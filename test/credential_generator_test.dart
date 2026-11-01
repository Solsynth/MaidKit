import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/credential_generator.dart';

void main() {
  group('generatePassword', () {
    test('honours the requested length and classes', () {
      final password = generatePassword(length: 24);
      expect(password.length, 24);
      expect(password.contains(RegExp('[a-z]')), isTrue);
      expect(password.contains(RegExp('[A-Z]')), isTrue);
      expect(password.contains(RegExp('[0-9]')), isTrue);
    });

    test('only uses the enabled classes', () {
      final digits = generatePassword(
        length: 16,
        uppercase: false,
        lowercase: false,
        symbols: false,
      );
      expect(digits, matches(RegExp(r'^[2-9]{16}$')));

      final letters = generatePassword(
        length: 16,
        digits: false,
        symbols: false,
      );
      expect(letters, matches(RegExp(r'^[A-Za-z]{16}$')));
    });

    test('never returns fewer characters than the enabled classes', () {
      final password = generatePassword(length: 1);
      expect(password.length, 4);
    });

    test('draws a different password each call', () {
      final seen = {for (var i = 0; i < 8; i++) generatePassword()};
      expect(seen.length, 8);
    });
  });

  group('generateSshKeyPair', () {
    test('ed25519 keys parse back and match their public half', () async {
      final generated = await generateSshKeyPair(comment: 'ci-runner');

      expect(generated.type, SshKeyType.ed25519);
      expect(generated.comment, 'ci-runner');
      expect(generated.privateKeyPem, contains('BEGIN OPENSSH PRIVATE KEY'));
      expect(generated.publicKey, startsWith('ssh-ed25519 AAAA'));
      expect(generated.publicKey, endsWith(' ci-runner'));

      final parsed = SSHKeyPair.fromPem(generated.privateKeyPem);
      expect(parsed, hasLength(1));
      expect(parsed.single.name, 'ssh-ed25519');
      expect(parsed.single.comment, 'ci-runner');
      expect(
        '${parsed.single.name} ${base64.encode(parsed.single.toPublicKey().encode())}',
        generated.publicKey.substring(0, generated.publicKey.lastIndexOf(' ')),
      );
    });

    test('passphrase-protected keys only open with that passphrase', () async {
      final generated = await generateSshKeyPair(passphrase: 'correct horse');

      expect(
        SSHKeyPair.isEncryptedPem(generated.privateKeyPem),
        isTrue,
        reason: 'the private key must not be stored in the clear',
      );
      expect(
        SSHKeyPair.fromPem(generated.privateKeyPem, 'correct horse'),
        hasLength(1),
      );
      expect(
        () => SSHKeyPair.fromPem(generated.privateKeyPem, 'wrong'),
        throwsA(isA<SSHKeyDecryptError>()),
      );
    });

    test('rsa keys parse back at the requested size', () async {
      final generated = await generateSshKeyPair(
        type: SshKeyType.rsa,
        rsaBits: 2048,
        comment: 'legacy',
      );

      expect(generated.publicKey, startsWith('ssh-rsa AAAA'));
      final parsed = SSHKeyPair.fromPem(generated.privateKeyPem);
      expect(parsed.single.name, 'ssh-rsa');
      // ssh-rsa signs with rsa-sha2-256 on modern servers.
      expect(parsed.single.type, 'rsa-sha2-256');
    });

    test('every call mints a distinct key', () async {
      final first = await generateSshKeyPair();
      final second = await generateSshKeyPair();
      expect(first.privateKeyPem, isNot(second.privateKeyPem));
      expect(first.publicKey, isNot(second.publicKey));
    });

    test('a blank comment falls back to the default', () async {
      final generated = await generateSshKeyPair(comment: '   ');
      expect(generated.comment, defaultSshKeyComment);
      expect(generated.publicKey, endsWith(' $defaultSshKeyComment'));
    });
  });
}
