import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/data/local/app_database.dart';

import 'maidcafe_debug.dart';
import 'maidcafe_service.dart';
import 'maidcafe_stream.dart';
import 'maidcafe_terminal_connection_manager.dart';
import 'server_models.dart';

/// Outcome of one step of a MaidCafe connectivity check.
enum MaidCafeConnectivityStatus { ok, failed, skipped }

/// One line of a [MaidCafeConnectivityReport].
class MaidCafeConnectivityStep {
  const MaidCafeConnectivityStep({
    required this.titleKey,
    required this.status,
    this.detail,
    this.detailKey,
  });

  /// Localization key of the step name.
  final String titleKey;

  final MaidCafeConnectivityStatus status;

  /// What the step found, already human readable (a resolved endpoint, or the
  /// transport's own failure message).
  final String? detail;

  /// A localization key for fixed explanations, used instead of [detail].
  final String? detailKey;
}

/// What one transport — the daemon dialed directly, or the cloud relay —
/// answered.
class MaidCafeConnectivityReport {
  const MaidCafeConnectivityReport({required this.relay, required this.steps});

  /// Whether this report probed the cloud relay instead of the daemon.
  final bool relay;

  final List<MaidCafeConnectivityStep> steps;

  /// Whether the server carries the configuration this route needs. A route
  /// that is not configured is skipped rather than failed.
  bool get configured =>
      steps.isNotEmpty &&
      steps.first.status != MaidCafeConnectivityStatus.skipped;

  bool get failed =>
      steps.any((step) => step.status == MaidCafeConnectivityStatus.failed);

  bool get ok => configured && !failed;
}

/// Everything a check touches, injectable so tests can drive every step
/// without a daemon, a cloud session, or a socket.
class MaidCafeConnectivityProbes {
  const MaidCafeConnectivityProbes({
    required this.resolveTarget,
    required this.checkHealth,
    required this.openTerminal,
  });

  /// Resolves the route's endpoint, or null when the server carries none.
  final Future<MaidCafeTerminalTarget?> Function({required bool relay})
  resolveTarget;

  /// Reads `<baseUrl>/health`, the daemon's or the cloud's liveness endpoint.
  final Future<MaidCafeDaemonHealth> Function(String baseUrl, String? secret)
  checkHealth;

  /// Opens and immediately closes a terminal: the handshake a real session
  /// performs, including the credential and (for a browser) the origin.
  final Future<void> Function(MaidCafeTerminalTarget target) openTerminal;
}

/// Checks the three things a MaidCafe route has to pass: a configured
/// endpoint, an answering `/health`, and a terminal handshake the daemon
/// accepts.
///
/// A stuck endpoint stops the report after the health step, because a transport
/// that never answered cannot handshake either. Every failure keeps the
/// transport's own message, so the report tells the user what to fix — a listen
/// address, a firewall, the terminal secret, a refused origin — instead of a
/// generic "cannot connect".
Future<MaidCafeConnectivityReport> runMaidCafeConnectivityCheck(
  MaidCafeConnectivityProbes probes, {
  required bool relay,
  bool? terminalEnabled,
  String notConfiguredKey = 'maidCafeCheckNotConfigured',
}) async {
  final steps = <MaidCafeConnectivityStep>[];

  Future<MaidCafeConnectivityReport> finish() async {
    // One line per run: the sheet renders the report, and this is what a user
    // asked to reproduce a failure can paste.
    maidCafeLog(
      'connectivity (relay=$relay terminalEnabled=$terminalEnabled): '
      '${steps.map((step) => '${step.titleKey}=${step.status.name}'
          '${step.detailKey != null ? '(${step.detailKey})' : ''}'
          '${step.detail != null ? '[${step.detail}]' : ''}').join(' | ')}',
    );
    return MaidCafeConnectivityReport(relay: relay, steps: steps);
  }

  final MaidCafeTerminalTarget? target;
  try {
    target = await probes.resolveTarget(relay: relay);
  } catch (error) {
    steps.add(
      MaidCafeConnectivityStep(
        titleKey: 'maidCafeCheckRoute',
        status: MaidCafeConnectivityStatus.failed,
        detail: describeMaidCafeError(error),
      ),
    );
    return finish();
  }
  if (target == null) {
    steps.add(
      MaidCafeConnectivityStep(
        titleKey: 'maidCafeCheckRoute',
        status: MaidCafeConnectivityStatus.skipped,
        detailKey: notConfiguredKey,
      ),
    );
    return finish();
  }
  steps.add(
    MaidCafeConnectivityStep(
      titleKey: 'maidCafeCheckRoute',
      status: MaidCafeConnectivityStatus.ok,
      detail: target.baseUrl,
    ),
  );

  // The daemon's own terminal switch comes before any network advice: a
  // disabled endpoint refuses every session, so an open port cannot help. It is
  // only reported when a client has read it — the caller refreshes it over SSH
  // when it can, and an unread switch stays silent rather than claiming a state.
  if (terminalEnabled != null) {
    steps.add(
      MaidCafeConnectivityStep(
        titleKey: 'maidCafeCheckTerminalEnabled',
        status: terminalEnabled
            ? MaidCafeConnectivityStatus.ok
            : MaidCafeConnectivityStatus.failed,
        detailKey: terminalEnabled ? null : 'maidCafeCheckTerminalDisabled',
      ),
    );
  }

  maidCafeLog(
    'checking $relay route: reachability at ${target.baseUrl} with '
    'credential ${maidCafeDescribeCredential(target.secret.isEmpty ? null : target.secret)}',
  );
  try {
    final health = await probes.checkHealth(
      target.baseUrl,
      target.secret.isEmpty ? null : target.secret,
    );
    steps.add(
      MaidCafeConnectivityStep(
        titleKey: 'maidCafeCheckReachability',
        status: MaidCafeConnectivityStatus.ok,
        detail: [?health.mode, ?health.id].join(' · '),
      ),
    );
  } catch (error) {
    steps.add(
      MaidCafeConnectivityStep(
        titleKey: 'maidCafeCheckReachability',
        status: MaidCafeConnectivityStatus.failed,
        detail: describeMaidCafeError(error),
      ),
    );
    return finish();
  }

  maidCafeLog('checking the terminal handshake against ${target.endpoint}');
  try {
    await probes.openTerminal(target);
    steps.add(
      const MaidCafeConnectivityStep(
        titleKey: 'maidCafeCheckTerminal',
        status: MaidCafeConnectivityStatus.ok,
      ),
    );
  } catch (error) {
    steps.add(
      MaidCafeConnectivityStep(
        titleKey: 'maidCafeCheckTerminal',
        status: MaidCafeConnectivityStatus.failed,
        detail: describeMaidCafeError(error),
      ),
    );
  }
  return finish();
}

