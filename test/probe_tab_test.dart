import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:maid_kit/shared/presentation/icon_label_tab.dart';
import 'package:maid_kit/theme.dart';

void main() {
  testWidgets('probe tab label rendering', (tester) async {
    await EasyLocalization.ensureInitialized();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: MaterialApp(
          theme: createMaidKitTheme(Brightness.light),
          locale: const Locale('en', 'US'),
          home: Scaffold(
            body: DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      IconLabelTab(
                        icon: const Icon(Icons.dns, size: 18),
                        label: 'assetsConnections'.tr(),
                      ),
                      IconLabelTab(
                        icon: const Icon(Icons.rocket_launch, size: 18),
                        label: 'tabGithub'.tr(),
                      ),
                      IconLabelTab(
                        icon: const Icon(Icons.key, size: 18),
                        label: 'assetsCredentialsTitle'.tr(),
                      ),
                      IconLabelTab(
                        icon: const Icon(Icons.code, size: 18),
                        label: 'tabSnippets'.tr(),
                      ),
                    ],
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final texts = find.byType(Text).evaluate().toList();
    for (final element in texts) {
      final widget = element.widget as Text;
      final box = element.renderObject as RenderBox?;
      debugPrint(
        'PROBE data="${widget.data}" style=${widget.style?.fontSize} '
        'size=${box?.size}',
      );
    }
  });
}
