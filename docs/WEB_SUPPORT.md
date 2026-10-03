# Web support

MaidKit builds for the browser with `flutter build web`. This document records
what runs there, how the native-only code is isolated, what a deployment needs,
and what is still open.

## What runs in a browser

| Area | Browser build |
| --- | --- |
| Terminal rendering | `xterm3` (see `docs/TERMINAL_EMU_ADAPTER.md`) |
| Terminals | MaidCafe daemon terminals over WebSocket — the only transport that needs no raw socket |
| Server statistics | MaidCafe daemon `/api/v1/metrics` over HTTP(S) — the only statistics route that needs no SSH |
| Servers, settings, snippets, GitHub, projects, cloud sync | Local database + HTTP(S) |
| SSH, serial, local shells | Unavailable (no raw sockets) |
| File management, file editor | MaidCafe daemon `/api/v1/files` over HTTP(S) for a remote server; the local pane is absent (no local filesystem in a browser) |
| Containers | MaidCafe daemon `/api/v1/containers` and its per-container reads, over HTTP(S). Exec, attach and re-create-from-inspect stay SSH-only |
| Port forwarding, systemd, web servers, packages, firewall | Unavailable (SSH or local filesystem) |
| Tailscale, network ping | Unavailable (native runtime) |
| Local MCP server, agent processes | Unavailable (no child processes) |
| Desktop window control, system notifications, biometric unlock, system fonts | Unavailable (no plugin) |

Unavailable surfaces are hidden, and the entry points that funnel into them
report why. `server_connection_actions.dart` is the single gate for "this needs
a connection a browser cannot make": `connectForStatistics` returns early on web
with the `serverTerminalUnavailableInBrowser` message, and `openTerminalSession`
does the same unless the server carries a MaidCafe route — a daemon endpoint, a
cloud relay identity, or the port a native client learned for it — in which case
the terminal is opened over the daemon. The terminal command palette lists only
MaidCafe servers there.

Every server card's context menu names the MaidCafe transports explicitly
("Open terminal via daemon", "Open terminal via cloud relay") and adds a
connectivity check. The check resolves each configured route, reads `/health`,
and completes a real terminal handshake, so a firewall, an unlisted origin, or a
wrong endpoint shows up before a session is opened. On a native client the
daemon route uses the server's own loopback through a temporary SSH forward when
one is needed, and the browser build dials the server host on the learned port
instead.

### Host statistics over the daemon

A host whose daemon answers on an address this client can dial reports its load,
memory, swap, disk and uptime over `/api/v1/metrics` — **no SSH session is
opened for them**, on any platform. `MaidCafeStatsCollector`
(`lib/servers/maidcafe_stats.dart`) resolves that address with
`maidCafeBrowserTerminalUrl`, the same view a browser gets: the endpoint override
when one is stored, otherwise the server host on the port the daemon reported. A
daemon that only listens on the server's own loopback therefore has no direct
route, so it falls back to the SSH collectors rather than opening a forward —
the point of the route is that it costs the server no connection at all.

`MaidCafeStatsScheduler` polls on the same cadence as the SSH path, driven by
`maidCafeStatsSchedulerProvider` from `app.dart` so a browser build collects
statistics without any tab asking first. Cards and the server detail page read
`maidCafeStatsProvider` first and fall back to the SSH session's numbers; a
daemon-backed card is live — `connected` — with no SSH session, and its status
chip says *"Live from the MaidCafe daemon — no SSH session"* instead of a
latency readout it never measured. When a daemon stops answering, its snapshot
is withdrawn instead of being left on screen as if it were current.

The daemon serves this only to a caller that presents its terminal secret or,
when none is set, its metrics secret — the same fallback the daemon applies to
`daemon.terminal.secret`. A browser reaching a plain-HTTP daemon from an HTTPS
page is blocked as mixed content, so that combination needs the TLS front the
endpoint override section describes; a WebSocket terminal has the same
requirement.

Detecting an installed daemon over SSH configures that shell route by itself —
endpoint, port, credential, and cloud identity — and a finished install does the
same, so neither needs the editor to be filled in by hand. When the direct route
does not answer, the failure names the TCP port to expose (and the address the
daemon listens on) instead of only reporting that the connection failed.

