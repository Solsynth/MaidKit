import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';

import 'github_api.dart';
import 'github_device_auth.dart';
import 'github_models.dart';
import 'github_repository.dart';
import 'github_token_store.dart';

final githubTokenStoreProvider = Provider<GitHubTokenStorage>((ref) {
  return VaultGitHubTokenStorage(
    ref.watch(databaseProvider),
    ref.watch(vaultServiceProvider),
  );
});

final githubRepositoryProvider = Provider<GitHubRepository>((ref) {
  return GitHubRepository(
    ref.watch(databaseProvider),
    ref.watch(githubTokenStoreProvider),
  );
});

final githubConnectionsProvider = StreamProvider<List<GitHubConnection>>((ref) {
  return ref.watch(githubRepositoryProvider).watchConnections();
});

/// The account this device is signed in with (the first stored connection).
final githubActiveConnectionProvider = Provider<GitHubConnection?>((ref) {
  final connections = ref.watch(githubConnectionsProvider).asData?.value;
  if (connections == null || connections.isEmpty) return null;
  return connections.first;
});

/// The active connection paired with its vault-stored token, or null while
/// signed out or when no token is stored (e.g. a connection imported from a
/// backup written before tokens were vault-backed).
final githubTokenForConnectionProvider =
    FutureProvider<({GitHubConnection connection, String token})?>((ref) async {
      final connection = ref.watch(githubActiveConnectionProvider);
      if (connection == null) return null;
      final token = await ref
          .watch(githubRepositoryProvider)
          .tokenFor(connection.accountLogin);
      if (token == null || token.isEmpty) return null;
      return (connection: connection, token: token);
    });

final githubApiProvider = Provider<GithubApi?>((ref) {
  final cwt = ref.watch(githubTokenForConnectionProvider).asData?.value;
  return cwt == null ? null : GithubApi(token: cwt.token);
});

final githubPinnedReposProvider = StreamProvider<List<GitHubRepoPin>>((ref) {
  final connection = ref.watch(githubActiveConnectionProvider);
  if (connection == null) return Stream.value(const []);
  return ref
      .watch(githubRepositoryProvider)
      .watchRepoPins()
      .map(
        (pins) =>
            pins.where((pin) => pin.connectionId == connection.id).toList(),
      );
});

/// Bumping this counter refetches the GitHub feeds (manual refresh, tab
/// focus, project detail changes).
final githubRefreshTickProvider =
    NotifierProvider<GitHubRefreshTickNotifier, int>(
      GitHubRefreshTickNotifier.new,
    );

class GitHubRefreshTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;
}

enum GitHubSignInPhase { idle, starting, awaitingUser, signedIn, failed }

class GitHubSignInState {
  const GitHubSignInState({
    this.phase = GitHubSignInPhase.idle,
    this.userCode,
    this.verificationUri,
    this.error,
  });

  final GitHubSignInPhase phase;
  final String? userCode;
  final String? verificationUri;
  final String? error;
}

final githubSignInProvider =
    NotifierProvider<GitHubSignInNotifier, GitHubSignInState>(
      GitHubSignInNotifier.new,
    );

/// Drives the OAuth device flow: requests a device code, opens the
/// verification page through the UI, and polls until the user authorizes.
class GitHubSignInNotifier extends Notifier<GitHubSignInState> {
  Timer? _pollTimer;
  int _pollInterval = 5;
  bool _cancelled = true;
  bool _polling = false;
  bool _requesting = false;