/// Reads `<baseUrl>/health` with the route's credential, if it has one.
///
/// The probe is deliberately independent of the cloud session: a daemon that is
/// only reachable on the local network must check out without signing in.
Future<MaidCafeDaemonHealth> probeMaidCafeHealth(
  String baseUrl,
  String? secret,
) async {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: secret == null || secret.isEmpty
          ? null
          : <String, String>{'Authorization': 'Bearer $secret'},
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );
  maidCafeLog(
    'GET $baseUrl/health with ${secret == null || secret.isEmpty ? 'no credential' : 'credential ${maidCafeDescribeCredential(secret)}'}',
  );
  try {
    final response = await dio.get<dynamic>('/health');
    final data = response.data;
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : jsonDecode('$data') as Map<String, dynamic>;
    return MaidCafeDaemonHealth.fromJson(map);
  } finally {
    dio.close(force: true);
  }
}

/// Turns a transport failure into the one line the report shows.
String describeMaidCafeError(Object error) {
  if (error is MaidCafeTerminalException) return error.message;
  if (error is MaidCafeException) return error.message;
  if (error is DioException) {
    final status = error.response?.statusCode;
    final message = error.message ?? error.type.name;
    return status == null ? message : 'HTTP $status: $message';
  }
  return error.toString();
}

/// The TCP port a user has to expose for a direct daemon connection, and the
/// address the daemon listens on.
///
/// Read from what the app learned about the daemon — the port column a probe or
/// an install filled, then the stored endpoints — so an unreachable route names
/// exactly what to open instead of reporting "cannot connect".
({int port, String listenHost}) maidCafeExposure(Server server) {
  final terminal = Uri.tryParse(server.maidCafeTerminalUrl?.trim() ?? '');
  final daemon = Uri.tryParse(server.maidCafeDaemonUrl?.trim() ?? '');
  return (
    port:
        server.maidCafeTerminalPort ??
        _maidCafeUrlPort(terminal) ??
        _maidCafeUrlPort(daemon) ??
        maidCafeDefaultPort,
    listenHost:
        _maidCafeUrlHost(daemon) ?? _maidCafeUrlHost(terminal) ?? '127.0.0.1',
  );
}

int? _maidCafeUrlPort(Uri? uri) => uri != null && uri.hasPort ? uri.port : null;

String? _maidCafeUrlHost(Uri? uri) =>
    uri != null && uri.host.isNotEmpty ? uri.host : null;

