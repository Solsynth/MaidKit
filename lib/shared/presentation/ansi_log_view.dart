import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app_scaffold.dart';
import '../../servers/server_providers.dart';
import '../../servers/terminal_find_host.dart';
import '../../servers/terminal_session_adapter.dart';

/// Read-only log surface that reuses MaidTerm so container logs and task
/// output share the same VT parser, colors, and renderer as interactive
/// sessions.
///
/// [streaming] mode is for live CLI output (compose pull, deploy, etc.):
/// - appends only new suffix bytes instead of rebuilding the terminal
/// - preserves carriage returns so progress lines rewrite in place
/// - keeps ANSI color sequences intact
///
/// Full-dump mode (default) is for one-shot log payloads such as container
/// logs: the buffer is rewritten whenever [text] changes, and bare newlines
/// are normalized to CRLF so each line starts at column 0.
class AnsiLogView extends ConsumerStatefulWidget {
  const AnsiLogView({
    super.key,
    required this.text,
    this.streaming = false,

    /// Only bottom corners are rounded by default — the log pane sits under a
    /// tab bar that already provides the top edge of the panel.
    this.borderRadius = const BorderRadius.vertical(
      bottom: Radius.circular(12),
    ),
  });

  final String text;
  final bool streaming;
  final BorderRadius borderRadius;

  @override
  ConsumerState<AnsiLogView> createState() => _AnsiLogViewState();
}

class _AnsiLogViewState extends ConsumerState<AnsiLogView> {
  TerminalSessionAdapter? _adapter;
  String _writtenText = '';
  var _writeGeneration = 0;

  /// True while a deferred bulk write is scheduled for the current adapter.
  /// Prevents [build] / parent rebuilds from cancelling that write by forcing
  /// a recreate loop (which left the log pane blank).
  var _writeScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bindAdapter(force: true);
    });
  }

  @override
  void didUpdateWidget(AnsiLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streaming != widget.streaming) {
      _bindAdapter(force: true);
      return;
    }
    if (oldWidget.text == widget.text) return;
    if (widget.streaming) {
      _appendStreamDelta();
    } else {
      // Full dumps replace the buffer; recreate so old lines do not linger.
      _bindAdapter(force: true);
    }
  }

  @override
  void dispose() {
    _writeGeneration++;
    _writeScheduled = false;
    unawaited(_adapter?.dispose() ?? Future<void>.value());
    _adapter = null;
    super.dispose();
  }

  void _bindAdapter({bool force = false}) {
    final factory = ref.read(terminalSessionAdapterFactoryProvider);
    final recreate = force || _adapter == null;
    if (!recreate) {
      if (widget.streaming) {
        _appendStreamDelta();
      } else if (_writtenText != widget.text) {
        _scheduleLogDump(_adapter!);
      }
      return;
    }

    final previous = _adapter;
    final adapter = factory.create();
    _writeGeneration++;
    _adapter = adapter;
    _writtenText = '';
    _writeScheduled = false;
    setState(() {});

    if (widget.streaming) {
      _scheduleStreamingWrite(adapter);
    } else {
      _scheduleLogDump(adapter);
    }

    unawaited(previous?.dispose() ?? Future<void>.value());
  }

  /// Wait two frames so MaidTerm can size the grid before a bulk dump.
  void _scheduleLogDump(TerminalSessionAdapter adapter) {
    final generation = ++_writeGeneration;
    _writeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _writeGeneration) return;
        if (!identical(_adapter, adapter)) return;
        _writeLogDump(adapter, widget.text);
        _writtenText = widget.text;
        _writeScheduled = false;
      });
    });
  }

  void _scheduleStreamingWrite(TerminalSessionAdapter adapter) {
    final generation = ++_writeGeneration;
    _writeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _writeGeneration) return;
        if (!identical(_adapter, adapter)) return;
        _writeStreaming(adapter, widget.text);
        _writtenText = widget.text;
        _writeScheduled = false;
      });
    });
  }

  void _appendStreamDelta() {
    final adapter = _adapter;
    if (adapter == null) return;
    final next = widget.text;
    if (next == _writtenText) return;

    if (_writtenText.isNotEmpty && next.startsWith(_writtenText)) {
      final delta = next.substring(_writtenText.length);
      _writeStreaming(adapter, delta);
      _writtenText = next;
      return;
    }

    // Non-prefix update (session reset / replace) — rebuild cleanly.
    _bindAdapter(force: true);
  }

  /// Full log dump: normalize all newlines to CRLF so each line starts at
  /// column 0 (VT line discipline treats bare LF as "move down, keep column").
  void _writeLogDump(TerminalSessionAdapter adapter, String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.isEmpty) return;
    final withCrlf = normalized.replaceAll('\n', '\r\n');
    final payload = withCrlf.endsWith('\r\n') ? withCrlf : '$withCrlf\r\n';
    adapter.write(Uint8List.fromList(utf8.encode(payload)));
  }

  /// Live CLI stream: keep lone CR for in-line progress rewrites, convert bare
  /// LF to CRLF, and leave ANSI sequences untouched for the VT parser.
  void _writeStreaming(TerminalSessionAdapter adapter, String text) {
    if (text.isEmpty) return;
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code == 0x0d) {
        // CR
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0a) {
          out.write('\r\n');
          i++;
        } else {
          out.writeCharCode(0x0d);
        }
      } else if (code == 0x0a) {
        out.write('\r\n');
      } else {
        out.writeCharCode(code);
      }
    }
    if (out.isEmpty) return;
    adapter.write(Uint8List.fromList(utf8.encode(out.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final adapter = _adapter;
    if (adapter == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Mirror the interactive terminal: a transparent terminal lets the app
    // surface show through; otherwise fall back to the opaque terminal slab.
    // Passing [transparentBackground] through also keeps the opacity in sync
    // when the user toggles the setting while a log is on screen.
    final transparent = ref.watch(transparentTerminalBackgroundProvider);

    // If a dump never landed (e.g. interrupted by dispose/recreate), schedule
    // a write — never force-recreate here, or we cancel the deferred write.
    if (!widget.streaming && _writtenText != widget.text && !_writeScheduled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _writtenText == widget.text || _writeScheduled) return;
        final current = _adapter;
        if (current != null) _scheduleLogDump(current);
      });
    }

    // Clip bottom corners, expand so the terminal gets a bounded viewport, and
    // enable mouse/trackpad drag devices for nested scrollables.
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: ColoredBox(
        color: transparent ? Colors.transparent : const Color(0xFF111315),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: true,
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          // Absorb vertical scroll notifications so TabBarView / modal sheets
          // do not steal them when the user scrolls logs.
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) => true,
            child: SizedBox.expand(
              child: TerminalFindHost(
                adapter: adapter,
                autofocus: false,
                readOnly: true,
                showCursor: false,
                transparentBackground: transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