  @override
  GitHubSignInState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return const GitHubSignInState();
  }

  Future<void> start() async {
    // One flow at a time: a second start while the previous request or poll
    // is still in flight would spawn a duplicate device code and race the
    // timers.
    if (_requesting || _polling) return;
    final clientId = GithubDeviceAuth.configuredClientId;
    if (clientId.isEmpty) {
      state = const GitHubSignInState(
        phase: GitHubSignInPhase.failed,
        error:
            'GITHUB_CLIENT_ID is not configured. Build with '
            '--dart-define=GITHUB_CLIENT_ID=<your OAuth App client id>.',
      );
      return;
    }
    _requesting = true;
    _cancelled = false;
    _polling = false;
    _pollTimer?.cancel();
    // Surface the in-flight request as a loading state so the UI can show a
    // spinner and keep the button disabled; also clears any previous error.
    state = const GitHubSignInState(phase: GitHubSignInPhase.starting);
    final auth = GithubDeviceAuth(clientId: clientId);
    try {
      final code = await auth.requestDeviceCode();
      state = GitHubSignInState(
        phase: GitHubSignInPhase.awaitingUser,
        userCode: code.userCode,
        verificationUri: code.verificationUriComplete ?? code.verificationUri,
      );
      _pollTimer?.cancel();
      _pollInterval = code.interval;
      _pollTimer = Timer.periodic(
        Duration(seconds: code.interval),
        (_) => _poll(auth, code),
      );
    } catch (error) {
      state = GitHubSignInState(
        phase: GitHubSignInPhase.failed,
        error: error.toString(),
      );
    } finally {
      _requesting = false;
    }
  }

  Future<void> _poll(GithubDeviceAuth auth, GitHubDeviceCode code) async {
    if (_cancelled || _polling) return;
    _polling = true;
    try {
      final result = await auth.pollAccessToken(code);
      final token = result.token;
      if (token == null) {
        // GitHub answers `slow_down` with an escalated interval when we poll
        // too fast. Ignore it and GitHub never hands over the token, even
        // after the user authorizes — reschedule with the demanded interval.
        final interval = result.interval;
        if (interval != null && interval > _pollInterval) {
          _pollTimer?.cancel();
          _pollInterval = interval;
          _pollTimer = Timer.periodic(
            Duration(seconds: interval),
            (_) => _poll(auth, code),
          );
        }
        return;
      }
      Logger.root.info('[GitHub] Device flow authorized; fetching account.');
      _pollTimer?.cancel();
      final account = await GithubApi(token: token).currentUser();
      final repository = ref.read(githubRepositoryProvider);
      // Token first: a tokenless connection (if the insert fails) renders as
      // signed-out, while a failed token write still leaves a usable flow.
      await repository.saveToken(account.login, token);
      await repository.saveConnection(account);
      Logger.root.info('[GitHub] Signed in as ${account.login}.');
      state = const GitHubSignInState(phase: GitHubSignInPhase.signedIn);
    } on DeviceFlowException catch (error) {
      _pollTimer?.cancel();
      state = GitHubSignInState(
        phase: GitHubSignInPhase.failed,
        error: error.message,
      );
    } on GitHubApiException catch (error) {
      _pollTimer?.cancel();
      state = GitHubSignInState(
        phase: GitHubSignInPhase.failed,
        error: error.message,
      );
    } catch (error, stackTrace) {
      // Storage or database failures after authorization must surface, not
      // leave the UI waiting forever.
      Logger.root.severe(
        '[GitHub] Sign-in failed after authorization: $error\n$stackTrace',
      );
      _pollTimer?.cancel();
      state = GitHubSignInState(
        phase: GitHubSignInPhase.failed,
        error: 'GitHub sign-in failed: $error',
      );
    } finally {
      _polling = false;
    }
  }

  void cancel() {
    _cancelled = true;
    _polling = false;
    _requesting = false;
    _pollTimer?.cancel();
    state = const GitHubSignInState();
  }

  Future<void> signOut() async {
    final connection = ref.read(githubActiveConnectionProvider);
    if (connection == null) return;
    final repository = ref.read(githubRepositoryProvider);
    await repository.removeToken(connection.accountLogin);
    await repository.removeConnection(connection);
  }
}

/// Polls the runs feed while any pinned run is live. The stream re-emits on
/// every successful fetch; a manual refresh recreates the provider through
/// [githubRefreshTickProvider].
class GitHubRunsPoller {
  GitHubRunsPoller(this._fetch) {
    Future.microtask(refresh);
  }

  final Future<GitHubRunsSnapshot> Function() _fetch;
  final StreamController<GitHubRunsSnapshot> _controller =
      StreamController<GitHubRunsSnapshot>.broadcast();
  Timer? _timer;
  GitHubRunsSnapshot? _last;
  bool _disposed = false;

  Stream<GitHubRunsSnapshot> get stream => _controller.stream;

