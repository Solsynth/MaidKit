# End-to-end encrypted cloud sync design

## Purpose

MaidKit syncs selected user-managed data between devices in near real time.
The cloud service authenticates devices, orders changes, and relays encrypted
payloads. It must not be able to read server addresses, credentials, scripts,
or deployment data.

## Sync scope

The following records are synchronized:

- Servers and their SSH credentials
- Compose project links
- Deployment projects and deployment resources
- Script snippets

The following records remain local to a device:

- Vault metadata, biometric state, and local database encryption keys
- Active SSH sessions, terminal layout, and refresh preferences
- Container cache entries and `lastConnectedAt`
- Learned SSH host-key fingerprints. Trusting a host key is a device-local
  security decision.

The device-local records above are not merely left unapplied on the receiving
device; they are dropped before the payload leaves the client. They change
from ordinary use — connecting to a server, listing containers — so including
them would make a device publish a new revision while the user edited nothing,
and would turn two devices' differing connect times into an equal-timestamp
conflict. Connecting to a server therefore must not touch `Servers.updatedAt`.

## Encryption

The client derives a workspace sync key from the vault password and a
workspace-specific public salt. The service stores the salt, but it never
receives the vault password or a derived key.

```text
sync key = KDF(vault password, workspace public salt, "maidkit-sync-v1")
record key = HKDF(sync key, record identifier)
```

Records are encrypted on the client with AES-GCM before upload. The encrypted
payload includes the entity type, stable entity identifier, operation, revision
clock, and data. This keeps the service unaware of both data and record type.

When a server credential is synchronized, it is decrypted only in application
memory, included in the encrypted sync payload, then encrypted with the local
vault key on the receiving device before it is written to Drift.

The vault password is required when adding a device to a workspace. Existing
local vault encryption continues to work independently of sync.

## Identity and local storage

Every synchronized entity has a stable UUID. Local SQLite integer IDs are not
synchronized. Cross-record references use stable UUIDs, such as a deployment
resource's server reference.

Add these Drift tables:

| Table | Responsibility |
| --- | --- |
| `sync_workspace` | Server URL, workspace ID, device ID, public salt, and latest applied cursor. |
| `sync_records` | Stable entity ID, local-record mapping, current revision clock, and tombstone state. |
| `sync_outbox` | Locally encrypted operations awaiting upload, with retry information. |

The existing `servers.syncId` becomes the server's stable entity ID. Other
entity types use `sync_records` to avoid spreading sync-specific columns across
the application schema.

## Operation format

The transport envelope is intentionally opaque to the service:

```json
{
  "operationId": "uuid",
  "deviceId": "uuid",
  "clock": "2026-07-22T12:34:56.123Z-0001-device-id",
  "ciphertext": "base64url-aes-gcm-payload"
}
```

The decrypted content has this shape:

```json
{
  "entityType": "server",
  "entityId": "uuid",
  "action": "upsert",
  "record": {}
}
```

Deletes create encrypted tombstones. Tombstones are retained until every active
device has acknowledged a cursor past the operation, or until a conservative
server retention period expires.

## Client sync flow

1. A feature repository writes a local change and registers it with the sync
   tracker in the same Drift transaction.
2. The tracker encrypts an operation and stores it in `sync_outbox`.
3. The sync engine uploads queued operations, with idempotency based on
   `operationId`.
4. The engine pulls operations after its saved cursor.
5. It decrypts and applies them in a Drift transaction, without adding those
   remote changes back to the outbox.
6. A Server-Sent Events notification tells the client that a pull is needed,
   enabling near-realtime updates without relying on the notification as a data
   channel.

## Conflict handling

Simultaneous edits are expected to be rare. The initial release therefore uses
last-write-wins with a hybrid logical clock. Device ID is a deterministic
tie-breaker when clocks compare equally. A deletion wins when its revision is
newer than, or equal to, a competing update.

This policy lets the service remain blind to record content. Future versions can
retain encrypted history and present manual resolution for sensitive conflicts,
particularly SSH credentials.

## Service contract

The service stores accounts, workspaces, device registrations, opaque operation
blobs, and monotonically increasing workspace cursors. It deduplicates uploads
by `operationId`.

```text
POST /auth/session
POST /workspaces
POST /workspaces/{workspaceId}/devices

POST /workspaces/{workspaceId}/operations
GET  /workspaces/{workspaceId}/operations?after={cursor}&limit={limit}

GET  /workspaces/{workspaceId}/events  (Server-Sent Events)
```

The SSE stream sends only an indication that changes are available, optionally
including the latest cursor. The client uses
`GET /workspaces/{workspaceId}/operations` to retrieve data in cursor order.
SSE reconnects naturally with `Last-Event-ID`; on reconnect, the client still
performs a cursor-based pull so no operation depends on an event being kept.

An event is intentionally small and does not repeat the encrypted operation:

```text
id: 4812
event: changes-available
data: {"cursor":"4812"}
```

The client keeps one authenticated SSE connection while sync is enabled. A
successful `POST /operations` can return its accepted cursor immediately; the
SSE event remains the mechanism that informs other connected devices.

## Client implementation layout

Keep this feature flat under `lib/sync/`:

```text
lib/sync/
  sync_models.dart
  sync_crypto.dart
  sync_api.dart
  sync_repository.dart
  sync_engine.dart
  sync_providers.dart
  sync_settings_section.dart
```

## Delivery phases

1. Add local sync identity, record mappings, encrypted outbox, and tests.
2. Add workspace setup and a manual Sync now action in Settings.
3. Implement upload and pull against the service contract.
4. Add SSE-driven sync, retry/backoff, and sync-status UI.
5. Add key rotation, encrypted conflict history, and optional manual conflict
   resolution.
