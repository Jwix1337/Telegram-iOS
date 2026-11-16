# Winter Sync Service v1 (server only)

Python 3.10+ / FastAPI / SQLite, one process, no Redis, Docker or Telegram dependencies.
Local validation: `python3 -m unittest discover -s winter-sync -q`.
Install in a private virtualenv using requirements-test.txt for tests, requirements.txt for runtime.
ASGI factory: `app:create_app --factory` from winter-sync directory. Set WINTER_DB to a
persistent private path and WINTER_PROVISION_KEY to a randomly generated secret (>=32 chars).
No deployment or TLS/VPN/system configuration is included. A future operator must provide
HTTPS/WSS through an explicitly approved TLS endpoint. Never transmit credentials over plain HTTP.
Use one uvicorn worker and `--ws-max-size 1024 --limit-concurrency 64`; do not expose this
service or select/change any VPS port as part of this stage. SQLite DB is created mode 0600;
keep its directory and secret environment file private, back it up, never commit keys.

## Identity and pairing

Device IDs are server-issued opaque UUIDs, NOT Telegram identities. This protocol makes
no claim to verify a Telegram account. Provisioning is administrator-mediated, not open signup.
Every REST endpoint requires `Authorization: Bearer <device token>`, except provisioning
and device revocation which require the separate provisioning secret. Tokens are random
256-bit credentials, returned once; only SHA256 hashes are stored. Store client tokens in Keychain.

- POST /v1/devices: admin; returns {device_id,token}; no Telegram credentials accepted.
- GET /v1/device: device bearer; returns {device_id} for checking an imported credential.
- POST /v1/devices/{device_id}/revoke: admin; permanently invalidates device credential.
- POST /v1/pair-codes: device A; returns {code,expires_in:300}. Share code out of band.
- POST /v1/pairs/claim {code}: device B; consumes the 96-bit code atomically, returns pair_id.
- GET /v1/pairs: own pending/active pairs only, with a,b,ca,cb (mutual confirmation flags).
- POST /v1/pairs/{pair_id}/confirm: BOTH A and B must independently confirm the displayed
  peer device ID through their trusted channel. Claim alone grants no data access.
- DELETE /v1/pairs/{pair_id}: either participant immediately revokes sharing; code cannot
  reactivate it. Third parties get 404. A new code + mutual confirmation are required again.

## Events and snapshots

POST /v1/events body:
```
{"version":1,"event_id":"canonical-lowercase-uuid","pair_id":"uuid",
 "type":"snowman_update","session_id":"uuid","expected_version":2,
 "mutation":{"part":"bottom","value":1}}
```
Types: hat, snowball, snowman_invite, snowman_accept, snowman_update, snowman_complete.
No sender field: authenticated device determines sender_id. Unknown fields rejected (422).
Hat uses only `hat:{hat_id:1..10,enabled:bool,scale:0.35..2,x:-1..1,y:-1..1,
rotation:-pi..pi}`. Coordinates normalized to avatar dimensions; finite numbers only.
Snowball has no payload/session/version. Server created_at is UNIX seconds (not iOS milliseconds).
Snowman events require session_id and expected_version. Invite expects 0 and creates version 1;
only the other device can accept version 1, producing 2. Update adds one part in order:
bottom, middle, head, eyes, nose, arms, scarf, hat (value=1); scarfColor=0..5 and hatStyle=1..10
are independent style registers. Complete requires all 8 parts and freezes editing.
Each accepted snowman action increments the version. BEGIN IMMEDIATE serializes validation,
state update and event append. Concurrent same-version writers: one succeeds, other gets 409.
On 409 GET snapshot, merge user intent, explicitly retry with NEW event_id/current version.
Do not silently overwrite or reuse an old ID for changed payloads.

