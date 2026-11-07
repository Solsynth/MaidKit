// Which sessions the attach picker offers. The rule is what keeps a plain
// "open a terminal" from turning into a dialog: only sessions that MaidKit did
// not create itself are worth choosing between, and MaidKit names its own after
// the server.
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/tmux_sessions.dart';

TmuxSessionInfo _session(String name, {int attached = 0}) => TmuxSessionInfo(
  name: name,
  windows: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  attached: attached,
);

void main() {
  test('a session the user started is offered', () {
    final offered = attachableTmuxSessions([
      _session('maidkit-build-host'),
      _session('work', attached: 1),
    ], defaultName: 'maidkit-build-host');
    expect(offered.map((session) => session.name), ['work']);
  });

  test('only MaidKit sessions means nothing to choose', () {
    expect(
      attachableTmuxSessions([
        _session('maidkit-build-host'),
      ], defaultName: 'maidkit-build-host'),
      isEmpty,
    );
  });

  test('an empty host offers nothing', () {
    expect(
      attachableTmuxSessions(const [], defaultName: 'maidkit-build-host'),
      isEmpty,
    );
  });

  test(
    'a user session that merely looks like a maidkit one is still offered',
    () {
      final offered = attachableTmuxSessions([
        _session('maidkit-build-host'),
        _session('maidkit-other-host'),
      ], defaultName: 'maidkit-build-host');
      expect(offered.map((session) => session.name), ['maidkit-other-host']);
    },
  );
}