The daemon's own terminal switch (`daemon.terminal.enabled`) is checked before
that advice: a daemon whose terminal endpoint is off refuses every session, so
the message is to enable it rather than to open a port. The switch is read from
the daemon configuration over SSH and stored on the server row, so the check can
report it on a client that has no SSH session of its own.

Those settings are editable in the MaidCafe tab's configuration editor: the
terminal switch, its secret, and its allowed origins are exposed there, and
saving patches the `[daemon.terminal]` table in place — comments, unknown keys,
and the rest of the file stay as the daemon wrote them. A daemon registered in
the workspace is found again by the server's name when the row never stored its
uuid — and a stored uuid the workspace no longer has is repaired the same way —
so a relay session is not reported as "not configured", and the hosted web
build's origin is seeded into the origin list so a browser can attach without
hand-editing the daemon.

### Endpoint override and a TLS front

A server can name the address this app reaches its daemon at — normally an
HTTPS reverse proxy that terminates TLS in front of it — in the MaidCafe tab's
**Endpoint override** section, which also carries copyable Caddy and nginx
recipes. A non-loopback override must be HTTPS, the same rule the endpoint
editor enforces, because the daemon serves plain HTTP and the credential would
otherwise cross the network in the clear. A loopback address is not an override:
that is the tunnel the app builds for itself.

A session with an override dials it directly and never opens a port forward,
which is what lets a build with no SSH at all — a browser, above all — still
reach the daemon's metrics, log stream and config API. Routing falls back to the
automatic resolution (an SSH forward on desktop, the server host in a browser)
when no override is set or the override does not answer.

The connectivity check dials the route a **browser** would take, never this
client's own SSH tunnel: an address that only works because the app is tunneling
to the daemon's loopback says nothing about whether a web client can reach it,
and it reports a throwaway port the user cannot act on. The direct section of
the report therefore shows the server host on the port the daemon reported, and
the sheet says so, so a green result means a browser can attach and a red one
names the port to expose.

Every MaidCafe connection writes what it did — the route it chose, the
endpoint it dialed and a redacted credential (length plus a stable digest, so two
runs can be compared without the secret being written down) — through
`maidCafeLog`. It is on in debug builds and switchable from the connectivity
sheet, because a report that cannot explain a failure needs the console line
that can.

A refused handshake is a policy answer, not a transport failure: the daemon
checks its switch, its platform, the peer address and the credential before it
upgrades the socket, and reports each with its own status, so the app asks it
which one refused instead of sending the user after the port, the credential and
the origin list at once. Only a route that never answered is advised to open a
port — and a direct open on a client that never stored a credential reads the
daemon's own configuration over SSH first, because a detected installation
leaves that field empty by design.

A daemon that enables its terminal must also list its shells: the daemon
rejects a configuration that turns the endpoint on — directly or through the
relay — while `daemon.terminal.shells` is empty, and **a rejected
configuration leaves the running daemon on its previous policy**. So a switch
that reads as on in the file can still be off in the running process, which is
why saving writes a shell list whenever the result would enable either switch.

A cloud-relayed session needs the host to opt in **twice**: the daemon side
serves it only with `daemon.terminal.relay.enabled`, and the cloud refuses the
ticket until its own daemon record has `terminal_relay_enabled`. The editor's
"Serve relayed terminals" switch writes both — the configuration over SSH and
the record through the cloud API — because writing only one of them leaves the
relay refused with a bare `forbidden`. The connectivity check reports either
missing opt-in on the relay route instead of letting the cloud answer that.

## File management without SSH

The file manager and the editor used to be unavailable in a browser because
they spoke SFTP. They now speak `RemoteFileClient`
(`lib/servers/remote_file_system.dart`), which has two implementations:

- `SftpRemoteFileClient` — SFTP, used whenever the server has a live SSH
  client, on any platform.
- `MaidCafeRemoteFileClient` — the MaidCafe daemon's file API over HTTP(S),
  used in a browser (`resolveRemoteFileClient` in
  `remote_file_client_resolver.dart` decides).

A browser therefore browses, reads, edits, uploads and deletes files on any
server that carries a daemon route, confined to the roots the daemon's operator
declared in `daemon.files.roots`. The daemon also decides whether a write needs
root: a root marked `privileged` is written through the operator-installed
`maidkit-priv` helper, so a browser can edit an nginx or Caddy configuration
without the app holding any privilege of its own.