  Future<void> refresh() async {
    if (_disposed) return;
    try {
      final next = await _fetch();
      _last = next;
      if (!_controller.isClosed) _controller.add(next);
    } catch (_) {
      // Fetch failures surface per-repo in the snapshot; keep the last state.
    } finally {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_last?.hasLiveRuns ?? false) {
      _timer = Timer(const Duration(seconds: 15), refresh);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _controller.close();
  }
}

Future<GitHubRunsSnapshot> _fetchRuns(
  ({GitHubConnection connection, String token})? cwt,
  List<GitHubRepoPin> pins,
) async {
  if (cwt == null || pins.isEmpty) {
    return GitHubRunsSnapshot(
      repos: const [],
      fetchedAt: DateTime.now(),
      errors: const [],
    );
  }
  final api = GithubApi(token: cwt.token);
  final errors = <String>[];
  final repos = <PinnedRepoRuns>[];
  for (final pin in pins) {
    try {
      final runs = await api.listRuns(pin.owner, pin.name);
      repos.add(
        PinnedRepoRuns(
          owner: pin.owner,
          name: pin.name,
          runs: latestRunPerWorkflow(runs),
        ),
      );
    } on GitHubApiException catch (error) {
      errors.add('${pin.owner}/${pin.name}: ${error.message}');
    }
  }
  return GitHubRunsSnapshot(
    repos: repos,
    fetchedAt: DateTime.now(),
    errors: errors,
  );
}

final githubRunsProvider = StreamProvider<GitHubRunsSnapshot>((ref) {
  ref.watch(githubRefreshTickProvider);
  final cwt = ref.watch(githubTokenForConnectionProvider).asData?.value;
  final pins =
      ref.watch(githubPinnedReposProvider).asData?.value ??
      const <GitHubRepoPin>[];
  final poller = GitHubRunsPoller(() => _fetchRuns(cwt, pins));
  ref.onDispose(poller.dispose);
  return poller.stream;
});

/// True while any pinned repository has a failed, timed-out, cancelled, or
/// action-required run — drives the rail badge and failure banner.
final githubHasFailuresProvider = Provider<bool>((ref) {
  final snapshot = ref.watch(githubRunsProvider).asData?.value;
  return snapshot?.hasFailures ?? false;
});

/// Repositories available for pinning, newest-updated first.
final githubAvailableReposProvider = FutureProvider<List<GitHubRepo>>((ref) {
  final cwt = ref.watch(githubTokenForConnectionProvider).asData?.value;
  if (cwt == null) return Future.value(const []);
  return GithubApi(token: cwt.token).listRepos();
});

final githubWorkflowsProvider =
    FutureProvider.family<List<GitHubWorkflow>, GitHubRepoRef>((
      ref,
      repo,
    ) async {
      final cwt = ref.watch(githubTokenForConnectionProvider).asData?.value;
      if (cwt == null) return const [];
      try {
        return await GithubApi(
          token: cwt.token,
        ).listWorkflows(repo.owner, repo.name);
      } on GitHubApiException {
        return const [];
      }
    });

/// The latest run of a linked deployment workflow (a `githubWorkflow`
/// deployment resource's configuration).
final githubLinkedRunProvider =
    FutureProvider.family<
      WorkflowRun?,
      ({String owner, String name, String workflowName})
    >((ref, key) async {
      ref.watch(githubRefreshTickProvider);
      final cwt = ref.watch(githubTokenForConnectionProvider).asData?.value;
      if (cwt == null) return null;
      try {
        return await GithubApi(
          token: cwt.token,
        ).latestRunForWorkflow(key.owner, key.name, key.workflowName);
      } on GitHubApiException {
        return null;
      }
    });

final githubRunJobsProvider =
    FutureProvider.family<
      List<RunJob>,
      ({String owner, String name, int runId})
    >((ref, key) async {
      final cwt = ref.watch(githubTokenForConnectionProvider).asData?.value;
      if (cwt == null) return const [];
      try {
        return await GithubApi(
          token: cwt.token,
        ).listJobs(key.owner, key.name, key.runId);
      } on GitHubApiException {
        return const [];
      }
    });
