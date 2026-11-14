# MaidKit architecture

MaidKit is a desktop-first Flutter application for managing SSH servers.

## Stack

- **Flutter + Material 3** for the application UI.
- **Riverpod** and **flutter_hooks** for state, lifecycle-aware UI state, and dependency wiring.
- **auto_route** for declarative, nested navigation. Generated route files live beside their router and must not be edited manually.
- **Drift** for the local SQLite database. The current schema begins with saved server definitions.
- **dartssh2** for SSH client connections and remote command execution.
- **MaidCafe daemon over HTTP/SSE/WebSocket** for the optional daemon layer:
  host statistics, activity history, and terminals reach a daemon without an SSH
  session (`lib/servers/maidcafe_stats.dart`, `maidcafe_stream.dart`,
  `maidcafe_terminal_connection_manager.dart`). It is the only route that
  works in a browser build, and it leads on a native build too: the daemon owns
  statistics, activity, the process and runtime tables, database metrics,
  systemd, packages, firewall, the container and image lists, the
  per-container reads and every action it implements, because each of those
  costs the host one HTTP request instead of an exec over its session. SSH is
  the fallback — it answers a route with no daemon (no stored endpoint, nothing
  to forward through) and a daemon older than the endpoint a surface asks for,
  never as the first choice beside a daemon that answers. `logs -f` is the one
  deliberate exception: it streams the moment the runtime writes, where the
  daemon's deltas arrive on its collection cadence. A browser gets the daemon's
  captured window followed by its `logs` stream.
  `lib/servers/session_lookup.dart` holds the helpers that answer for that
  policy: `isLiveSshSession` reads the feed's `SessionTransport` tag so a daemon
  terminal never passes for an SSH session, and `sshFallbackAvailable` says
  whether a row has an SSH route a failed daemon read can fall back to at all.
  Features only the daemon implements — the daemon console, container update
  checks, the compose stack registry, watched-process history, the file API and
  the daemon's health score — never look for an SSH form.
- **Host metrics have one app-wide switch.** `serverMetricsEnabledProvider`
  (`lib/servers/server_providers.dart`, persisted by
  `MetricsRefreshPreferences`) turns collection off for every server at once.
  Off means no scheduler serves a host, `SshConnectionManager` skips its metric
  and system-information commands and refuses the Activity tab's probe, and
  every surface shows a "metrics are turned off" placeholder instead of a
  reading — connections, terminals and process listings keep working.
- **Server rows are independent of transports.** `connectionType` names what the
  row *is* — `ssh`, `serial`, or `maidcafe` — and a daemon route can sit on any
  of them as a second way in. Only a row typed `maidcafe` is daemon-only; a row
  typed `ssh` always keeps its SSH route, which is what covers a surface the
  daemon does not implement, an older daemon, or a daemon with no route at all.
- **island_ui_foundation** from the Solian Git repository for reusable responsive UI utilities and sheets. Its `DesktopWindowFrame` is not used: `shared/presentation/window_chrome.dart` owns the window chrome.
- **window_manager** for native desktop window setup, with **screen_retriever** for the display layout saved window bounds are restored against.

## Source layout

Features are flat and live directly under `lib/<feature>/`. Avoid `data`, `domain`, `presentation`, or similar subfolders unless a feature grows enough to make one necessary.

```
lib/
  app.dart                         # MaterialApp.router and theme
  main.dart                        # Bootstrap and desktop window setup
  data/local/                      # App-wide Drift database
  routing/                         # auto_route configuration and generated routes
  servers/                         # Server feature pages, providers, repository
  shared/presentation/             # App-wide reusable UI shell
```

## Navigation

`AppRouter` owns a single route: `ServerWorkspacePage`, the tab workspace
(`SessionsWorkspace` in `servers/tabs_screen.dart`). There is no tab router
and no navigation rail — every destination is content inside a tab, mounted
from `servers/terminal_tabs_provider.dart`: the servers dashboard, terminals,
file management, file editors, agent chats, assets, deployment projects, the
MaidCafe cloud console and settings.

