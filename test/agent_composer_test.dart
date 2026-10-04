import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/agent/agent_attachment.dart';
import 'package:maid_kit/agent/agent_composer.dart';
import 'package:maid_kit/agent/agent_reasoning.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  /// Pumps the composer over a harness that owns the attachment list, the way
  /// the chat page does.
  Future<void> pumpComposer(
    WidgetTester tester, {
    required TextEditingController controller,
    List<AgentAttachment> attachments = const [],
    bool working = false,
    bool enabled = true,
    AgentReasoning reasoning = AgentReasoning.modelDefault,
    ValueChanged<AgentReasoning>? onReasoningChanged,
    VoidCallback? onSubmit,
    VoidCallback? onStop,
  }) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: MaterialApp(
          home: _Harness(
            controller: controller,
            attachments: attachments,
            working: working,
            enabled: enabled,
            reasoning: reasoning,
            onReasoningChanged: onReasoningChanged,
            onSubmit: onSubmit,
            onStop: onStop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  IconButton buttonWith(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(
        find
            .ancestor(of: find.byIcon(icon), matching: find.byType(IconButton))
            .first,
      );

  group('send gating', () {
    testWidgets('nothing to send keeps the send button disabled', (
      tester,
    ) async {
      final controller = TextEditingController();
      await pumpComposer(tester, controller: controller);
      expect(buttonWith(tester, Symbols.send).onPressed, isNull);

      controller.text = 'check nginx';
      await tester.pump();
      expect(buttonWith(tester, Symbols.send).onPressed, isNotNull);
    });

    testWidgets('an attachment alone is enough to send', (tester) async {
      final controller = TextEditingController();
      await pumpComposer(
        tester,
        controller: controller,
        attachments: const [AgentAttachment(name: 'app.log', content: 'boom')],
      );
      expect(find.text('app.log'), findsOneWidget);
      expect(buttonWith(tester, Symbols.send).onPressed, isNotNull);
    });

    testWidgets('an attachment that could not be read holds the turn', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'check nginx');
      await pumpComposer(
        tester,
        controller: controller,
        attachments: const [AgentAttachment(name: 'blob.bin', error: 'binary')],
      );
      expect(buttonWith(tester, Symbols.send).onPressed, isNull);
    });

    testWidgets('a pending proposal disables the field and its attach button', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'check nginx');
      await pumpComposer(tester, controller: controller, enabled: false);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(buttonWith(tester, Symbols.attach_file).onPressed, isNull);
    });
  });

  testWidgets('removing a queued attachment clears it from the strip', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pumpComposer(
      tester,
      controller: controller,
      attachments: const [AgentAttachment(name: 'app.log', content: 'boom')],
    );
    expect(find.text('app.log'), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.close));
    await tester.pump();
    expect(find.text('app.log'), findsNothing);
    expect(buttonWith(tester, Symbols.send).onPressed, isNull);
  });

  testWidgets('a pasted block leaves the field and becomes an attachment', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);
    await tester.enterText(find.byType(TextField), 'keep this');
    await tester.pump();

    final block = List.generate(200, (index) => 'log line $index').join('\n');
    expect(block.length, greaterThan(kPasteTextAttachmentChars));
    await tester.enterText(find.byType(TextField), 'keep this\n$block');
    await tester.pump();

    // The message stays as it was written; the block is queued beside it.
    expect(controller.text, 'keep this');
    expect(find.byIcon(Symbols.description), findsOneWidget);
    expect(buttonWith(tester, Symbols.send).onPressed, isNotNull);
  });

  testWidgets('a short paste stays in the field', (tester) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);
    await tester.enterText(find.byType(TextField), 'a short log line');
    await tester.pump();

    expect(controller.text, 'a short log line');
    expect(find.byIcon(Symbols.description), findsNothing);
  });

  testWidgets('Enter sends and Shift+Enter breaks the line', (tester) async {
    var sends = 0;
    final controller = TextEditingController(text: 'check nginx');
    await pumpComposer(tester, controller: controller, onSubmit: () => sends++);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sends, 1);
    expect(controller.text, 'check nginx');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sends, 1);
    expect(controller.text, 'check nginx\n');
  });

  testWidgets('a working turn queues instead of sending, and offers stop', (
    tester,
  ) async {
    var submits = 0;
    var stops = 0;
    final controller = TextEditingController(text: 'and then restart it');
    await pumpComposer(
      tester,
      controller: controller,
      working: true,
      onSubmit: () => submits++,
      onStop: () => stops++,
    );

    expect(find.byIcon(Symbols.schedule), findsOneWidget);
    expect(find.byIcon(Symbols.stop), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.schedule));
    await tester.pump();
    expect(submits, 1);

    await tester.tap(find.byIcon(Symbols.stop));
    await tester.pump();
    expect(stops, 1);
  });

  testWidgets('a sent turn names the files it carried', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentAttachmentChips(
            attachments: [
              AgentAttachment(name: 'app.log', content: 'boom'),
              AgentAttachment(
                name: 'shot.png',
                content: 'data:image/png;base64,cG5n',
                isImage: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('app.log'), findsOneWidget);
    expect(find.text('shot.png'), findsOneWidget);
    expect(find.byIcon(Symbols.description), findsOneWidget);
    expect(find.byIcon(Symbols.image), findsOneWidget);
  });

  group('reasoning pill', () {
    /// The fill of a level's chip: the lit one wears the accent's tint, the
    /// rest stay transparent.
    Color chipColor(WidgetTester tester, String label) =>
        ((tester
                    .widget<AnimatedContainer>(
                      find
                          .ancestor(
                            of: find.text(label),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color)!;

    testWidgets('the untouched pill lights no level', (tester) async {
      await pumpComposer(tester, controller: TextEditingController());
      for (final level in [
        AgentReasoning.low,
        AgentReasoning.medium,
        AgentReasoning.high,
      ]) {
        expect(chipColor(tester, level.labelKey.tr()), Colors.transparent);
      }
    });

    testWidgets('choosing a level lights it and reports the choice', (
      tester,
    ) async {
      final chosen = <AgentReasoning>[];
      await pumpComposer(
        tester,
        controller: TextEditingController(),
        onReasoningChanged: chosen.add,
      );
      final scheme = Theme.of(
        tester.element(find.byType(AgentComposer)),
      ).colorScheme;

      await tester.tap(find.text('agentReasoningHigh'.tr()));
      await tester.pumpAndSettle();

      expect(chosen, [AgentReasoning.high]);
      expect(
        chipColor(tester, 'agentReasoningHigh'.tr()),
        scheme.primaryContainer,
      );
      expect(chipColor(tester, 'agentReasoningLow'.tr()), Colors.transparent);
    });

    testWidgets('tapping the lit level returns to the model default', (
      tester,
    ) async {
      final chosen = <AgentReasoning>[];
      await pumpComposer(
        tester,
        controller: TextEditingController(),
        reasoning: AgentReasoning.high,
        onReasoningChanged: chosen.add,
      );

      await tester.tap(find.text('agentReasoningHigh'.tr()));
      await tester.pumpAndSettle();

      expect(chosen, [AgentReasoning.modelDefault]);
      expect(chipColor(tester, 'agentReasoningHigh'.tr()), Colors.transparent);
    });
  });
}

/// The chat page in miniature: it owns the attachment list, so a removal or a
/// pasted block is a real state change rather than a callback into nothing.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.controller,
    required this.attachments,
    required this.working,
    required this.enabled,
    required this.reasoning,
    this.onReasoningChanged,
    this.onSubmit,
    this.onStop,
  });

  final TextEditingController controller;
  final List<AgentAttachment> attachments;
  final bool working;
  final bool enabled;
  final AgentReasoning reasoning;
  final ValueChanged<AgentReasoning>? onReasoningChanged;
  final VoidCallback? onSubmit;
  final VoidCallback? onStop;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final List<AgentAttachment> _attachments = [...widget.attachments];
  late AgentReasoning _reasoning = widget.reasoning;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AgentComposer(
      controller: widget.controller,
      focusNode: _focusNode,
      attachments: _attachments,
      working: widget.working,
      enabled: widget.enabled,
      reasoning: _reasoning,
      onReasoningChanged: (reasoning) {
        setState(() => _reasoning = reasoning);
        widget.onReasoningChanged?.call(reasoning);
      },
      onAttach: () {},
      onAttachText: (text) => setState(
        () => _attachments.add(
          AgentAttachment.text(text, name: 'agentPastedText'.tr()),
        ),
      ),
      onEditAttachment: (_) {},
      onRemoveAttachment: (index) =>
          setState(() => _attachments.removeAt(index)),
      onSubmit: widget.onSubmit ?? () {},
      onStop: widget.onStop ?? () {},
    ),
  );
}
