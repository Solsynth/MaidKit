import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/shared/services/user_agent.dart';
import 'package:package_info_plus/package_info_plus.dart';

ResponseBody _json(int status) => ResponseBody.fromString(
  '{}',
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'maid_kit',
      packageName: 'dev.solsynth.maid',
      version: '3.1.0',
      buildNumber: '52',
      buildSignature: '',
    );
  });

  test('stamps every request with the MaidKit user agent', () async {
    late RequestOptions seen;
    final dio = maidKitDio()
      ..httpClientAdapter = _Adapter((options) async {
        seen = options;
        return _json(200);
      });

    await dio.get<dynamic>('https://api.solian.app/valve/workspaces');

    final agent = await maidKitUserAgent();
    expect(agent, startsWith('MaidKit/3.1.0+52 ('));
    expect(seen.headers['User-Agent'], agent);
  });

  test('attaches once and leaves an explicit user agent alone', () async {
    final dio = maidKitDio();
    final attached = dio.interceptors.length;
    maidKitDio(dio);
    expect(dio.interceptors.length, attached);

    late RequestOptions seen;
    dio.httpClientAdapter = _Adapter((options) async {
      seen = options;
      return _json(200);
    });
    await dio.get<dynamic>(
      'https://api.solian.app/personality/agents',
      options: Options(headers: {'User-Agent': 'custom/1.0'}),
    );
    expect(seen.headers['User-Agent'], 'custom/1.0');
  });

  test('header value is plain printable ASCII', () async {
    expect(await maidKitUserAgent(), matches(RegExp(r'^[\x20-\x7e]+$')));
    expect((await maidKitUserAgentHeader())['User-Agent'], isNotEmpty);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Object>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}