A tab that can open a detail page (dashboard, server detail, assets, projects,
MaidCafe cloud, settings) wraps its content in a `TabNavigator`
(`shared/presentation/tab_navigator.dart`). Push details with
`TabNavigator.of(context).push(SomeDetailPage(...))` so the page lands inside the
tab that opened it and survives switching tabs and panes; pop them with
`TabNavigator.of(context).pop()`. `context.router` is only the root navigator and
must not be used for detail pages.

The workspace has one tab bar, not one per pane. A tab is a document that
owns its panes: `WorkspaceTab` carries a `SessionLayout` tree, the panes it
mounts (`TabPane`), and which pane has focus. Splitting adds a pane to the
current tab rather than a second tab, so a split terminal keeps its one bar
entry with a pane count and remembers its own divider ratio while other tabs
open single-pane. The bar lists tabs left to right, so the workspace reads as
one set of documents with several viewports rather than as several independent
windows. On desktop that bar *is* the window title bar: the window is
borderless, the bar occupies the native title bar row
(`kMaidKitTitleBarHeight`, 40 pt), and there is no second bar above it. The bar
reserves the macOS traffic-light inset on its leading edge, moves the window
when dragged from empty bar space, and draws the minimize/maximize/close
buttons itself where the OS does not (Windows, Linux). `MainFlutterWindow.swift`
re-centers the macOS traffic lights on the bar whenever the Dart side reports a
new effective height, so they stay aligned across UI-scale changes. While no
bar exists — the locked vault, an empty workspace — `MaidKitWindowScaffold`
draws a standalone `MaidKitTitleBar` instead, so the window is never
draggable-less. On a window narrower than 768 logical pixels only the selected
tab draws its title, and that title expands out of its icon and collapses back
instead of snapping the bar's layout, so background tabs stay icon-sized.

Panes below the bar are separate cards on the workspace paper: they are
separated by a gutter, with no rule drawn between them, and the gutter is the
drag band that resizes the split. Each pane ends in its own band — the terminal
band (`AnimatedTerminalStatusBar`) when that pane shows a terminal, nothing
otherwise — so a split reads out every terminal it shows, not just the focused
one. The band is one row deep, and which row depends on the input device. On a
pointer platform it is the readings: transport, connection state, ping and the
host's label as pills on the pane's sheet, with no rule above the band and no
rules between readings, so it groups itself by tone and spacing. On a touch
platform it is the key deck (`servers/terminal_key_bar.dart`): a soft keyboard
has no Esc, Tab, arrows or Ctrl, so those keys sit on the caps directly above
the IME. Mono keycaps at `MaidKitRadius.chip` read as hardware, the leading
`ctrl` key arms and swaps the run from navigation keys to control chords
instead of adding a second row, arrows repeat while held, and the trailing key
raises or puts away the IME. A key never takes focus, so a chord leaves the
keyboard up and the cursor where it was.

A split's panes carry a short drag handle at the top centre of their sheet:
dragging it onto a sibling swaps the two viewports' slots (`swapPaneSlots`),
keeping each pane's id, content and state, so moving a terminal rearranges the
split instead of reopening its shell. Closing one pane of a split is a
command-palette action (`sessionsClosePane`), next to closing the tab the pane
belongs to. The focused pane also carries a single accent hairline, and idle
panes are dimmed by a paint-time brightness filter instead of a colour wash, so
exactly one viewport reads as live while an idle pane keeps every pointer
event, scroll and Material ink it had.

A pane shows exactly one content instance. Every tab stays mounted, with only
the selected one visible, so switching tabs keeps a terminal's scrollback, an
editor's scroll position and a file browser's listing.

A split always yields an empty pane: nothing is cloned, because a terminal and
an agent chat own one live renderer and a second view of a page is the user's
decision rather than a side effect of splitting. That pane shows
`PaneLauncher` (`servers/pane_launcher.dart`) — the session-actions command
palette inline, searchable, over everything a pane can mount: a terminal on any
host, the file manager, a server detail page, each assets page, projects, an
agent chat, the cloud console, settings and the dashboard. Every
`TerminalTabsNotifier.open*` takes an optional `paneId`, so a pick mounts into
that pane when one is named (with an id of its own, since one id is one view)
and opens a workspace tab otherwise; the same launcher serves the no-tabs
workspace.

