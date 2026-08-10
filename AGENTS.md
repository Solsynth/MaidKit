# MaidKit contributor guidance

Read `docs/ARCHITECTURE.md` before making structural changes.

## Tech stack rules

- Use Material 3 (`ThemeData.useMaterial3`) for standard controls and theming.
- Use `hooks_riverpod` for state management. Prefer `ConsumerWidget` for read-only reactive views and `HookConsumerWidget` only when hooks are needed.
- Keep feature code directly under `lib/<feature>/`; do not introduce deep `presentation`, `domain`, or `data` folders by default.
- Use `auto_route` for navigation. Add route annotations/configuration and regenerate code with `dart run build_runner build`; never edit generated `*.g.dart` or `*.gr.dart` files.
- Store persistent data in Drift and place app-wide schema changes in `lib/data/local/app_database.dart`.
- Use `dartssh2` for SSH behavior. Do not put credentials or private keys in Drift; introduce a secure credential store when authentication is implemented.

## Window and layout rules

- Keep the app wrapped in `MaidKitWindowScaffold`, which uses Island's `DesktopWindowFrame` for desktop-native chrome.
- Preserve desktop window initialization in `main.dart` when changing startup code.
- The main workspace uses the Island-inspired `AutoTabsRouter` shell: `NavigationRail` on wide layouts and Material `NavigationBar` on narrow layouts.
- Put tab content in its own route page. Do not replace nested tab routing with local selected-index state.
- Reference `../SolarNetwork/Island/lib/misc/tabs_screen.dart` and `../SolarNetwork/Island/lib/shared/widgets/app_scaffold.dart` when extending navigation or window behavior.

## UI guidelines

- Make the interface quiet, functional, and desktop-oriented. Prefer standard Material 3 components and the Island foundation helpers over custom chrome.
- Use calm theme colors already defined in `app.dart`; do not introduce gradients, glows, glass effects, decorative hero sections, or fake dashboards.
- Avoid oversized rounded corners, pill-heavy navigation, large shadows, and unnecessary cards.
- Keep spacing on a simple 4/8/12/16/24/32 scale. Use borders and contrast for hierarchy rather than effects.
- Do not add a page-level app bar to the tab workspace unless there is a clear product requirement. The window title bar and tab navigation provide the surrounding chrome.
- Keep responsive behavior intentional: rail for widths above 768 logical pixels; bottom navigation below that breakpoint.

## Checks

Run formatting, code generation when annotations or Drift schema change, then `flutter analyze` and `flutter test`.
