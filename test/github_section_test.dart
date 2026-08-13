import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/github/github_models.dart';
import 'package:maid_kit/github/github_providers.dart';
import 'package:maid_kit/github/github_section.dart';
import 'package:maid_kit/github/github_token_store.dart';
import 'package:maid_kit/github/github_workflow_strip.dart';

class _AwaitingUserNotifier extends GitHubSignInNotifier {
  @override
  GitHubSignInState build() => const GitHubSignInState(
    phase: GitHubSignInPhase.awaitingUser,
    userCode: 'ABCD-EFGH',
    verificationUri: 'https://github.com/login/device',
  );
}

class _StartingNotifier extends GitHubSignInNotifier {
  @override
  GitHubSignInState build() =>
      const GitHubSignInState(phase: GitHubSignInPhase.starting);
}

/// Renders [GitHubSection] with every data source overridden, so the widget
/// test never touches the database (drift's isolate executor deadlocks inside
/// `testWidgets`' FakeAsync zone).
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return Directory.systemTemp.path;
        });
  });

  GitHubRunsSnapshot snapshotWithFailures() => GitHubRunsSnapshot(
    repos: [
      PinnedRepoRuns(
        owner: 'octocat',
        name: 'hello',
        runs: [
          WorkflowRun(
            id: 1,
            name: 'CI',
            displayTitle: 'Build',
            headBranch: 'main',
            headSha: 'abc',
            status: WorkflowRunStatus.completed,
            conclusion: WorkflowRunConclusion.failure,
            runNumber: 3,
            actorLogin: 'octocat',
          ),
        ],
      ),
    ],
    fetchedAt: DateTime.now(),
    errors: const [],
  );

  testWidgets(
    'workflow strip renders one pill per workflow and hides when empty',
    (WidgetTester tester) async {
      WorkflowRun run(
        int id,
        String workflow,
        WorkflowRunConclusion conclusion,
      ) => WorkflowRun(
        id: id,
        name: workflow,
        displayTitle: 'Build $id',
        headBranch: 'main',
        headSha: 'x',
        status: WorkflowRunStatus.completed,
        conclusion: conclusion,
        runNumber: id,
        actorLogin: 'octocat',
      );
      final snapshot = GitHubRunsSnapshot(
        repos: [
          PinnedRepoRuns(
            owner: 'octocat',
            name: 'hello',
            runs: [
              run(2, 'CI', WorkflowRunConclusion.success),
              run(3, 'Deploy', WorkflowRunConclusion.failure),
            ],
          ),
        ],
        fetchedAt: DateTime.now(),
        errors: const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            githubRunsProvider.overrideWith((ref) => Stream.value(snapshot)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: GithubWorkflowStatusStrip()),
          ),
        ),
      );
      await tester.pump();
      // One row per repo: only the newest run (Deploy) is shown.
      expect(find.text('Deploy'), findsOneWidget);
      expect(find.text('CI'), findsNothing);
      expect(find.text('octocat/hello · main'), findsOneWidget);
      expect(find.text('Build 3'), findsOneWidget);
      expect(find.text('Build 2'), findsNothing);
      // The failing count covers every failing run in the snapshot.
      expect(find.text('githubStatusFailing'.tr(args: ['1'])), findsOneWidget);

      // An empty snapshot hides the strip entirely. A distinct key forces a
      // new ProviderScope state so the overrides are re-applied.
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            githubRunsProvider.overrideWith(
              (ref) => Stream.value(
                GitHubRunsSnapshot(
                  repos: const [],
                  fetchedAt: DateTime(2020),
                  errors: const [],
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: GithubWorkflowStatusStrip()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CI'), findsNothing);
    },
  );

  testWidgets('device code card is selectable and has a copy button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            githubTokenStoreProvider.overrideWithValue(
              InMemoryGitHubTokenStorage(),
            ),
            githubConnectionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            githubSignInProvider.overrideWith(_AwaitingUserNotifier.new),
          ],
          child: MaterialApp(
            locale: Locale('en', 'US'),
            home: Scaffold(body: ListView(children: const [GitHubSection()])),
          ),
        ),
      ),
    );
    // The waiting spinner animates indefinitely, so bounded pumps instead of
    // pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    // The copy action must not throw on the mocked clipboard channel.
    await tester.tap(find.byTooltip('commonCopy'.tr()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('add repository button is visible with no pinned repos', (
    WidgetTester tester,
  ) async {
    final connection = GitHubConnection(
      id: 1,
      accountLogin: 'octocat',
      accountName: 'Octo Cat',
      avatarUrl: '',
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            githubTokenStoreProvider.overrideWithValue(
              InMemoryGitHubTokenStorage(),
            ),
            githubConnectionsProvider.overrideWith(
              (ref) => Stream.value([connection]),
            ),
            githubTokenForConnectionProvider.overrideWith(
              (ref) async => (connection: connection, token: 'secret'),
            ),
            githubPinnedReposProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            githubRunsProvider.overrideWith(
              (ref) => Stream.value(
                GitHubRunsSnapshot(
                  repos: const [],
                  fetchedAt: DateTime.now(),
                  errors: const [],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            locale: Locale('en', 'US'),
            home: Scaffold(body: ListView(children: const [GitHubSection()])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('githubNoPinnedRepos'.tr()), findsWidgets);
    expect(find.text('githubAddRepo'.tr()), findsOneWidget);
  });

  testWidgets('renders the sign-in card when no account is connected', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            githubTokenStoreProvider.overrideWithValue(
              InMemoryGitHubTokenStorage(),
            ),
            githubConnectionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
          child: MaterialApp(
            locale: Locale('en', 'US'),
            home: Scaffold(body: ListView(children: const [GitHubSection()])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('githubSignInTitle'.tr()), findsOneWidget);
    expect(find.text('githubSignIn'.tr()), findsOneWidget);
    expect(find.text('githubTokenLocalHint'.tr()), findsOneWidget);
  });

  testWidgets('shows a disabled sign-in button with a spinner while starting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            githubTokenStoreProvider.overrideWithValue(
              InMemoryGitHubTokenStorage(),
            ),
            githubConnectionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            githubSignInProvider.overrideWith(_StartingNotifier.new),
          ],
          child: MaterialApp(
            locale: Locale('en', 'US'),
            home: Scaffold(body: ListView(children: const [GitHubSection()])),
          ),
        ),
      ),
    );
    // The spinner animates indefinitely, so bounded pumps instead of
    // pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('githubSignIn'.tr()),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the runs feed and failure banner when signed in', (
    WidgetTester tester,
  ) async {
    final connection = GitHubConnection(
      id: 1,
      accountLogin: 'octocat',
      accountName: 'Octo Cat',
      avatarUrl: '',
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            githubTokenStoreProvider.overrideWithValue(
              InMemoryGitHubTokenStorage(),
            ),
            githubConnectionsProvider.overrideWith(
              (ref) => Stream.value([connection]),
            ),
            githubTokenForConnectionProvider.overrideWith(
              (ref) async => (connection: connection, token: 'secret'),
            ),
            githubPinnedReposProvider.overrideWith(
              (ref) => Stream.value([
                GitHubRepoPin(
                  id: 1,
                  connectionId: 1,
                  owner: 'octocat',
                  name: 'hello',
                  pinnedAt: DateTime.now(),
                ),
              ]),
            ),
            githubRunsProvider.overrideWith(
              (ref) => Stream.value(snapshotWithFailures()),
            ),
          ],
          child: MaterialApp(
            locale: Locale('en', 'US'),
            home: Scaffold(body: ListView(children: const [GitHubSection()])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('octocat'), findsOneWidget);
    expect(find.text('githubRuns'.tr()), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('githubConclusionFailure'.tr()), findsOneWidget);
    expect(find.text('githubAddRepo'.tr()), findsOneWidget);
  });
}