The home dashboard (`canSplitTab`) never splits: it is the workspace's floor
and fills the pane area it occupies. It is also the only tab that cannot be
closed; a dashboard mounted in a split pane closes with its pane.

The window shell
(`shared/presentation/maidkit_window_scaffold.dart`) owns the app-level
shortcuts — Shift+Tab opens the session-actions palette, Cmd/Ctrl+T opens an
empty workspace tab and Cmd/Ctrl+W closes the pane the workspace is showing —
because focus may sit outside the workspace when they are pressed. The new tab
is one empty pane, the same launcher a split leaves behind, so it starts from a
choice instead of a copy of the current tab. A split loses only its focused
pane; the tab's last pane *is* the tab, so the same chord closes the whole tab
there. The close routes through `TerminalTabsNotifier.closePaneInTab`, which
asks first when the pane's content is still working: a terminal running a task,
an agent chat still replying, or a dirty file editor.

Ctrl+Tab walks the workspace's tabs (Shift+Ctrl+Tab walks back) and
Cmd/Ctrl+1…9 jumps to the tab at that position; both are answered by the
terminal's key hook as well, because a focused terminal would otherwise
encode or swallow them. The cycle wraps at the ends, while a position past the
last tab selects nothing.

The saved workspace (`servers/workspace_snapshot.dart`, version 2) stores one
layout and one pane map per tab. Version 1 saves — a single workspace layout
with tab lists frozen inside each pane — are converted on load, one tab per
pane tab, so an older session still reopens.

## tmux-backed terminals

A terminal can be a tmux *client* instead of a shell, so its process tree
outlives the transport: closing the tab detaches, the session keeps running,
and any later open — over SSH or over a MaidCafe daemon, relayed or direct —
reattaches by name.

The layer has three parts. `servers/tmux_control_client.dart` speaks tmux's
control-mode protocol (`tmux -CC`): it strips the DCS framing, parses the
`%`-prefixed notifications, correlates `%begin`/`%end` blocks with the commands
that asked for them, and turns keystrokes into `send-keys -H` hex chunks. It
runs on an allocated pty because `-CC` refuses to start without a tty, which is
why the SSH path opens a shell channel (`SshConnectionManager.openTmuxControl`)
and the daemon path runs `tmux -CC` inside the PTY it already allocates.
`servers/tmux_terminal.dart` owns `TmuxTabBinding`: one binding per session,
the adapter for every mirrored pane, and the tmux commands behind splitting,
resizing, closing a pane and detaching. `servers/tmux_layout.dart` maps a tmux
layout onto the workspace's binary `SessionLayout` tree, folding an n-ary
container into nested splits.

Both layout serializations are parsed, because tmux picks between them by
version rather than by request: format 2 (`{"V":2,"L":…}`) appears only after
the client sets `refresh-client -f new-layouts`, and a tmux that predates that
flag — Ubuntu and Debian still ship 3.3a — answers `%error` and keeps emitting
format 1 (`5525,80x24,0,0{…}`, a checksum followed by nested cells). The flag
is requested but never required, and a host that refuses it mirrors its panes
instead of showing an empty tab.

tmux is the authority. Splitting, dragging a gutter and closing a pane all
become tmux commands whose `%layout-change` reply is what re-tiles the screen,
so the tab's layout is a projection of the session's own tree and a refused
gesture snaps back instead of drifting. `TerminalTabsNotifier.openTmux` mounts
one workspace tab per session, `applyTmuxLayout` applies a projected tree, and
`closeTmuxTab` drops a tab whose session ended. `tmuxEnabledProvider` is the
app-wide switch; `detachOnCloseProvider` chooses between detaching and killing
when a tab closes, and the workspace snapshot records a terminal's session name
so a restored workspace reattaches to it.

