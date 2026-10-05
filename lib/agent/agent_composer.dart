import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_attachment.dart';
import 'agent_reasoning.dart';

/// The message composer: the prompt field, the attachments queued over it, and
/// the one control that sends them.
///
/// The shape follows Persynth's insight composer: attachments queue as a strip
/// above the field, the field carries no surface of its own — the chat docks it
/// on the bar that closes the pane, so the two read as one — and the send
/// control is the single filled button: disabled until there is something to
/// send, and held back while an attachment could not be read.
///
/// A block pasted into the field at least [kPasteTextAttachmentChars] long
/// leaves the field and becomes a text attachment, so a pasted log stays
/// editable and out of the sentence it was pasted into.
class AgentComposer extends StatefulWidget {
  const AgentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.attachments,
    required this.working,
    required this.enabled,
    required this.onAttach,
    required this.onAttachText,
    required this.onEditAttachment,
    required this.onRemoveAttachment,
    required this.onSubmit,
    required this.onStop,
    required this.reasoning,
    required this.onReasoningChanged,
    this.status,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The attachments queued for the next turn, in the order they will ride it.
  final List<AgentAttachment> attachments;

  /// Whether a turn is in flight: the send control queues instead of sending,
  /// and the stop control appears beside it.
  final bool working;

  /// False while a pending proposal owns the turn: nothing can be sent, and
  /// nothing can be attached to a message that cannot leave.
  final bool enabled;

  /// Opens the file picker; what comes back is queued by the owner.
  final VoidCallback onAttach;

  /// Queues a block of pasted text as a text attachment.
  final ValueChanged<String> onAttachText;

  /// Opens one queued text attachment for editing.
  final ValueChanged<int> onEditAttachment;

  /// Drops one queued attachment.
  final ValueChanged<int> onRemoveAttachment;

  final VoidCallback onSubmit;
  final VoidCallback onStop;

  /// How much the model should think before answering. It is a standing
  /// choice, sent with the next turn, not a property of the message being
  /// written.
  final AgentReasoning reasoning;

  final ValueChanged<AgentReasoning> onReasoningChanged;

  /// The chat's own read-out for the footer strip, beside the reasoning pill:
  /// what the next request costs, in the meter Persynth's composer carries.
  /// Null when there is nothing to report yet.
  final Widget? status;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  /// The field's text as it was before the last change, so a paste can be told
  /// from typing. [_restoringInput] swallows the change made while a pasted
  /// block is taken back out of the field.
  String _lastInput = '';
  bool _restoringInput = false;

  @override
  void initState() {
    super.initState();
    _lastInput = widget.controller.text;
    widget.focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    widget.focusNode.onKeyEvent = null;
    super.dispose();
  }

