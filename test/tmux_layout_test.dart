import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/session_layout.dart';
import 'package:maid_kit/servers/tmux_layout.dart';

void main() {
  test('a single pane leaf maps to its pane id', () {
    final layout = tmuxLayoutToSessionLayout(
      '{"V":2,"L":{"t":"p","w":80,"h":24,"x":0,"y":0,"a":true,"i":0,"I":"%2"}}',
      windowId: '@1',
    );
    expect(layout, const SessionLayoutLeaf('%2'));
  });

  test('two equal children become one half split', () {
    final layout = tmuxLayoutToSessionLayout(
      '{"V":2,"L":{"t":"h","w":160,"h":24,"x":0,"y":0,'
      '"c":[{"t":"p","w":80,"h":24,"x":0,"y":0,"I":"%0"},'
      '{"t":"p","w":80,"h":24,"x":80,"y":0,"I":"%1"}]}}',
      windowId: '@2',
    );
    expect(layout, isA<SessionLayoutSplit>());
    final split = layout! as SessionLayoutSplit;
    expect(split.axis, SessionSplitAxis.horizontal);
    expect(split.ratio, 0.5);
    expect(split.first, const SessionLayoutLeaf('%0'));
    expect(split.second, const SessionLayoutLeaf('%1'));
    expect(split.id, 'tmux-@2-0');
  });

  test('a vertical container becomes a vertical split', () {
    final layout =
        tmuxLayoutToSessionLayout(
              '{"V":2,"L":{"t":"v","w":80,"h":48,"x":0,"y":0,'
              '"c":[{"t":"p","w":80,"h":12,"x":0,"y":0,"I":"%0"},'
              '{"t":"p","w":80,"h":36,"x":0,"y":12,"I":"%1"}]}}',
              windowId: '@3',
            )!
            as SessionLayoutSplit;
    expect(layout.axis, SessionSplitAxis.vertical);
    expect(layout.ratio, 0.25);
  });

  test('three children fold into two nested splits', () {
    final layout =
        tmuxLayoutToSessionLayout(
              '{"V":2,"L":{"t":"h","w":120,"h":24,"x":0,"y":0,'
              '"c":[{"t":"p","w":40,"h":24,"x":0,"y":0,"I":"%0"},'
              '{"t":"p","w":40,"h":24,"x":40,"y":0,"I":"%1"},'
              '{"t":"p","w":40,"h":24,"x":80,"y":0,"I":"%2"}]}}',
              windowId: '@4',
            )!
            as SessionLayoutSplit;
    expect(layout.ratio, closeTo(1 / 3, 1e-9));
    expect(layout.first, const SessionLayoutLeaf('%0'));
    final rest = layout.second as SessionLayoutSplit;
    expect(rest.ratio, 0.5);
    expect(tmuxPaneOrder(layout), ['%0', '%1', '%2']);
  });

  test('re-parsing the same layout yields an equal tree', () {
    const json =
        '{"V":2,"L":{"t":"h","w":160,"h":24,"x":0,"y":0,'
        '"c":[{"t":"p","w":80,"h":24,"x":0,"y":0,"I":"%0"},'
        '{"t":"p","w":80,"h":24,"x":80,"y":0,"I":"%1"}]}}';
    expect(
      tmuxLayoutToSessionLayout(json, windowId: '@5'),
      tmuxLayoutToSessionLayout(json, windowId: '@5'),
    );
  });

  test('a leaf without a pane id is rejected', () {
    expect(
      tmuxLayoutToSessionLayout(
        '{"V":2,"L":{"t":"p","w":80,"h":24,"x":0,"y":0}}',
        windowId: '@6',
      ),
      isNull,
    );
  });

  test('malformed json is rejected', () {
    expect(tmuxLayoutToSessionLayout('not json', windowId: '@7'), isNull);
  });

  // The strings below are what a tmux without the `new-layouts` flag actually
  // reports, for both `#{window_layout}` and `%layout-change`. They are format
  // 1: a four-hex checksum, then nested cells.
  test('a legacy one-pane window maps to its pane id', () {
    expect(
      tmuxLayoutToSessionLayout('b25d,80x24,0,0,0', windowId: '@8'),
      const SessionLayoutLeaf('%0'),
    );
  });

  test('a legacy row of panes becomes nested horizontal splits', () {
    // id=%0 idx=0 w=5 | %13 w=4 | %11 w=9 | %9 w=19 | %6 w=39
    final layout =
        tmuxLayoutToSessionLayout(
              '5525,80x24,0,0{5x24,0,0,0,4x24,6,0,13,9x24,11,0,11,'
              '19x24,21,0,9,39x24,41,0,6}',
              windowId: '@9',
            )!
            as SessionLayoutSplit;
    expect(layout.axis, SessionSplitAxis.horizontal);
    expect(layout.paneIds, ['%0', '%13', '%11', '%9', '%6']);
    // The five cells are 5+4+9+19+39 = 76 wide, so the first side is 5/76 of
    // the row. That is below the minimum a draggable gutter allows, so it
    // clamps — the same bound every other layout respects.
    expect(layout.ratio, closeTo(0.15, 0.001));
    final second = layout.second as SessionLayoutSplit;
    expect(second.axis, SessionSplitAxis.horizontal);
  });

  test('a legacy column becomes a vertical split', () {
    final layout =
        tmuxLayoutToSessionLayout(
              'bb11,80x24,0,0[40x12,0,0,3,39x11,0,13,4]',
              windowId: '@10',
            )!
            as SessionLayoutSplit;
    expect(layout.axis, SessionSplitAxis.vertical);
    expect(layout.paneIds, ['%3', '%4']);
  });

  test('a legacy layout with a bad checksum prefix is rejected', () {
    expect(tmuxLayoutToSessionLayout('nope', windowId: '@11'), isNull);
    expect(tmuxLayoutToSessionLayout('b25d,', windowId: '@11'), isNull);
  });
}