Every mirrored pane is a real shell, so it gets the same `sudo` autofill a
plain SSH terminal has: the binding carries the connection's password
(`openTmux(autoFillSecret: …)`, sourced from the same credential and Settings
switch as the plain path), each pane's `TerminalSessionBinding` owns its own
`SudoPromptAutofill`, and a bare Enter at a genuine prompt is replaced with it.
The secret is per pane because the prompt appears in one pane, never in all of
them. A daemon tmux session offers none: the daemon runs its shell as its own
account, which the stored SSH credential need not belong to.

A tmux tab restores by *reattaching*, never by replaying a saved layout. The
session, its windows and its processes live on the host, so there is nothing to
rebuild: `new-session -A -s <name>` reconnects to the session that is still
running, and `initialize` then pulls its layout and seeds each pane's
scrollback from tmux's own history. `detachOnClose` is what keeps that true
across a close: the default detaches, so the session outlives the tab and the
next open reattaches it.

One attach per session, by two rules:

* The snapshot names the session on *every* pane of a tmux tab, because each
  pane is a real terminal. `resolveWorkspaceSnapshot` claims each
  `(server, session)` once per tab and defers a single
  `PendingTerminalRestore`; the other panes stay empty for the session's own
  layout to fill in. A second attach would take the reservation over from the
  first and leave the tab with two clients on one session.
* When a caller reserved a pane (`openTmux(paneId: …)`), the tab owning that
  pane *becomes* the tmux tab rather than a second tab opening beside it. That
  is how a restored split tab keeps the file manager or editor it had next to
  the terminal, with the session's panes mounting where they were.

Attaching pulls the layout instead of waiting for it. tmux only emits
`%layout-change` from events — a split, a resize, a closed pane — so a session
nobody is typing into reports nothing after the handshake, and a tab that
waited for the event would stay the empty placeholder it opened as. So
`TmuxTabBinding.initialize` asks for `#{window_layout}` with one
`display-message`, projects it, and then follows events normally. The answer is
in whichever format that tmux reports — v2 JSON where the flag was honoured,
format 1 where it was not — and both parse. `openTmux` rolls the tab back if
that handshake throws, so a failed attach never leaves an empty pane behind.

Which transport carries the client follows the server's own connection type,
not whether it has a daemon endpoint: an SSH server opens tmux over SSH, and a
stored loopback endpoint is dialed only when the caller actually chose the
daemon (`shouldOpenTmuxViaDaemon`). Reaching for the endpoint instead would aim
at the port only a native client's own SSH forward serves, and the socket is
refused. The SSH path also connects the server first, because tmux rides that
session and an unconnected server would otherwise lose tmux silently.

When changing pages:

1. Add the destination or detail widget; only `ServerWorkspacePage` is a
   `@RoutePage()`.
2. Add a `SessionTab` subclass plus an `open*` method on `TerminalTabsNotifier`
   for a new destination, accept its `paneId` (see `_insertTab`), render it in
   `_SessionTabBody`, list it in `PaneLauncher`, and give it a snapshot kind in
   `servers/workspace_snapshot.dart`.
3. Run `dart run build_runner build` if routes changed.
4. Never hand-edit `*.g.dart` or `*.gr.dart` files.

## Long-running tasks

`shared/presentation/task_progress.dart` owns every task the user starts and
waits on: `TaskProgressNotifier` queues one `AppTaskRequest` at a time, samples
speed, throttles progress to 250 ms, and hands each action a `TaskControl` for
pause/cancel and a report callback. `TaskProgressBar` in the window shell
renders the queue over the app, and tapping it opens the full list, so a
background transfer is visible and cancellable from any tab.

A feature submits work rather than building its own queue: the file transfer
path in `servers/file_management_tab.dart` is one `AppTaskRequest` per copy,
and the tab tracks the returned ids only to mark itself busy and to cancel its
work when the tab closes. Throwing `TaskSkipped` settles a task quietly (no
success callback); throwing `TaskCancelled` — normally from
`TaskControl.throwIfCancelled` — settles it as cancelled.