What the daemon's API does not do, and what the app therefore refuses rather
than faking:

| Feature | Why |
| --- | --- |
| Archiving and unarchiving | Needs `zip`/`tar` and a working directory on the host; the daemon serves named operations, not a shell. Reported unavailable instead of silently doing nothing. |
| Move/copy inside a privileged root | Renaming there needs root, and the root helper implements write/mkdir/remove only. The daemon answers `501` and the app reports it. |
| A file larger than the daemon's write cap | The daemon writes whole files, so the client buffers an upload and refuses past the cap. SFTP streams instead. |
| Permission and ownership changes | Not implemented by the daemon; the file manager only performs those over SSH. |

The local pane is hidden in a browser rather than disabled: there is no local
filesystem to browse, and downloads go through the browser's own save flow.

## Containers without SSH

The container list has been daemon-first for a while: `GET /api/v1/containers`
and its `containers` stream, over the session `MaidCafeSessionRegistry` hands
out, with the SSH poller as the fallback. The per-container surfaces now take
the same route:

| Surface | Transport |
| --- | --- |
| List | Daemon `/api/v1/containers` + `containers` stream; SSH poller as fallback |
| Inspect | Daemon `/api/v1/containers/:id/inspect`; SSH `inspect --format '{{json .}}'` as fallback |
| Resources | Daemon `/api/v1/containers/:id/stats`; SSH `stats --no-stream` as fallback |
| Logs | SSH `logs -f` whenever a session exists, otherwise the daemon's captured tail plus the `logs` stream |
| Lifecycle | Daemon `POST /api/v1/containers/:id/:action`; SSH `docker\|podman <verb>` as fallback |
| Update badge | Daemon `/api/v1/updates` (its own cache, no registry traffic) |
| Pull, Update | Daemon `container.pull` / `container.update`, which read the image reference from the container's own configuration |

Reads fall back to SSH because a read is safe to retry — the daemon may simply
not see a container (a user-scoped runtime, or one it has no binary for), and a
daemon older than the detail reads has no such route at all. Actions keep the
opposite rule they already had: a daemon failure surfaces instead of being
replayed over SSH, so nothing is performed twice by two different paths.

The log follow prefers SSH because `logs -f` streams the moment the runtime
writes, where the daemon's deltas arrive on its own capture cadence and only
for the containers it is tailing. A browser, which has no SSH at all, gets the
captured window followed by the `logs` stream.

`pull` and `update` are daemon-only: each one reads the container's own
configuration for the runtime that holds it and the image it was created from,
so a local session has no reference to work with. `update` recreates
compose-managed containers only, and the daemon refuses anything else with the
reason, which the app shows as the error. A container whose own labels do not
record where its project lives is updated in the directory a **compose scan**
assigned to that daemon: the containers tab's scan action takes a starting point
you pick, and every project it assigns then appears as a project in the
container list, with the daemon's directory for it and how many of its
containers are up. That registry is the only source of those rows: the app keeps
no copy of where a project lives, so a project's row cannot disagree with the
daemon about it. A project row updates that whole stack (every service pulled,
its containers recreated), and the header updates every managed stack on the
server one at a time, reporting each stack's own outcome.

An update is a **task** on the daemon rather than a request the app holds open.
A pull takes minutes, and a browser client gives up after ten seconds of
silence — so the app starts the task and follows it instead: the run's output
streams into the shared task terminal with the stage it is on
(`pull`, then `recreate`) and a cancel button, and the bulk dialog shows each
stack's stage as it runs. Because the run belongs to the daemon, hiding the
terminal or leaving the page no longer abandons an update halfway through: the
work continues, and the task can be picked up again from the task terminal's
rail button while it is still running. What remains SSH-only is the
interactive half — exec, attach, and re-creating a container from its inspect
payload — which the app does not offer without a shell.

As with the file API, a browser needs a route it can dial on its own: the
session that carries all of the above cannot open an SSH forward there, so a
server with no endpoint override (normally the HTTPS front described below)
shows the containers tab with the route it is missing instead of a list.

## How the platform split works

Flutter web compiles `dart:io` (its members throw at runtime), so a plain
`import 'dart:io'` is not a build problem — but any `Platform.*`, `File` or
`Socket` call *reached* in a browser is. Two mechanisms keep that from
happening:

