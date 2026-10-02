// Coverage for the Flutter-rendered (web/Android) context menu path lives in
// context_menu_layout_test.dart, which reproduces the
// "A _RenderGroupIntrinsicWidth was mutated in _RenderLayoutBuilder.performLayout"
// crash and asserts it no longer happens.
import 'context_menu_layout_test.dart' as regression;

void main() => regression.main();
