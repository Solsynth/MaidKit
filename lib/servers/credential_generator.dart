import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:pointycastle/export.dart';

/// The SSH key algorithms the credentials page can mint.
///
/// Both are written as `OPENSSH PRIVATE KEY` — the format `SSHKeyPair.fromPem`
/// (and therefore the connection manager) reads back — so a generated key can
/// be saved and used without a conversion step.
enum SshKeyType { ed25519, rsa }

/// Key sizes offered for [SshKeyType.rsa]. 3072 is the size OpenSSH suggests by
/// default; 2048 stays available for older servers.
const rsaKeySizes = [2048, 3072, 4096];

/// The comment appended to a generated public key when the user leaves it
/// blank.
const defaultSshKeyComment = 'maidkit';

const _lowercase = 'abcdefghijkmnopqrstuvwxyz';
const _uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const _digits = '23456789';
const _symbols = r'!@#$%^&*()-_=+[]{};:,.?/';

/// A freshly generated password.
///
/// Every enabled class contributes at least one character, so a caller that
/// asks for digits never gets a digits-free password from an unlucky draw.
String generatePassword({
  int length = 20,
  bool uppercase = true,
  bool lowercase = true,
  bool digits = true,
  bool symbols = true,
  Random? random,
}) {
  final classes = <String>[
    if (lowercase) _lowercase,
    if (uppercase) _uppercase,
    if (digits) _digits,
    if (symbols) _symbols,
  ];
  if (classes.isEmpty) {
    throw ArgumentError('At least one character class must be enabled');
  }
  final size = length < classes.length ? classes.length : length;
  final rng = random ?? Random.secure();
  final pool = classes.join();
  final chars = <String>[
    for (final alphabet in classes) alphabet[rng.nextInt(alphabet.length)],
    for (var i = classes.length; i < size; i++) pool[rng.nextInt(pool.length)],
  ];
  // Fisher-Yates, so the guaranteed characters do not stay at the front.
  for (var i = chars.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join();
}

/// A generated SSH key pair: the private key in OpenSSH PEM, plus the
/// `authorized_keys` line that installs it on a server.
class GeneratedSshKeyPair {
  const GeneratedSshKeyPair({
    required this.type,
    required this.privateKeyPem,
    required this.publicKey,
    required this.comment,
  });

  final SshKeyType type;

  /// `-----BEGIN OPENSSH PRIVATE KEY-----` …, encrypted with the passphrase the
  /// caller supplied if there was one.
  final String privateKeyPem;

  /// `ssh-ed25519 AAAA… comment`, ready to append to `~/.ssh/authorized_keys`.
  final String publicKey;

  final String comment;
}

/// Generates [type]'s key pair off the UI isolate.
///
/// RSA generation is CPU-bound (seconds at 4096 bits) and the passphrase path
/// runs bcrypt over the key, so both go through [compute]. [passphrase]
/// encrypts the private key with OpenSSH's `bcrypt` KDF; null or empty writes
/// the unencrypted form.
Future<GeneratedSshKeyPair> generateSshKeyPair({
  SshKeyType type = SshKeyType.ed25519,
  int rsaBits = 3072,
  String? passphrase,
  String? comment,
}) {
  final trimmed = comment?.trim() ?? '';
  return compute(_generateSshKeyPair, (
    type: type.name,
    rsaBits: rsaBits,
    passphrase: passphrase == null || passphrase.isEmpty ? null : passphrase,
    comment: trimmed.isEmpty ? defaultSshKeyComment : trimmed,
  )).then(
    (result) => GeneratedSshKeyPair(
      type: type,
      privateKeyPem: result.privateKeyPem,
      publicKey: result.publicKey,
      comment: result.comment,
    ),
  );
}

/// Isolate entry point. It hands back strings only, so no key object has to be
/// transferable.
Future<({String privateKeyPem, String publicKey, String comment})>
_generateSshKeyPair(
  ({String type, int rsaBits, String? passphrase, String comment}) request,
) async {
  final type = SshKeyType.values.byName(request.type);
  final OpenSSHKeyPair pair = switch (type) {
    SshKeyType.ed25519 => await _ed25519KeyPair(request.comment),
    SshKeyType.rsa => _rsaKeyPair(request.rsaBits, request.comment),
  };
  final encoded = base64.encode(pair.toPublicKey().encode());
  return (
    privateKeyPem: pair.toPem(passphrase: request.passphrase),
    publicKey: '${pair.name} $encoded ${request.comment}',
    comment: request.comment,
  );
}

/// Ed25519 seeds come from `cryptography`, which draws them from its own secure
/// random source. OpenSSH stores the 64-byte secret as the seed followed by the
/// derived public key.
Future<OpenSSHEd25519KeyPair> _ed25519KeyPair(String comment) async {
  final keyPair = await Ed25519().newKeyPair();
  final seed = await keyPair.extractPrivateKeyBytes();
  final publicKey = (await keyPair.extractPublicKey()).bytes;
  return OpenSSHEd25519KeyPair(
    Uint8List.fromList(publicKey),
    Uint8List.fromList([...seed, ...publicKey]),
    comment,
  );
}

OpenSSHRsaKeyPair _rsaKeyPair(int bits, String comment) {
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
        FortunaRandom()..seed(KeyParameter(_randomBytes(32))),
      ),
    );
  final private = generator.generateKeyPair().privateKey;
  final p = private.p!;
  final q = private.q!;
  return OpenSSHRsaKeyPair(
    private.modulus!,
    private.publicExponent!,
    private.privateExponent!,
    q.modInverse(p),
    p,
    q,
    comment,
  );
}

Uint8List _randomBytes(int length) => Uint8List.fromList(
  List<int>.generate(length, (_) => Random.secure().nextInt(256)),
);
