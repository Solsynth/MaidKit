import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('SudoPromptAutofill', () {
    test('replaces bare Enter with the secret at an English prompt', () {
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('[sudo] password for alice: '));
      expect(autofill.prompting, isTrue);
      expect(autofill.reason, SudoPromptReason.prompt);
      expect(autofill.intercept(_bytes('\r')), _bytes('hunter2\r'));
      expect(autofill.prompting, isFalse);
    });

    test('does not arm on a sudo command line until the prompt appears', () {
      // Issue #73: pasting a sudo command then pressing Enter must not inject
      // the saved SSH password into the next command. The command line alone
      // merely echoes the word "sudo"; sudo may be passwordless, so autofill
      // arms only once a real password prompt is on screen.
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('\r\nuser@host:~\$ sudo apt update\r\n'));
      expect(autofill.prompting, isFalse);
      expect(autofill.reason, isNull);
      expect(autofill.intercept(_bytes('\r')), _bytes('\r'));
      // The following command runs without the secret leaking in.
      autofill.inspect(_bytes('\r\nuser@host:~\$ useradd alice\r\n'));
      expect(autofill.intercept(_bytes('\r')), _bytes('\r'));
      // A real prompt still autofills.
      autofill.inspect(_bytes('[sudo] password for alice: '));
      expect(autofill.prompting, isTrue);
      expect(autofill.reason, SudoPromptReason.prompt);
      expect(autofill.intercept(_bytes('\r')), _bytes('hunter2\r'));
    });

    test('does not arm on plain commands or non-sudo output', () {
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('\r\nuser@host:~\$ apt update\r\n'));
      expect(autofill.prompting, isFalse);
      autofill.inspect(_bytes('sudoers file check: ok\r\n'));
      expect(autofill.prompting, isFalse);
      autofill.inspect(_bytes('\r\nuser@host:~\$ sudo\r\n'));
      expect(autofill.prompting, isFalse);
      // A pasted line containing "sudo" anywhere must not arm the autofill;
      // the next Enter runs a normal command, not sudo's password prompt.
      autofill.inspect(
        _bytes('\r\nuser@host:~\$ sudo apt update && mkdir /x\r\n'),
      );
      expect(autofill.prompting, isFalse);
    });

    test('matches the sudo-rs prompt used by Ubuntu 26', () {
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('[sudo: authenticate] Password: '));
      expect(autofill.prompting, isTrue);
      expect(autofill.intercept(_bytes('\r')), _bytes('hunter2\r'));
      // Case-insensitive for locale capitalisation.
      autofill.inspect(_bytes('[sudo: authenticate] password: '));
      expect(autofill.prompting, isTrue);
    });

    test('ignores non-sudo password questions', () {
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('alice@remote password: '));
      expect(autofill.prompting, isFalse);
      autofill.inspect(_bytes('su: Authentication failure\nPassword: '));
      expect(autofill.prompting, isFalse);
      expect(autofill.intercept(_bytes('\r')), _bytes('\r'));
    });

    test('disarms when the user types their own input', () {
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('[sudo] password for alice: '));
      // Typing a character forwards it untouched and stops interception.
      expect(autofill.intercept(_bytes('x')), _bytes('x'));
      expect(autofill.intercept(_bytes('\r')), _bytes('\r'));
    });

    test('re-arms after a failed attempt redraws the prompt', () {
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('[sudo] password for alice: '));
      autofill.intercept(_bytes('\r'));
      autofill.inspect(
        _bytes('\r\nSorry, try again.\r\n[sudo] password for alice: '),
      );
      expect(autofill.prompting, isTrue);
      expect(autofill.intercept(_bytes('\r')), _bytes('hunter2\r'));
    });

    test('clears the prompt once the command output continues', () {
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('[sudo] password for alice: '));
      autofill.inspect(_bytes('\r\noutput line without a prompt\r\n'));
      expect(autofill.prompting, isFalse);
    });

    test('escape sequences never satisfy the matcher', () {
      final autofill = SudoPromptAutofill('hunter2');
      autofill.inspect(_bytes('\x1B[2K\x1B[1G[sudo] password for alice: '));
      expect(autofill.prompting, isTrue);
      // A split control sequence leaves no stray matcher text behind.
      autofill.intercept(_bytes('\r'));
      autofill.inspect(_bytes('\x1B[3'));
      expect(autofill.prompting, isFalse);
    });

    test('is inert without a secret', () {
      final autofill = SudoPromptAutofill(null);
      autofill.inspect(_bytes('[sudo] password for alice: '));
      expect(autofill.prompting, isFalse);
      expect(autofill.intercept(_bytes('\r')), _bytes('\r'));
      expect(SudoPromptAutofill('').prompting, isFalse);
    });
  });
}