A queued task cannot hold the queue hostage. `TaskControl.cancelled` completes
the moment the user cancels, and `_execute` settles the task on it instead of
waiting for the action to unwind — an action parked on I/O that never returns
would otherwise occupy the single slot for the rest of the session, leaving
every later transfer stuck at "queued".

Remote reads are bounded by `servers/remote_transfer.dart`. SFTP requests carry
no timeout of their own, so `pumpRemoteFile` races each read against
`transferStallTimeout` and against `TaskControl.cancelled`, and calls the
caller's `abandon` callback when either wins. Closing the transport is the only
thing that completes a pending request, so a transfer whose peer went silent
fails with `RemoteTransferStalled` and a cancelled one aborts immediately; the
file manager then drops its cached transport so the next transfer opens a fresh
one. `abandon` is never called for a read that finished normally.

## Theming

`lib/theme.dart` is the single source of design decisions, ported from Island's
`lib/core/theme.dart`. Feature widgets must depend on it rather than inventing
local colour schemes or chrome.

- **Tokens.** `MaidKitSpace` (spacing), `MaidKitRadius` (corner radii) and
  `MaidKitInsets` (reusable insets) are the scales. If a value is not on a
  scale it is a one-off, not a system decision — prefer the nearest token.
- **Surfaces.** `createMaidKitTheme` rebuilds only the *neutral ramp* from the
  seed (`_seedPaper`), keeping accent roles as `ColorScheme.fromSeed` produced
  them. Neutrals are tinted toward the seed's own hue, so a teal seed reads as
  cool paper and a clay seed as warm paper.
- **Tone over outlines.** Cards, sections and the workspace tab bar separate
  themselves with a deeper surface tone, not borders or shadows. One paper
  runs through the app: `scaffoldBackgroundColor`/`canvasColor` are
  `surfaceContainerLow`, the same tone as the tab bar, so the locked vault, the
  window frame and every top-level page share it. The bar's selected entry
  paints `surface`. Panes are `MaidKitPanel` cards that step off the paper by
  exactly one tone: the focused pane is `surfaceContainerLow` and an unfocused
  one sits back down on the paper, `surfaceContainerLowest`, so a split shows
  one live card and the gutter alone divides them. An unfocused pane keeps a
  neutral hairline (`outlineVariant` at 60%) — the one outline in the system,
  and it exists because a pane body may paint no surface of its own: the file
  manager's pane is transparent, so without the edge an idle pane would be the
  paper exactly, with nothing to read as a pane. Never flatten the two tones
  into one role; that collapse is what removes the only other cue. A panel
  republishes its own tone as the theme paper
  for everything inside it, so a tab body that paints a surface — a page
  scaffold, a pushed detail page, a file editor — fills the card instead of
  cutting a paper-coloured hole in it, and cards inside step one tone further
  off whichever sheet holds them (`surfaceContainer` live,
  `surfaceContainerLow` idle).
- **Inputs are tonal first.** A soft fill (`surfaceContainerHigh` at 70%)
  defines a field; only focus and error draw an edge.
- **Placeholders.** Every empty or failed surface renders through
  `MaidKitEmptyState` (`lib/shared/presentation/empty_state.dart`). One shape
  everywhere: `compact: true` inside panels, sheets and overlays, and
  `iconColor` when the placeholder is an error.

`material_ui` and Flutter's own Material library expose separate `Theme`
inherited widgets, so the window chrome — which reads the Flutter SDK theme —
would otherwise fall back to Flutter defaults. `maidkit_window_scaffold.dart`
therefore copies the app's colour scheme into a `flutter.ThemeData` (rather
than regenerating one from the seed) so both libraries agree on the paper ramp.

## Persistence

`AppDatabase` in `lib/data/local/app_database.dart` is the single Drift database. Keep database tables and migrations there. Feature repositories should expose feature-focused queries, while Riverpod providers construct repositories and expose UI-friendly streams or async values.

## Validation

Run these before handing off changes:

```sh
dart format lib test
dart run build_runner build
flutter analyze
flutter test
```