1. **Conditional shims** in `lib/platform/` replace the libraries that cannot
   compile or cannot answer truthfully on the web. Each is a conditional export
   (`if (dart.library.js_interop)`) between a native file that re-exports the
   real package and a web file with the same API:

   | Facade | Native | Web |
   | --- | --- | --- |
   | `platform_support.dart` | `Platform.*` / `defaultTargetPlatform` | true values for `isWebPlatform`, `isDesktopPlatform`, `platformPathSeparator`, `operatingSystemName`, `hostName`, `homeDirectory` |
   | `tailscale.dart` | `package:tailscale` | unsupported stubs, `tailscaleRuntimeSupported == false` |
   | `network_ping.dart` | `package:dart_ping` | unsupported stubs |

   The terminal renderer uses the same technique in
   `lib/servers/terminal_renderer_backend.dart`.

2. **`kIsWeb` gates** in the features themselves: startup connection and
   workspace restore, the metrics scheduler, serial ports, vault file handling,
   notifications/FCM, system fonts, biometrics, desktop window code, and the
   local MCP server. The file manager and editor are no longer blanket-gated:
   they choose their transport per server (see the file transport section
   below) and a browser renders the remote pane alone.

Pure replacements were preferred where they exist: `defaultTargetPlatform`
instead of `Platform.isMacOS`, `platformPathSeparator` instead of
`Platform.pathSeparator`. `lib/platform/platform_support.dart` is the only
place that still reads `dart:io` for these values, and it short-circuits before
touching it on the web.

## Persistence

The browser has no filesystem, so there is exactly one database per browser,
stored by drift under the name `maid_kit`; the vault is a single logical entry
and no file operation is ever attempted (`VaultFileStorage` and the vault
providers return the browser vault path, `migrateLegacyVault` is skipped).

drift's web support needs two assets in `web/`, both taken from the drift
release that matches the resolved `drift` version (see `pubspec.lock`):

- `sqlite3.wasm`
- `drift_worker.js`

They must be served with the right content types — in particular
`Content-Type: application/wasm` for `sqlite3.wasm`. Serving the app with
`Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy:
require-corp` additionally unlocks drift's OPFS storage implementations.

### Known limitation: the database does not open on Chromium 150

On Chromium 150 (the build available in this development environment) drift's
web database cannot be opened, in *every* configuration:

- `WasmDatabase.open` → the chosen worker implementation fails with
  `LateInitializationError: Field '' has not been initialized` from inside
  `drift_worker.js`.
- `WasmDatabase.probe(...).open(...)` for each of `inMemory`,
  `sharedIndexedDb` and `unsafeIndexedDb` → the same failure, `inMemory`
  included.
- A hand-rolled setup (`WasmSqlite3.loadFromUrl` + `IndexedDbFileSystem` +
  `registerVirtualFileSystem` + `WasmDatabase(...)`) → `Null check operator used
  on a null value` on the first query, although `sqlite3.wasm` loads
  (`libVersion 3.53.4`) and the IndexedDB file system opens fine through the
  same Dart code.

Every failure is in the wasm↔Dart bridge inside `drift`/`package:sqlite3`, not
in MaidKit: the minimal reproduction is a 40-line entry point. drift 2.35.1 and
sqlite3 3.7.0 with their own release assets behave identically. The application
is not hiding this — the vault gate renders its error state when the first query
fails.

`tool/db_probe.dart` reproduces the diagnosis and prints each step to the
browser console:

```sh
flutter build web --release -t tool/db_probe.dart
# serve build/web (Content-Type: application/wasm for .wasm), then open it
```

Until that is resolved or reproduced as environment-specific, treat browser
persistence as unverified: the build, the boot, the terminal renderer and the
MaidCafe transport are verified, the store behind them is not.

## Verification

```sh
dart format lib test
flutter analyze
flutter test
flutter build web --release
```

The renderer seam can be compiled on its own (a full web build also needs the
rest of the app to stay web-safe):

```sh
flutter build web --release -t tool/web_renderer_probe.dart
```

For a browser smoke test, serve `build/web` with a server that maps `.wasm` to
`application/wasm` and open the page: the app must boot to the vault gate with
no uncaught page errors.
