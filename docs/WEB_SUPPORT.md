# Web support

MaidKit builds for the browser with `flutter build web`. This document records
what runs there, how the native-only code is isolated, what a deployment needs,
and what is still open.

## What runs in a browser

| Area | Browser build |
| --- | --- |
| Terminal rendering | `xterm3` (see `docs/TERMINAL_EMU_ADAPTER.md`) |
| Terminals | MaidCafe daemon terminals over WebSocket — the only transport that needs no raw socket |
| Servers, settings, snippets, GitHub, projects, cloud sync | Local database + HTTP(S) |
| SSH, serial, local shells | Unavailable (no raw sockets) |
| File management, file editor, port forwarding, metrics, containers, systemd, web servers, packages, firewall | Unavailable (SSH/SFTP or local filesystem) |
| Tailscale, network ping | Unavailable (native runtime) |
| Local MCP server, agent processes | Unavailable (no child processes) |
| Desktop window control, system notifications, biometric unlock, system fonts | Unavailable (no plugin) |

Unavailable surfaces are hidden, and the entry points that funnel into them
report why. `server_connection_actions.dart` is the single gate for "this needs
a connection a browser cannot make": `connectForStatistics` and
`openTerminalSession` return early on web with the
`serverTerminalUnavailableInBrowser` message, and the terminal command palette
lists only MaidCafe servers there.

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
   workspace restore, the metrics scheduler, serial ports, the file manager and
   editor, vault file handling, notifications/FCM, system fonts, biometrics,
   desktop window code, and the local MCP server.

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
