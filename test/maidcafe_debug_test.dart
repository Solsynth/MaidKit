import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/maidcafe_debug.dart';

void main() {
  tearDown(() {
    maidCafeLogCredentials = false;
  });

  test('a credential reads as its length and a stable digest', () {
    final described = maidCafeDescribeCredential('super-secret-value');

    // The secret itself is never written down by default.
    expect(described, isNot(contains('super-secret-value')));
    expect(described, contains('len=18'));
    // Equal inputs read equal, so two logs can be compared.
    expect(
      maidCafeDescribeCredential('super-secret-value'),
      maidCafeDescribeCredential('super-secret-value'),
    );
    expect(
      maidCafeDescribeCredential('super-secret-value'),
      isNot(maidCafeDescribeCredential('super-secret-valu3')),
    );
  });

  test('an absent credential is distinct from an empty one', () {
    // "the field was never filled" and "the field is filled with nothing" are
    // different problems, so they cannot read the same.
    expect(maidCafeDescribeCredential(null), 'none');
    expect(maidCafeDescribeCredential(''), 'empty');
  });

  test('the raw value appears only when credential logging is on', () {
    expect(maidCafeDescribeCredential('secret'), isNot(contains('"secret"')));

    maidCafeLogCredentials = true;
    expect(maidCafeDescribeCredential('secret'), contains('"secret"'));
  });

  test('a secret summary names each credential the route can use', () {
    final summary = maidCafeDescribeSecret(
      terminalSecret: 'terminal-secret',
      metricsSecret: null,
      cloudSecret: 'cloud-secret',
    );

    expect(summary, contains('terminal='));
    expect(summary, contains('metrics=none'));
    expect(summary, contains('cloud='));
    expect(summary, isNot(contains('terminal-secret')));
    expect(summary, isNot(contains('cloud-secret')));
  });
}