Response: {version:1,cursor,event:<validated request>,sender_id,created_at,state:<snowman snapshot including creator_id/created_at|null>}.
Same event ID + same authenticated sender + identical canonical request returns the original
response even after state changes. Changed data/sender with same ID ->409. Idempotency is durable.
GET /v1/pairs/{id}/state returns {version:1,cursor,hats,sessions}. Cursor is the global
journal high watermark in the same SQLite transaction (do NOT advance a client's replay cursor
from it). Each session snapshot includes session_id, version, creator_id, created_at (UNIX
seconds), accepted, completed, parts. creator_id is required to identify the invitee safely.
The optional created_at column is added on startup for earlier v1 databases; existing sessions
keep their state; creation time is recovered from the invitation journal, with migration time
used only if no historical invitation exists. Earlier event responses are enriched with the same
metadata on replay and idempotent retry, so upgrading cannot stall an iOS replay cursor.
Hats are per-device settings shared with its mutually confirmed pairs; enabled=false is a tombstone.
GET /v1/events?after=0 returns {events:[...]} sorted by global cursor, max100, active pairs only.
Persist the last processed cursor locally AFTER processing; deduplicate by event_id as well.
Continue paging until empty; cursor gaps are normal. State + event journal survive restarts.

## WebSocket

WSS /v1/ws; first TEXT frame within 5 seconds exactly {"token":"device credential","after":0}.
Token is never in URL/query. Subsequent server frames {events:[...]} have identical REST data;
empty frames are heartbeats each second. Client writes use authenticated REST, not WS commands.
On reconnect send last persisted cursor. Invalid auth/frame ->close1008; device revocation is
rechecked every poll. Pair revocation removes all its data from future frames. One in-flight
frame/request can precede a concurrent revocation. No iOS background animations/push assumed.

## Limits and operational boundaries

HTTP body 8192 bytes (including chunked); WS hello1024 bytes; extra fields disallowed.
Per device: requests240/min, events60/min, snowball1 per fixed3-second bucket, codes5/min,
claims10 successful/min; failed attempts also consume the general authenticated request budget.
Provisioning20/min. Limits persist in SQLite; 429 requires backoff. Fixed-window edges allow bursts.
Maximum32 active/pending pairs per device, 32 snowman sessions per pair, 10000 retained events
per pair (507 on exhaustion, no silent data loss). Event storage is retained for replay; there is
no automatic pruning/reset. Operator archival/quota lifecycle and key rotation UX are future work.
HTTP errors:401 bad auth,403 unconfirmed/invalid acceptance,404 inaccessible resource,
409 conflict/quota,413 size,422 schema,429 rate,507 event capacity. Retry transient DB/service
failures with backoff and same event ID. Do not log Authorization, hello frames or bodies.

No VPS deployment, background push, Telegram sessions/tokens/messages,
VPN changes, ports, certificates, firewall or system services are part of this implementation.


## Swift adapter (implemented separately in SnowEffect)
The iOS client requires the updated v1 identity and snapshot fields above. Provision device
credentials outside the app; enter only HTTPS origin/device UUID/device key in the chat's
Winter Sync setup. Keys use Keychain WhenUnlockedThisDeviceOnly, not UserDefaults or URLs.
Both users compare the remote device UUID in a trusted channel, confirm server pairing, then
explicitly associate the active pair with the selected Telegram chat LOCALLY. Telegram IDs
never enter HTTP/WS payloads. A credential cannot be reused across local Telegram accounts.
Server bindings are exclusive; unavailable/revoked/missing credentials never trigger technical
Telegram messages. Forgetting credentials pauses routes and discards queued server actions;
server-side device revocation is still an administrator operation.
The client persists immutable HTTP requests for idempotent retry. A 409 refreshes authoritative
state and blocks the old action until the user explicitly retries with a new ID. Versioned server
snapshots are projected onto the existing snowman UI; they do not enter the Telegram CRDT merge.
HTTP POST responses never advance replay cursors, so interleaved incoming events cannot be lost.
Foreground WS reconnects with bounded exponential backoff and cursor replay, and refreshes pairs
at least every 30 seconds to observe remote revocation. iOS background cancels all client tasks;
foreground resumes from durable state. Incoming snowballs expire after 120s and are consumed once.