/// The advice for a route that did not answer.
///
/// Enabling the terminal endpoint comes before exposing a port: a daemon whose
/// terminal is switched off refuses every session no matter what is open in
/// front of it. [exposeHint] is the port advice, used when the terminal is on
/// or unknown.
String maidCafeRouteFailureHint(
  MaidCafeConnectivityReport report,
  String? exposeHint,
) {
  final disabled = report.steps.any(
    (step) =>
        step.titleKey == 'maidCafeCheckTerminalEnabled' &&
        step.status == MaidCafeConnectivityStatus.failed,
  );
  if (disabled) return 'maidCafeCheckTerminalDisabledHint'.tr();
  return exposeHint ?? 'maidCafeCheckReachHint'.tr();
}

/// Shows what the daemon route and the cloud relay answered for a server.
///
/// [directUnreachableHint] replaces the generic advice on a direct route that
/// does not answer, so the user is told which port to expose — unless the
/// daemon's terminal endpoint is off, which is checked first.
Future<void> showMaidCafeConnectivitySheet(
  BuildContext context, {
  required String serverName,
  required Future<MaidCafeConnectivityReport> Function({required bool relay})
  run,
  String? directUnreachableHint,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MaidCafeConnectivitySheet(
      serverName: serverName,
      run: run,
      directUnreachableHint: directUnreachableHint,
    ),
  );
}

class _MaidCafeConnectivitySheet extends StatefulWidget {
  const _MaidCafeConnectivitySheet({
    required this.serverName,
    required this.run,
    this.directUnreachableHint,
  });

  final String serverName;
  final Future<MaidCafeConnectivityReport> Function({required bool relay}) run;

  /// What a failed direct route should tell the user to expose.
  final String? directUnreachableHint;

  @override
  State<_MaidCafeConnectivitySheet> createState() =>
      _MaidCafeConnectivitySheetState();
}

class _MaidCafeConnectivitySheetState
    extends State<_MaidCafeConnectivitySheet> {
  List<MaidCafeConnectivityReport>? _reports;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    setState(() => _running = true);
    final results = await Future.wait([
      widget.run(relay: false),
      widget.run(relay: true),
    ]);
    if (!mounted) return;
    setState(() {
      _reports = results;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = _reports;
    final allOk =
        reports != null &&
        reports.any((report) => report.ok) &&
        reports.every((report) => !report.failed);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('maidCafeCheckTitle'.tr(), style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              widget.serverName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (allOk)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _StatusLine(
                    status: MaidCafeConnectivityStatus.ok,
                    title: Text('maidCafeCheckAllOk'.tr()),
                  ),
                ),
              for (final report in reports ?? const [])
                _ReportSection(
                  report: report,
                  unreachableHint: widget.directUnreachableHint,
                ),
            ],
            const SizedBox(height: 8),
            // The report is the readable half of a failure; the console line
            // the check writes is the other. Release builds start silent, so
            // the switch that turns it on lives where a failure is read.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: maidCafeVerboseLogging,
              title: Text('maidCafeCheckVerboseLogging'.tr()),
              subtitle: Text('maidCafeCheckVerboseLoggingHint'.tr()),
              onChanged: (value) =>
                  setState(() => maidCafeVerboseLogging = value),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _running ? null : () => unawaited(_check()),
                  child: Text('maidCafeCheckRunAgain'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text('commonClose'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.report, this.unreachableHint});

  final MaidCafeConnectivityReport report;

  /// The port advice for a failed direct route, when the terminal is enabled.
  final String? unreachableHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (report.relay
                    ? 'maidCafeCheckRelaySection'
                    : 'maidCafeCheckDaemonSection')
                .tr(),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          for (final step in report.steps)
            _StepLine(
              step: step,
              failureHint: maidCafeRouteFailureHint(
                report,
                report.relay ? null : unreachableHint,
              ),
            ),
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.step, this.failureHint});

  final MaidCafeConnectivityStep step;

  /// Shown when this step is what a route failed on.
  final String? failureHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = step.detailKey?.tr() ?? step.detail;
    final hint = switch (step.status) {
      MaidCafeConnectivityStatus.failed =>
        step.titleKey == 'maidCafeCheckTerminal'
            ? 'maidCafeCheckTerminalHint'.tr()
            : failureHint,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusLine(
            status: step.status,
            title: Text(step.titleKey.tr(), style: theme.textTheme.bodyMedium),
          ),
          // The detail wraps on its own line: a long endpoint or a transport
          // message must never widen the sheet.
          if (detail != null && detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(
                detail,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.title});

  final MaidCafeConnectivityStatus status;
  final Widget title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      MaidCafeConnectivityStatus.ok => (Symbols.check_circle, scheme.primary),
      MaidCafeConnectivityStatus.failed => (Symbols.error, scheme.error),
      MaidCafeConnectivityStatus.skipped => (
        Symbols.do_not_disturb_on,
        scheme.onSurfaceVariant,
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(child: title),
      ],
    );
  }
}
