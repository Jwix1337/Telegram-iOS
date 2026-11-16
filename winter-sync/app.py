"""Winter Sync v1: no Telegram credentials, sessions or chat content."""
import asyncio
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Literal
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, HTTPException, Query, Request, WebSocket
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, model_validator

PARTS = ('bottom', 'middle', 'head', 'eyes', 'nose', 'arms', 'scarf', 'hat')


class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True, allow_inf_nan=False)


class Code(Strict):
    code: str = Field(min_length=16, max_length=32)


class Hat(Strict):
    hat_id: int = Field(ge=1, le=10)
    enabled: bool
    scale: float = Field(ge=.35, le=2)
    x: float = Field(ge=-1, le=1)
    y: float = Field(ge=-1, le=1)
    rotation: float = Field(ge=-3.141592653589793, le=3.141592653589793)


class Mutation(Strict):
    part: Literal['bottom', 'middle', 'head', 'eyes', 'nose', 'arms', 'scarf', 'hat', 'scarfColor', 'hatStyle']
    value: int

    @model_validator(mode='after')
    def valid(self):
        limit = range(6) if self.part == 'scarfColor' else range(1, 11) if self.part == 'hatStyle' else [1]
        if self.value not in limit:
            raise ValueError('invalid part value')
        return self


class Event(Strict):
    version: int = Field(ge=1, le=1)
    event_id: str
    pair_id: str
    type: Literal['hat', 'snowball', 'snowman_invite', 'snowman_accept', 'snowman_update', 'snowman_complete']
    session_id: str | None = None
    expected_version: int | None = Field(default=None, ge=0, le=1000000)
    hat: Hat | None = None
    mutation: Mutation | None = None

    @model_validator(mode='after')
    def valid(self):
        for value in [self.event_id, self.pair_id] + ([self.session_id] if self.session_id else []):
            if str(UUID(value)) != value:
                raise ValueError('canonical lowercase UUID required')
        if self.type == 'hat':
            good = self.hat is not None and self.mutation is None and self.session_id is None and self.expected_version is None
        elif self.type == 'snowball':
            good = all(x is None for x in [self.hat, self.mutation, self.session_id, self.expected_version])
        else:
            good = self.hat is None and self.session_id is not None and self.expected_version is not None
            good = good and ((self.mutation is not None) == (self.type == 'snowman_update'))
        if not good:
            raise ValueError('invalid event shape')
        return self


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def create_app(db_path=None, admin_key=None, clock=time.time):
    path = Path(db_path or os.environ.get('WINTER_DB', 'winter.sqlite3')).resolve()
    key = admin_key or os.environ.get('WINTER_PROVISION_KEY', '')
    if len(key) < 32:
        raise RuntimeError('WINTER_PROVISION_KEY must contain at least 32 random characters')
    path.parent.mkdir(parents=True, exist_ok=True)
    # Create with restrictive permissions before SQLite opens it; directory must be private too.
    fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
    os.close(fd)
    os.chmod(path, 0o600)

    @contextmanager
    def db():
        c = sqlite3.connect(path, timeout=5, isolation_level=None)
        c.row_factory = sqlite3.Row
        c.execute('PRAGMA foreign_keys=ON')
        try:
            c.execute('BEGIN IMMEDIATE')
            yield c
            c.commit()
        except Exception:
            c.rollback()
            raise
        finally:
            c.close()

    with db() as c:
        if c.execute('PRAGMA user_version').fetchone()[0] not in (0, 1):
            raise RuntimeError('unsupported SQLite schema version')
        c.executescript('''
        CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, token TEXT UNIQUE, revoked INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS codes(hash TEXT PRIMARY KEY, owner TEXT NOT NULL, expires REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS pairs(id TEXT PRIMARY KEY,a TEXT NOT NULL,b TEXT NOT NULL,ca INTEGER DEFAULT 0,cb INTEGER DEFAULT 0,revoked INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS hats(owner TEXT PRIMARY KEY,data TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY,pair TEXT NOT NULL,creator TEXT NOT NULL,version INTEGER NOT NULL,data TEXT NOT NULL,created_at REAL NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT UNIQUE NOT NULL,pair TEXT NOT NULL,owner TEXT NOT NULL,hash TEXT NOT NULL,data TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS events_pair_seq ON events(pair,seq);
        CREATE TABLE IF NOT EXISTS rates(key TEXT PRIMARY KEY,bucket INTEGER,count INTEGER);
        PRAGMA user_version=1;
        ''')
        if 'created_at' not in [r[1] for r in c.execute('PRAGMA table_info(sessions)')]:
            c.execute('ALTER TABLE sessions ADD COLUMN created_at REAL NOT NULL DEFAULT 0')
        if c.execute('SELECT 1 FROM sessions WHERE created_at=0 LIMIT 1').fetchone():
            # Recover original invitation time from the existing journal, without JSON1 dependencies.
            for row in c.execute('SELECT data FROM events'):
                data = json.loads(row['data'])
                if data['event']['type'] == 'snowman_invite':
                    c.execute('UPDATE sessions SET created_at=? WHERE id=? AND created_at=0',
                              (data['created_at'], data['event']['session_id']))
            c.execute('UPDATE sessions SET created_at=? WHERE created_at=0', (clock(),))
    app = FastAPI(title='Winter Sync', version='1.0.0', docs_url=None, redoc_url=None, openapi_url=None)
    bearer = HTTPBearer(auto_error=False)

    def fail(status, detail):
        raise HTTPException(status, detail)

    def rate(c, scope, limit=60, window=60):
        bucket = int(clock() // window)
        c.execute('DELETE FROM rates WHERE bucket < ?', (int(clock() // 60) - 3600,))
        row = c.execute('SELECT bucket,count FROM rates WHERE key=?', (scope,)).fetchone()
        count = row['count'] + 1 if row and row['bucket'] == bucket else 1
        if count > limit:
            fail(429, 'rate limit')
        c.execute('INSERT OR REPLACE INTO rates VALUES(?,?,?)', (scope, bucket, count))

    def identify(token):
        with db() as c:
            row = c.execute('SELECT id FROM devices WHERE token=? AND revoked=0', (digest(token),)).fetchone()
            if not row:
                fail(401, 'invalid device credential')
            rate(c, 'request:' + row['id'], 240)
            return row['id']

    def auth(credential: HTTPAuthorizationCredentials | None = Depends(bearer)):
        if not credential or credential.scheme.lower() != 'bearer':
            fail(401, 'bearer credential required')
        return identify(credential.credentials)

    def admin(credential: HTTPAuthorizationCredentials | None = Depends(bearer)):
        if not credential or not hmac.compare_digest(digest(credential.credentials), digest(key)):
            fail(401, 'provisioning credential required')

    def pair(c, pair_id, who, active=True):
        row = c.execute('SELECT * FROM pairs WHERE id=? AND (a=? OR b=?) AND revoked=0', (pair_id, who, who)).fetchone()
        if not row:
            fail(404, 'pair not found')
        if active and not (row['ca'] and row['cb']):
            fail(403, 'mutual confirmation required')
        return row

    @app.middleware('http')
    async def boundary(request: Request, call_next):
        # Stream cap also covers chunked bodies, before JSON parsing.
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > 8192:
                from fastapi.responses import JSONResponse
                return JSONResponse({'detail': 'payload too large'}, status_code=413)
        request._body = bytes(body)
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        return response

    @app.post('/v1/devices', dependencies=[Depends(admin)], status_code=201)
    def provision():
        token = secrets.token_urlsafe(32)
        device = str(uuid4())
        with db() as c:
            rate(c, 'provision', 20)
            c.execute('INSERT INTO devices(id,token) VALUES(?,?)', (device, digest(token)))
        return {'device_id': device, 'token': token}

    @app.get('/v1/device')
    def identity(who=Depends(auth)):
        return {'device_id': who}

    @app.post('/v1/devices/{device}/revoke', dependencies=[Depends(admin)])
    def revoke_device(device: str):
        with db() as c:
            c.execute('UPDATE devices SET revoked=1 WHERE id=?', (device,))
        return {'revoked': True}

    @app.post('/v1/pair-codes', status_code=201)
    def code(who=Depends(auth)):
        value = secrets.token_urlsafe(12)
        with db() as c:
            rate(c, 'codes:' + who, 5)
            c.execute('DELETE FROM codes WHERE expires<? OR owner=?', (clock(), who))
            c.execute('INSERT INTO codes VALUES(?,?,?)', (digest(value), who, clock() + 300))
        return {'code': value, 'expires_in': 300}

    @app.post('/v1/pairs/claim', status_code=201)
    def claim(body: Code, who=Depends(auth)):
        with db() as c:
            rate(c, 'claim:' + who, 10)
            row = c.execute('SELECT * FROM codes WHERE hash=? AND expires>?', (digest(body.code), clock())).fetchone()
            if not row or row['owner'] == who:
                fail(400, 'invalid or expired code')
            if c.execute('SELECT count(*) FROM pairs WHERE (a=? OR b=?) AND revoked=0', (who, who)).fetchone()[0] >= 32 or c.execute('SELECT count(*) FROM pairs WHERE (a=? OR b=?) AND revoked=0', (row['owner'], row['owner'])).fetchone()[0] >= 32:
                fail(409, 'pair quota exceeded')
            pid = str(uuid4())
            c.execute('DELETE FROM codes WHERE hash=?', (digest(body.code),))
            c.execute('INSERT INTO pairs(id,a,b) VALUES(?,?,?)', (pid, row['owner'], who))
        return {'pair_id': pid}

    @app.get('/v1/pairs')
    def pairs(who=Depends(auth)):
        with db() as c:
            return [dict(r) for r in c.execute('SELECT * FROM pairs WHERE (a=? OR b=?) AND revoked=0', (who, who))]

    @app.post('/v1/pairs/{pid}/confirm')
    def confirm(pid: str, who=Depends(auth)):
        with db() as c:
            row = pair(c, pid, who, False)
            c.execute('UPDATE pairs SET ' + ('ca' if row['a'] == who else 'cb') + '=1 WHERE id=?', (pid,))
            row = pair(c, pid, who, False)
            return {'active': bool(row['ca'] and row['cb'])}

    @app.delete('/v1/pairs/{pid}')
    def revoke(pid: str, who=Depends(auth)):
        with db() as c:
            pair(c, pid, who, False)
            c.execute('UPDATE pairs SET revoked=1 WHERE id=?', (pid,))
        return {'revoked': True}

    def wire_event(c, serialized):
        data = json.loads(serialized)
        state = data.get('state')
        if state is not None and ('creator_id' not in state or 'created_at' not in state):
            session = c.execute('SELECT creator,created_at FROM sessions WHERE id=? AND pair=?',
                                (state['session_id'], data['event']['pair_id'])).fetchone()
            if session is None:
                fail(503, 'session metadata unavailable')
            state['creator_id'], state['created_at'] = session['creator'], session['created_at']
        return data

    @app.post('/v1/events')
    def publish(body: Event, who=Depends(auth)):
        canonical = body.model_dump_json()
        with db() as c:
            pair(c, body.pair_id, who)
            prior = c.execute('SELECT * FROM events WHERE id=?', (body.event_id,)).fetchone()
            if prior:
                if prior['owner'] != who or prior['hash'] != digest(canonical):
                    fail(409, 'event ID reused with different data')
                return wire_event(c, prior['data'])
            rate(c, 'events:' + who, 60)
            if body.type == 'snowball':
                rate(c, 'snowball:' + who, 1, 3)
            if c.execute('SELECT count(*) FROM events WHERE pair=?', (body.pair_id,)).fetchone()[0] >= 10000:
                fail(507, 'event storage quota exceeded')
            snapshot = None
            if body.type == 'hat':
                c.execute('INSERT OR REPLACE INTO hats VALUES(?,?)', (who, body.hat.model_dump_json()))
            elif body.type.startswith('snowman_'):
                row = c.execute('SELECT * FROM sessions WHERE id=?', (body.session_id,)).fetchone()
                if body.type == 'snowman_invite':
                    if c.execute('SELECT count(*) FROM sessions WHERE pair=?', (body.pair_id,)).fetchone()[0] >= 32:
                        fail(409, 'session quota exceeded')
                    if row or body.expected_version != 0:
                        fail(409, 'session exists or invalid initial version')
                    state = {'accepted': False, 'completed': False, 'parts': {}}
                    creator, version, created_at = who, 0, clock()
                else:
                    if not row or row['pair'] != body.pair_id:
                        fail(404, 'session not found')
                    state, creator, version, created_at = json.loads(row['data']), row['creator'], row['version'], row['created_at']
                    if version != body.expected_version:
                        fail(409, 'version conflict; refresh state')
                    if body.type == 'snowman_accept':
                        if creator == who or state['accepted']:
                            fail(403, 'only invitee may accept once')
                        state['accepted'] = True
                    else:
                        if not state['accepted'] or state['completed']:
                            fail(409, 'session not editable')
                        if body.type == 'snowman_update':
                            part, value = body.mutation.part, body.mutation.value
                            if part in PARTS and not all(p in state['parts'] for p in PARTS[:PARTS.index(part)]):
                                fail(409, 'missing prior assembly stage')
                            state['parts'][part] = value
                        else:
                            if not all(p in state['parts'] for p in PARTS):
                                fail(409, 'snowman incomplete')
                            state['completed'] = True
                version += 1
                c.execute('INSERT OR REPLACE INTO sessions VALUES(?,?,?,?,?,?)', (body.session_id, body.pair_id, creator, version, json.dumps(state), created_at))
                snapshot = {'session_id': body.session_id, 'version': version, 'creator_id': creator, 'created_at': created_at, **state}
            data = {'version': 1, 'event': body.model_dump(), 'sender_id': who, 'created_at': clock(), 'state': snapshot}
            c.execute('INSERT INTO events(id,pair,owner,hash,data) VALUES(?,?,?,?,?)', (body.event_id, body.pair_id, who, digest(canonical), json.dumps(data)))
            data['cursor'] = c.execute('SELECT last_insert_rowid()').fetchone()[0]
            c.execute('UPDATE events SET data=? WHERE id=?', (json.dumps(data), body.event_id))
            return data

    @app.get('/v1/pairs/{pid}/state')
    def state(pid: str, who=Depends(auth)):
        with db() as c:
            p = pair(c, pid, who)
            return {'version': 1, 'cursor': c.execute('SELECT coalesce(max(seq),0) FROM events').fetchone()[0], 'hats': {r['owner']: json.loads(r['data']) for r in c.execute('SELECT * FROM hats WHERE owner IN (?,?)', (p['a'], p['b']))},
                    'sessions': [{'session_id': r['id'], 'version': r['version'], 'creator_id': r['creator'], 'created_at': r['created_at'], **json.loads(r['data'])} for r in c.execute('SELECT * FROM sessions WHERE pair=?', (pid,))]}

    def backlog(who, after):
        with db() as c:
            return [wire_event(c, r['data']) for r in c.execute('''SELECT e.data FROM events e JOIN pairs p ON p.id=e.pair
                WHERE e.seq>? AND (p.a=? OR p.b=?) AND p.ca=1 AND p.cb=1 AND p.revoked=0
                ORDER BY e.seq LIMIT 100''', (after, who, who))]

    @app.get('/v1/events')
    def events(after: int = Query(0, ge=0, le=2**63-1), who=Depends(auth)):
        return {'events': backlog(who, after)}

    @app.websocket('/v1/ws')
    async def websocket(ws: WebSocket):
        await ws.accept()
        try:
            raw = await asyncio.wait_for(ws.receive_text(), 5)
            if len(raw.encode()) > 1024:
                await ws.close(code=1008)
                return
            hello = json.loads(raw)
            if set(hello) != {'token', 'after'} or type(hello['after']) is not int or not 0 <= hello['after'] <= 2**63-1:
                await ws.close(code=1008)
                return
            token, cursor = hello['token'], hello['after']
            if not isinstance(token, str) or len(token) > 256:
                await ws.close(code=1008)
                return
            while True:
                who = await asyncio.to_thread(identify, token)
                rows = await asyncio.to_thread(backlog, who, cursor)
                await ws.send_json({'events': rows})
                if rows:
                    cursor = rows[-1]['cursor']
                await asyncio.sleep(1)
        except Exception:
            await ws.close(code=1008)

    return app
