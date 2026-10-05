import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/agent/ssh_agent_service.dart';

void main() {
  group('settleTerminalOutput', () {
    test('keeps plain output untouched', () {
      expect(
        settleTerminalOutput('total 4\ndrwxr-xr-x 2 root root\n'),
        'total 4\ndrwxr-xr-x 2 root root\n',
      );
    });

    test('folds the CRLF line endings a PTY reports', () {
      expect(settleTerminalOutput('one\r\ntwo\r\n'), 'one\ntwo\n');
    });

    test('keeps only the last frame of an in-place progress line', () {
      expect(settleTerminalOutput('10%\r 20%\r 30%\nnext'), ' 30%\nnext');
    });

    test(
      'keeps a line whose frame returned to column zero without writing',
      () {
        expect(settleTerminalOutput('done\r\n'), 'done\n');
        expect(settleTerminalOutput('done\r'), 'done');
      },
    );

    test('drops ANSI color and erase sequences', () {
      expect(
        settleTerminalOutput('\x1B[31mred\x1B[0m\r\n\x1B[Kclean'),
        'red\nclean',
      );
    });

    test('keeps the rewritten text after an erase-to-end-of-line', () {
      expect(settleTerminalOutput('100%\r\x1B[K 50%'), ' 50%');
    });

    test('leaves an empty string empty', () {
      expect(settleTerminalOutput(''), '');
    });
  });
}
