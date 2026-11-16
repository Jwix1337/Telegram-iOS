"""Real ASGI/SQLite interactions between independent HTTP clients, not a Swift simulation."""
import unittest
import sqlite3
from unittest.mock import patch
from uuid import uuid4
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
import test_service
from app import create_app


class IntegrationTests(unittest.TestCase):
    def setUp(self):
        self.h = test_service.ServiceTests()
        self.h.setUp()
        self.a = TestClient(self.h.app)
        self.b = TestClient(self.h.app)

    def tearDown(self):
        self.a.close()
        self.b.close()
        self.h.tearDown()

    def send(self, client, token, event):
        return client.post('/v1/events', headers=self.h.headers(token), json=event)

    def test_two_clients_replay_hats_snowballs_and_conflict_recovery(self):
        h = self.h
        hat = h.event('hat', hat=dict(hat_id=5, enabled=True, scale=1.2, x=.1, y=-.4, rotation=.2))
        sent = self.send(self.a, h.a, hat).json()
        snapshot = self.b.get(f'/v1/pairs/{h.pid}/state', headers=h.headers(h.b)).json()
        self.assertEqual(snapshot['hats'][h.devices[0]['device_id']]['hat_id'], 5)
        cursor = sent['cursor']
        ball = h.event()
        first = self.send(self.a, h.a, ball).json()
        self.assertEqual(self.send(self.a, h.a, ball).json(), first)
        sid = str(uuid4())
        def action(kind, version, **kw):
            return h.event(kind, session_id=sid, expected_version=version, **kw)
        self.assertEqual(self.send(self.a, h.a, action('snowman_invite', 0)).status_code, 200)
        self.assertEqual(self.send(self.b, h.b, action('snowman_accept', 1)).status_code, 200)
        update_a = action('snowman_update', 2, mutation={'part': 'bottom', 'value': 1})
        update_b = action('snowman_update', 2, mutation={'part': 'bottom', 'value': 1})
        self.assertEqual(self.send(self.a, h.a, update_a).status_code, 200)
        self.assertEqual(self.send(self.b, h.b, update_b).status_code, 409)
        state = self.b.get(f'/v1/pairs/{h.pid}/state', headers=h.headers(h.b)).json()['sessions'][0]
        self.assertEqual(state['version'], 3)
        retry = action('snowman_update', state['version'], mutation={'part': 'middle', 'value': 1})
        self.assertEqual(self.send(self.b, h.b, retry).status_code, 200)
        # Server restarts while B is disconnected: durable replay returns the snowball exactly once.
        self.b.close()
        self.b = TestClient(create_app(h.db, h.key, lambda: h.now[0]))
        events = self.b.get('/v1/events', params={'after': cursor}, headers=h.headers(h.b)).json()['events']
        self.assertEqual(sum(e['event']['event_id'] == ball['event_id'] for e in events), 1)
        self.assertEqual(self.b.get('/v1/events', params={'after': events[-1]['cursor']}, headers=h.headers(h.b)).json()['events'], [])
        final_a = self.a.get(f'/v1/pairs/{h.pid}/state', headers=h.headers(h.a)).json()
        final_b = self.b.get(f'/v1/pairs/{h.pid}/state', headers=h.headers(h.b)).json()
        self.assertEqual(final_a, final_b)
        hat['event_id'] = str(uuid4()); hat['hat']['enabled'] = False
        self.assertEqual(self.send(self.a, h.a, hat).status_code, 200)
        disabled = self.b.get(f'/v1/pairs/{h.pid}/state', headers=h.headers(h.b)).json()
        self.assertFalse(disabled['hats'][h.devices[0]['device_id']]['enabled'])

    def test_storage_outage_does_not_acknowledge_or_duplicate_event(self):
        h = self.h
        event = h.event()
        unavailable = TestClient(h.app, raise_server_exceptions=False)
        with patch('app.sqlite3.connect', side_effect=sqlite3.OperationalError('simulated outage')):
            response = self.send(unavailable, h.a, event)
            self.assertEqual(response.status_code, 500)
        unavailable.close()
        accepted = self.send(self.a, h.a, event)
        self.assertEqual(accepted.status_code, 200)
        self.assertEqual(self.send(self.a, h.a, event).json(), accepted.json())
        rows = self.b.get('/v1/events', headers=h.headers(h.b)).json()['events']
        self.assertEqual(len(rows), 1)

    def test_revocation_disconnects_already_authenticated_websocket(self):
        h = self.h
        with self.b.websocket_connect('/v1/ws') as socket:
            socket.send_json({'token': h.b, 'after': 0})
            self.assertEqual(socket.receive_json()['events'], [])
            self.a.post('/v1/devices/' + h.devices[1]['device_id'] + '/revoke', headers=h.headers(h.key))
            with self.assertRaises(WebSocketDisconnect):
                socket.receive_json()


if __name__ == '__main__':
    unittest.main()
