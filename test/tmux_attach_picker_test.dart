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
  _freshNameTests();

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

void _freshNameTests() {
  test('a detached session keeps its name, so it is resumed', () {
    expect(
      nextTmuxSessionName(
        base: 'maidkit-build-host',
        existing: [_session('maidkit-build-host')],
      ),
      'maidkit-build-host',
    );
  });

  test('an attached session is never joined by a new terminal', () {
    // `new-session -A` would drop the new tab into that live session, and both
    // views would then share one pane size and one scrollback.
    expect(
      nextTmuxSessionName(
        base: 'maidkit-build-host',
        existing: [_session('maidkit-build-host', attached: 1)],
      ),
      'maidkit-build-host-2',
    );
  });

  test('a taken suffix is skipped rather than reused', () {
    expect(
      nextTmuxSessionName(
        base: 'maidkit-build-host',
        existing: [
          _session('maidkit-build-host', attached: 1),
          _session('maidkit-build-host-2', attached: 1),
          // A detached session still owns its name: reusing it would attach to
          // that session instead of creating another terminal.
          _session('maidkit-build-host-3'),
        ],
      ),
      'maidkit-build-host-4',
    );
  });

  test('a free name is used as-is', () {
    expect(
      nextTmuxSessionName(base: 'maidkit-build-host', existing: const []),
      'maidkit-build-host',
    );
  });
}