  /// Enter sends, Shift+Enter breaks the line. The field is multiline, so the
  /// key has to be claimed here rather than left to the field's own handling.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertNewLine();
    } else {
      widget.onSubmit();
    }
    return KeyEventResult.handled;
  }

  void _insertNewLine() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  void _handleChanged(String value) {
    final previous = _lastInput;
    _lastInput = value;
    if (_restoringInput) {
      _restoringInput = false;
      return;
    }
    final inserted = _insertedBlock(previous, value);
    if (inserted == null || inserted.text.length < kPasteTextAttachmentChars) {
      return;
    }
    _restoringInput = true;
    widget.controller.value = TextEditingValue(
      text: previous,
      selection: TextSelection.collapsed(offset: inserted.start),
    );
    _lastInput = previous;
    widget.onAttachText(inserted.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.attachments.isNotEmpty) ...[
            SizedBox(
              height: _AgentAttachmentTile.size,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: widget.attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final attachment = widget.attachments[index];
                  return _AgentAttachmentTile(
                    attachment: attachment,
                    onEdit: attachment.isImage
                        ? null
                        : () => widget.onEditAttachment(index),
                    onPreview: attachment.isImage
                        ? () => _previewAttachment(context, attachment)
                        : null,
                    onRemove: () => widget.onRemoveAttachment(index),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'agentAttachFiles'.tr(),
                onPressed: widget.enabled ? widget.onAttach : null,
                icon: const Icon(Symbols.attach_file),
              ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.multiline,
                  maxLines: 5,
                  minLines: 1,
                  onChanged: _handleChanged,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  onSubmitted: (_) => widget.onSubmit(),
                  decoration: InputDecoration(
                    hintText: 'agentPromptHint'.tr(),
                    hintMaxLines: 1,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              if (widget.working)
                IconButton(
                  tooltip: 'commonStop'.tr(),
                  onPressed: widget.onStop,
                  icon: const Icon(Symbols.stop),
                ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  // An attachment that could not be read keeps the turn here:
                  // what was written and what would be sent have to be the
                  // same thing. The tooltip says which control is holding it.
                  final failed = widget.attachments.any(
                    (attachment) => attachment.error != null,
                  );
                  final canSend =
                      widget.enabled &&
                      !failed &&
                      (value.text.trim().isNotEmpty ||
                          widget.attachments.any(
                            (attachment) => attachment.isSendable,
                          ));
                  return IconButton.filled(
                    tooltip: failed
                        ? 'agentAttachmentSendBlocked'.tr()
                        : widget.working
                        ? 'agentQueueMessage'.tr()
                        : 'agentSendMessage'.tr(),
                    onPressed: canSend ? widget.onSubmit : null,
                    icon: Icon(
                      widget.working ? Symbols.schedule : Symbols.send,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _ReasoningPill(
                reasoning: widget.reasoning,
                onChanged: widget.onReasoningChanged,
              ),
              if (widget.status case final status?) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: status),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _previewAttachment(
    BuildContext context,
    AgentAttachment attachment,
  ) => showDialog<void>(
    context: context,
    builder: (context) => _AttachmentPreviewDialog(attachment: attachment),
  );
}

/// The reasoning-effort pill: how hard the model thinks before it answers, set
/// where the message is written rather than buried in settings.
///
/// Three levels, because this strip has room for a dial, not a menu: low,
/// medium and high are the choices a reader can hold in mind. No level lit is
/// the model's own default — which is also where tapping the lit level again
/// returns, so the untouched state is never lost once the pill has been
/// touched.
///
/// The level is a standing choice sent with the next turn, so the pill does not
/// block while a turn is in flight: it says what the next request will carry.
class _ReasoningPill extends StatelessWidget {
  const _ReasoningPill({required this.reasoning, required this.onChanged});

  /// The levels the pill offers, in the order it shows them.
  static const _levels = [
    AgentReasoning.low,
    AgentReasoning.medium,
    AgentReasoning.high,
  ];

  final AgentReasoning reasoning;
  final ValueChanged<AgentReasoning> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _levels.contains(reasoning) ? reasoning : null;
    return Tooltip(
      message: active == null
          ? '${'agentReasoningEffort'.tr()}: '
                '${'agentReasoningModelDefault'.tr()}'
          : '${'agentReasoningEffort'.tr()}: ${active.labelKey.tr()}\n'
                '${'agentReasoningResetHint'.tr()}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 5, right: 4),
                child: Icon(
                  Symbols.psychology,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              for (final level in _levels)
                _ReasoningChip(
                  label: level.labelKey.tr(),
                  selected: level == active,
                  onTap: () => onChanged(
                    level == active ? AgentReasoning.modelDefault : level,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// One level in the pill: the lit one wears the accent's tint, the rest stay at
/// rest, so the pill's colour keeps meaning the reader made a choice.
class _ReasoningChip extends StatelessWidget {
  const _ReasoningChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// One queued attachment: a text card, or an image wearing the file's own
/// picture, with the control that takes it out of the turn.
class _AgentAttachmentTile extends StatelessWidget {
  const _AgentAttachmentTile({
    required this.attachment,
    required this.onRemove,
    this.onEdit,
    this.onPreview,
  });

  /// The tile's height, and the width of an image in it.
  static const double size = 60;

  final AgentAttachment attachment;
  final VoidCallback onRemove;

  /// Opens the text for editing. Null for an image, which has nothing to edit
  /// here.
  final VoidCallback? onEdit;

  /// Opens the picture whole. Null for a text attachment.
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = attachment.error;
    return Tooltip(
      message:
          error ??
          (onEdit != null
              ? 'agentAttachmentEdit'.tr(args: [attachment.name])
              : attachment.name),
      child: SizedBox(
        width: attachment.isImage ? size : 190,
        height: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: error != null
                  ? _buildFailure(scheme)
                  : attachment.isImage
                  ? _buildImage(context)
                  : _buildText(context),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'agentAttachmentRemove'.tr(args: [attachment.name]),
                iconSize: 12,
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHighest,
                  minimumSize: const Size(20, 20),
                  padding: EdgeInsets.zero,
                  // Without this the button keeps a 48-pixel tap target, which
                  // on a 60-pixel tile covers the tile it sits on.
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onRemove,
                icon: const Icon(Symbols.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailure(ColorScheme scheme) => Material(
    color: scheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error),
      ),
      child: Center(
        child: Icon(Symbols.error_outline, size: 20, color: scheme.error),
      ),
    ),
  );

  Widget _buildImage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = attachment.bytes;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPreview,
        child: bytes == null
            ? Center(
                child: Icon(
                  Symbols.image,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : Image.memory(bytes, fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildText(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 22, 6),
          child: Row(
            children: [
              Icon(
                Symbols.description,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      'agentAttachmentCharacters'.tr(
                        args: [
                          formatAttachmentCharacters(attachment.characterCount),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A queued image, open whole: a screenshot is read for what it shows, and a
/// 60-pixel tile is not enough of it to read.
class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({required this.attachment});

  final AgentAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final bytes = attachment.bytes;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (bytes != null)
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The editor behind a queued text attachment: the pasted block, whole, and a
/// way back to the message field.
class _TextAttachmentDialog extends StatefulWidget {
  const _TextAttachmentDialog({required this.name, required this.text});

  final String name;
  final String text;

  @override
  State<_TextAttachmentDialog> createState() => _TextAttachmentDialogState();
}

class _TextAttachmentDialogState extends State<_TextAttachmentDialog> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
      child: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('commonCancel'.tr()),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: Text('commonSave'.tr()),
      ),
    ],
  );
}

/// Opens the editor for one queued text attachment and answers with what it
/// was changed to, or null when the reader backed out.
Future<String?> showTextAttachmentEditor(
  BuildContext context, {
  required String name,
  required String text,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextAttachmentDialog(name: name, text: text),
);

/// The attachments a sent user turn carried, shown on its bubble by name: the
/// file the model was given is named by the same name it was given.
class AgentAttachmentChips extends StatelessWidget {
  const AgentAttachmentChips({super.key, required this.attachments});

  final List<AgentAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final attachment in attachments)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  attachment.isImage ? Symbols.image : Symbols.description,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    attachment.error == null
                        ? attachment.name
                        : '${attachment.name} — ${attachment.error}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The one contiguous block [after] gained over [before], with where it starts,
/// or null when the change was not a single insertion (a deletion, a typing
/// burst of separate edits, an IME composition).
({int start, String text})? _insertedBlock(String before, String after) {
  if (after.length <= before.length) return null;
  var start = 0;
  while (start < before.length && before[start] == after[start]) {
    start++;
  }
  var suffix = 0;
  while (suffix < before.length - start &&
      suffix < after.length - start &&
      before[before.length - 1 - suffix] == after[after.length - 1 - suffix]) {
    suffix++;
  }
  final text = after.substring(start, after.length - suffix);
  if (after.replaceRange(start, start + text.length, '') != before) return null;
  return (start: start, text: text);
}
