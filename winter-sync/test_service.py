import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from uuid import uuid4
from fastapi.testclient import TestClient
from app import create_app


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.key = 'p' * 48
        self.db = Path(self.tmp.name) / 'winter.db'
        self.now = [1800000000.0]
        self.app = create_app(self.db, self.key, lambda: self.now[0])
        self.client = TestClient(self.app)
        self.devices = [self.provision() for _ in range(3)]
        self.a, self.b, self.c = [d['token'] for d in self.devices]
        code = self.post('/v1/pair-codes', self.a).json()['code']
        self.pid = self.post('/v1/pairs/claim', self.b, {'code': code}).json()['pair_id']
        self.post(f'/v1/pairs/{self.pid}/confirm', self.a)
        self.post(f'/v1/pairs/{self.pid}/confirm', self.b)

    def tearDown(self):
        self.client.close()
        self.tmp.cleanup()

    def provision(self):
        r = self.client.post('/v1/devices', headers=self.headers(self.key))
        self.assertEqual(r.status_code, 201)
        return r.json()

    def headers(self, token):
        return {'Authorization': 'Bearer ' + token}

    def post(self, path, token, body=None):
        return self.client.post(path, headers=self.headers(token), json=body)

    def event(self, kind='snowball', **kw):
        return dict(version=1, event_id=str(uuid4()), pair_id=self.pid, type=kind, **kw)

    def test_auth_and_outsider_access(self):
        self.assertEqual(self.client.get('/v1/events').status_code, 401)
        self.assertEqual(self.client.get(f'/v1/pairs/{self.pid}/state', headers=self.headers(self.c)).status_code, 404)
        self.assertEqual(self.post('/v1/events', self.c, self.event()).status_code, 404)
        self.assertEqual(self.client.get('/v1/events', headers=self.headers(self.c)).json(), {'events': []})
        self.assertEqual(self.post('/v1/devices', self.a).status_code, 401)

    def test_pairing_code_single_use_expiry_and_mutual_confirmation(self):
        code = self.post('/v1/pair-codes', self.c).json()['code']
        pid = self.post('/v1/pairs/claim', self.a, {'code': code}).json()['pair_id']
        self.assertEqual(self.post('/v1/pairs/claim', self.b, {'code': code}).status_code, 400)
        value = {**self.event(), 'pair_id': pid}
        self.assertEqual(self.post('/v1/events', self.a, value).status_code, 403)
        self.post(f'/v1/pairs/{pid}/confirm', self.a)
        self.assertEqual(self.post('/v1/events', self.a, value).status_code, 403)
        self.post(f'/v1/pairs/{pid}/confirm', self.c)
        self.assertEqual(self.post('/v1/events', self.a, value).status_code, 200)
        code = self.post('/v1/pair-codes', self.c).json()['code']
        self.now[0] += 301
        self.assertEqual(self.post('/v1/pairs/claim', self.b, {'code': code}).status_code, 400)

    def test_idempotency_conflicts_rate_and_cursor_restart(self):
        event = self.event()
        first = self.post('/v1/events', self.a, event)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(self.post('/v1/events', self.a, event).json(), first.json())
        self.assertEqual(self.post('/v1/events', self.b, event).status_code, 409)
        self.assertEqual(self.post('/v1/events', self.a, self.event()).status_code, 429)
        restored = TestClient(create_app(self.db, self.key, lambda: self.now[0]))
        rows = restored.get('/v1/events', headers=self.headers(self.b)).json()['events']
        self.assertEqual(len(rows), 1)
        self.assertEqual(restored.get('/v1/events', params={'after': rows[-1]['cursor']}, headers=self.headers(self.b)).json()['events'], [])
        restored.close()

    def test_strict_validation_and_size(self):
        self.assertEqual(self.post('/v1/events', self.a, {**self.event(), 'telegram_token': 'forbidden'}).status_code, 422)
        self.assertEqual(self.post('/v1/events', self.a, {**self.event(), 'version': 2}).status_code, 422)
        self.assertEqual(self.post('/v1/events', self.a, {**self.event(), 'version': True}).status_code, 422)
        hat = dict(hat_id=1, enabled=True, scale=1.0, x=0.0, y=-.4, rotation=0.0)
        self.assertEqual(self.post('/v1/events', self.a, self.event('hat', hat=hat)).status_code, 200)
        hat['scale'] = 10.0
        self.assertEqual(self.post('/v1/events', self.a, self.event('hat', hat=hat)).status_code, 422)
        self.assertEqual(self.client.post('/v1/events', content='x' * 8193, headers=self.headers(self.a)).status_code, 413)

    def test_swift_identity_snapshot_contract_and_schema_migration(self):
        self.assertEqual(self.client.get('/v1/device', headers=self.headers(self.a)).json(),
                         {'device_id': self.devices[0]['device_id']})
        self.assertEqual(self.client.get('/v1/device').status_code, 401)
        sid = str(uuid4())
        invite = self.event('snowman_invite', session_id=sid, expected_version=0)
        result = self.post('/v1/events', self.a, invite).json()
        snapshot = self.client.get(f'/v1/pairs/{self.pid}/state', headers=self.headers(self.b)).json()
        self.assertEqual(snapshot['cursor'], result['cursor'])
        session = snapshot['sessions'][0]
        self.assertEqual(session['creator_id'], self.devices[0]['device_id'])
        self.assertEqual(session['created_at'], self.now[0])
        self.assertEqual(session['session_id'], sid)
        self.assertEqual(set(session), {'session_id', 'version', 'creator_id', 'created_at', 'accepted', 'completed', 'parts'})
        self.now[0] += 20
        accept = self.event('snowman_accept', session_id=sid, expected_version=1)
        accepted = self.post('/v1/events', self.b, accept).json()
        self.assertEqual(accepted['state']['created_at'], session['created_at'])
        self.assertEqual(accepted['state']['creator_id'], session['creator_id'])
        with sqlite3.connect(self.db) as connection:
            import json
            for seq, raw in connection.execute('SELECT seq,data FROM events').fetchall():
                data = json.loads(raw)
                if data['state'] is not None:
                    data['state'].pop('creator_id', None)
                    data['state'].pop('created_at', None)
                    connection.execute('UPDATE events SET data=? WHERE seq=?', (json.dumps(data), seq))
            connection.execute('ALTER TABLE sessions DROP COLUMN created_at')
        restored = TestClient(create_app(self.db, self.key, lambda: self.now[0]))
        migrated = restored.get(f'/v1/pairs/{self.pid}/state', headers=self.headers(self.a)).json()
        self.assertTrue(migrated['sessions'][0]['accepted'])
        self.assertEqual(migrated['sessions'][0]['created_at'], session['created_at'])
        replay = restored.get('/v1/events', headers=self.headers(self.b)).json()['events']
        self.assertTrue(all('creator_id' in item['state'] and 'created_at' in item['state'] for item in replay))
        retry = restored.post('/v1/events', headers=self.headers(self.a), json=invite).json()
        self.assertEqual(retry['state']['creator_id'], self.devices[0]['device_id'])
        restored.close()

    def test_snapshot_watermark_covers_global_hat_changes(self):
        code = self.post('/v1/pair-codes', self.b).json()['code']
        pid = self.post('/v1/pairs/claim', self.c, {'code': code}).json()['pair_id']
        self.post(f'/v1/pairs/{pid}/confirm', self.b)
        self.post(f'/v1/pairs/{pid}/confirm', self.c)
        event = {**self.event('hat', hat=dict(hat_id=4, enabled=True, scale=1.0, x=0.0, y=0.0, rotation=0.0)), 'pair_id': pid}
        result = self.post('/v1/events', self.b, event).json()
        snapshot = self.client.get(f'/v1/pairs/{self.pid}/state', headers=self.headers(self.a)).json()
        self.assertEqual(snapshot['cursor'], result['cursor'])
        self.assertEqual(snapshot['hats'][self.devices[1]['device_id']]['hat_id'], 4)
        self.assertEqual(self.client.get('/v1/events', headers=self.headers(self.a)).json()['events'], [])

    def test_keys_hats_and_modified_payload_replay(self):
        hat = dict(hat_id=3, enabled=True, scale=1.0, x=0.0, y=-.4, rotation=0.0)
        event = self.event('hat', hat=hat)
        self.assertEqual(self.post('/v1/events', self.a, event).status_code, 200)
        event['hat']['enabled'] = False
        self.assertEqual(self.post('/v1/events', self.a, event).status_code, 409)
        event['event_id'] = str(uuid4())
        self.assertEqual(self.post('/v1/events', self.a, event).status_code, 200)
        state = self.client.get(f'/v1/pairs/{self.pid}/state', headers=self.headers(self.b)).json()
        self.assertFalse(state['hats'][self.devices[0]['device_id']]['enabled'])
        with sqlite3.connect(self.db) as connection:
            hashes = [r[0] for r in connection.execute('SELECT token FROM devices')]
        self.assertNotIn(self.a, hashes)
        self.assertTrue(all(len(value) == 64 for value in hashes))
        self.assertEqual(self.db.stat().st_mode & 0o777, 0o600)

    def test_websocket_rejects_unauthorized_and_invalid_hello(self):
        from starlette.websockets import WebSocketDisconnect
        for hello in [{'token': 'invalid', 'after': 0}, {'token': self.a, 'after': -1}]:
            with self.client.websocket_connect('/v1/ws') as ws:
                ws.send_json(hello)
                with self.assertRaises(WebSocketDisconnect):
                    ws.receive_json()

    def test_atomic_snowman_versions_and_completion(self):
        sid = str(uuid4())
        def event(kind, ver, **kw):
            return self.event(kind, session_id=sid, expected_version=ver, **kw)
        self.assertEqual(self.post('/v1/events', self.a, event('snowman_invite', 0)).status_code, 200)
        self.assertEqual(self.post('/v1/events', self.a, event('snowman_accept', 1)).status_code, 403)
        self.assertEqual(self.post('/v1/events', self.b, event('snowman_accept', 1)).status_code, 200)
        updates = [event('snowman_update', 2, mutation={'part': 'bottom', 'value': 1}) for _ in range(2)]
        with ThreadPoolExecutor(2) as pool:
            codes = list(pool.map(lambda body: self.post('/v1/events', self.a, body).status_code, updates))
        self.assertEqual(sorted(codes), [200, 409])
        self.assertEqual(self.post('/v1/events', self.a, event('snowman_complete', 3)).status_code, 409)
        version = 3
        for part in ['middle', 'head', 'eyes', 'nose', 'arms', 'scarf', 'hat']:
            response = self.post('/v1/events', self.b, event('snowman_update', version, mutation={'part': part, 'value': 1}))
            self.assertEqual(response.status_code, 200, response.text)
            version += 1
        self.assertEqual(self.post('/v1/events', self.a, event('snowman_complete', version)).status_code, 200)
        state = self.client.get(f'/v1/pairs/{self.pid}/state', headers=self.headers(self.a)).json()
        self.assertTrue(state['sessions'][0]['completed'])

    def test_revocation_and_websocket_recovery(self):
        sent = self.post('/v1/events', self.a, self.event()).json()
        with self.client.websocket_connect('/v1/ws') as ws:
            ws.send_json({'token': self.b, 'after': 0})
            self.assertEqual(ws.receive_json()['events'][0], sent)
        self.client.delete(f'/v1/pairs/{self.pid}', headers=self.headers(self.a))
        self.assertEqual(self.client.get('/v1/events', headers=self.headers(self.b)).json()['events'], [])
        self.assertEqual(self.post('/v1/events', self.b, self.event()).status_code, 404)
        self.post('/v1/devices/' + self.devices[1]['device_id'] + '/revoke', self.key)
        self.assertEqual(self.client.get('/v1/events', headers=self.headers(self.b)).status_code, 401)
        with self.client.websocket_connect('/v1/ws') as ws:
            ws.send_json({'token': self.c, 'after': 0})
            self.assertEqual(ws.receive_json()['events'], [])


if __name__ == '__main__':
    unittest.main()
