# MaidKit architecture

MaidKit is a desktop-first Flutter application for managing SSH servers.

## Stack

- **Flutter + Material 3** for the application UI.
- **Riverpod** and **flutter_hooks** for state, lifecycle-aware UI state, and dependency wiring.
- **auto_route** for declarative, nested navigation. Generated route files live beside their router and must not be edited manually.
- **Drift** for the local SQLite database. The current schema begins with saved server definitions.
- **dartssh2** for SSH client connections and remote command execution.
- **island_ui_foundation** from the Solian Git repository for the desktop window frame and reusable responsive UI utilities.
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

`AppRouter` owns top-level routes. `ServerWorkspacePage` is a nested
`AutoTabsRouter` shell with servers, projects, and settings routes.
`ServersPage` contains the server dashboard and terminal/file-management
workspace as in-page tabs.

When changing routes:

1. Add `@RoutePage()` to the page.
2. Update `lib/routing/app_router.dart`.
3. Run `dart run build_runner build`.
4. Never hand-edit `*.g.dart` or `*.gr.dart` files.

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
