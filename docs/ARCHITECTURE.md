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
  `maidcafe_terminal_connection_manager.dart`). This is the only route that
  works in a browser build, and on a native build it is a fallback rather than
  the default: for a server that can also do SSH, a connected SSH session owns
  statistics, activity, container and management actions, while the daemon
  answers only until a session is live (and the statistics poll stands aside
  while one is). `lib/servers/session_lookup.dart` holds that rule —
  `sshPreferredOverDaemon` reads the session feed, whose
  `SessionTransport` tag is what keeps a daemon terminal from passing for an SSH
  session. Features SSH has no implementation for keep the daemon outright: the
  daemon console, container update checks, the compose stack registry,
  watched-process history, and the daemon's health score.
- **Server rows are independent of transports.** `connectionType` names what the
  row *is* — `ssh`, `serial`, or `maidcafe` — and a daemon route can sit on any
  of them as a second way in. Only a row typed `maidcafe` is daemon-only; a row
  typed `ssh` always keeps its SSH route, and the daemon is what covers it when
  no session is up.
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

`AppRouter` owns a single route: `ServerWorkspacePage`, the pane-tab workspace
(`SessionsWorkspace` in `servers/tabs_screen.dart`). There is no tab router
and no navigation rail — every destination is a `SessionTab` in the pane tab
strip (`servers/terminal_tabs_provider.dart`): the servers dashboard, terminals, file
management, file editors, agent chats, assets, deployment projects, the MaidCafe
cloud console and settings.

A tab that can open a detail page (dashboard, server detail, assets, projects,
MaidCafe cloud, settings) wraps its content in a `TabNavigator`
(`shared/presentation/tab_navigator.dart`). Push details with
`TabNavigator.of(context).push(SomeDetailPage(...))` so the page lands inside the
tab that opened it and survives switching tabs and panes; pop them with
`TabNavigator.of(context).pop()`. `context.router` is only the root navigator and
must not be used for detail pages.

The workspace has one tab bar, not one per pane. It lists every tab in the
session left to right in pane order, so a split reads as one set of documents
with several viewports rather than as several independent windows. On desktop
that bar *is* the window title bar: the window is borderless, the bar occupies
the native title bar row (`kMaidKitTitleBarHeight`, 40 pt), and there is no
second bar above it. The bar reserves the macOS traffic-light inset on its
leading edge, moves the window when dragged from empty bar space, and draws the
minimize/maximize/close buttons itself where the OS does not (Windows, Linux).
`MainFlutterWindow.swift` re-centers the macOS traffic lights on the bar
whenever the Dart side reports a new effective height, so they stay aligned
across UI-scale changes. While no bar exists — the locked vault, a workspace
with no panes — `MaidKitWindowScaffold` draws a standalone `MaidKitTitleBar`
instead, so the window is never draggable-less. On a window narrower than 768
logical pixels only the selected tab draws its title, and that title expands
out of its icon and collapses back instead of snapping the bar's layout, so
background tabs stay icon-sized.

Panes below the bar are separate cards on the workspace paper: they are
separated by a gutter, with no rule drawn between them, and the gutter is the
drag band that resizes the split. Each pane ends in its own band — the
terminal status bar (`AnimatedTerminalStatusBar`) when that pane shows a
terminal, nothing otherwise — so a split reads out every terminal it shows, not
just the focused one. A split's focused pane carries a close control in its
corner, since panes no longer have strips to put one in.

A pane shows exactly one tab's content. A tab that needs several viewports is a
group: splitting mounts a second session of the same target in the new pane,
both sessions share one bar entry, and that entry prints the number of panes it
occupies. Terminals and agent chats each own one live renderer, so splitting
them leaves the new pane empty for a fresh session instead of duplicating them;
destinations with a fixed tab id behave the same way. The bar orders entries by
their panes' position in the layout, which is why the layout tree — not the tab
list — decides what the row reads like.

The window shell
(`shared/presentation/maidkit_window_scaffold.dart`) owns the app-level
shortcuts — Shift+Tab opens the session-actions palette and Cmd/Ctrl+W closes
the focused tab — because focus may sit outside the workspace when they are
pressed. Closing routes through `TerminalTabsNotifier.close`, which asks first
when the tab is still working: a terminal running a task, an agent chat still
replying, or a dirty file editor.

When changing pages:

1. Add the destination or detail widget; only `ServerWorkspacePage` is a
   `@RoutePage()`.
2. Add a `SessionTab` subclass plus an `open*` method on `TerminalTabsNotifier`
   for a new destination, and render it in `_SessionTabBody`.
3. Run `dart run build_runner build` if routes changed.
4. Never hand-edit `*.g.dart` or `*.gr.dart` files.

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
  themselves with a deeper surface tone, not borders or shadows. The bar is
  `surfaceContainerLow`; its selected entry paints `surface`. Panes are
  `MaidKitPanel` cards: the focused pane is `surfaceContainerHigh` and an
  unfocused one is `surfaceContainer`, so a split reads as one live card among
  quieter neighbours without a rule between them.
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
