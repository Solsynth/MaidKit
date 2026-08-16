/// Data models for the GitHub integration tab.
library;

/// A GitHub account the user signed in with. Identity only: the access token
/// is stored encrypted in the vault and never appears in these models.
class GitHubAccount {
  const GitHubAccount({
    required this.login,
    required this.name,
    required this.avatarUrl,
  });

  final String login;
  final String name;
  final String avatarUrl;

  factory GitHubAccount.fromJson(Map<String, dynamic> json) => GitHubAccount(
    login: json['login'] as String? ?? '',
    name: json['name'] as String? ?? json['login'] as String? ?? '',
    avatarUrl: json['avatar_url'] as String? ?? '',
  );
}

/// A repository the user can pin to the GitHub tab.
class GitHubRepo {
  const GitHubRepo({
    required this.owner,
    required this.name,
    required this.fullName,
    this.description,
    this.private = false,
    this.defaultBranch,
  });

  final String owner;
  final String name;
  final String fullName;
  final String? description;
  final bool private;
  final String? defaultBranch;

  String get slug => '$owner/$name';

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    final fullName = json['full_name'] as String? ?? '';
    final parts = fullName.split('/');
    final owner = parts.length == 2
        ? parts[0]
        : (json['owner'] as Map?)?.letMap()['login'] ?? '';
    return GitHubRepo(
      owner: owner,
      name: json['name'] as String? ?? '',
      fullName: fullName.isEmpty ? owner : fullName,
      description: json['description'] as String?,
      private: json['private'] == true,
      defaultBranch: json['default_branch'] as String?,
    );
  }
}

/// A workflow defined in a repository's `.github/workflows`.
class GitHubWorkflow {
  const GitHubWorkflow({required this.name, required this.path});

  final String name;
  final String path;

  factory GitHubWorkflow.fromJson(Map<String, dynamic> json) => GitHubWorkflow(
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
  );
}

enum WorkflowRunStatus { queued, inProgress, completed, unknown }

enum WorkflowRunConclusion {
  success,
  failure,
  cancelled,
  skipped,
  neutral,
  stale,
  timedOut,
  actionRequired,
  unknown,
}

WorkflowRunStatus _runStatus(String? status) => switch (status) {
  'queued' || 'requested' || 'waiting' => WorkflowRunStatus.queued,
  'in_progress' => WorkflowRunStatus.inProgress,
  'completed' => WorkflowRunStatus.completed,
  _ => WorkflowRunStatus.unknown,
};

WorkflowRunConclusion _runConclusion(String? conclusion) =>
    switch (conclusion) {
      'success' => WorkflowRunConclusion.success,
      'failure' => WorkflowRunConclusion.failure,
      'cancelled' => WorkflowRunConclusion.cancelled,
      'skipped' => WorkflowRunConclusion.skipped,
      'neutral' => WorkflowRunConclusion.neutral,
      'stale' => WorkflowRunConclusion.stale,
      'timed_out' => WorkflowRunConclusion.timedOut,
      'action_required' => WorkflowRunConclusion.actionRequired,
      _ => WorkflowRunConclusion.unknown,
    };

/// One workflow run of a repository's Actions.
class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.name,
    required this.displayTitle,
    required this.headBranch,
    required this.headSha,
    required this.status,
    required this.conclusion,
    this.createdAt,
    this.updatedAt,
    this.runNumber = 0,
    this.actorLogin = '',
    this.actorAvatarUrl,
    this.htmlUrl = '',
    this.event = '',
  });

  final int id;
  final String name;
  final String displayTitle;
  final String headBranch;
  final String headSha;
  final WorkflowRunStatus status;
  final WorkflowRunConclusion? conclusion;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int runNumber;
  final String actorLogin;
  final String? actorAvatarUrl;
  final String htmlUrl;
  final String event;

  /// True while the run is queued or executing and should be polled.
  bool get isLive =>
      status == WorkflowRunStatus.queued ||
      status == WorkflowRunStatus.inProgress;

  /// A finished run the user cares about: failed, timed out, cancelled, or
  /// waiting for a required action.
  bool get failed =>
      status == WorkflowRunStatus.completed &&
      switch (conclusion) {
        WorkflowRunConclusion.failure ||
        WorkflowRunConclusion.timedOut ||
        WorkflowRunConclusion.cancelled ||
        WorkflowRunConclusion.actionRequired => true,
        _ => false,
      };

  factory WorkflowRun.fromJson(Map<String, dynamic> json) => WorkflowRun(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    displayTitle: json['display_title'] as String? ?? '',
    headBranch: json['head_branch'] as String? ?? '',
    headSha: json['head_sha'] as String? ?? '',
    status: _runStatus(json['status'] as String?),
    conclusion: json['conclusion'] == null
        ? null
        : _runConclusion(json['conclusion'] as String?),
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    runNumber: (json['run_number'] as num?)?.toInt() ?? 0,
    actorLogin: (json['actor'] as Map?)?.letMap()['login'] as String? ?? '',
    actorAvatarUrl: (json['actor'] as Map?)?.letMap()['avatar_url'] as String?,
    htmlUrl: json['html_url'] as String? ?? '',
    event: json['event'] as String? ?? '',
  );
}

/// One step inside a job of a workflow run.
class RunStep {
  const RunStep({
    required this.number,
    required this.name,
    required this.status,
    this.conclusion,
    this.startedAt,
    this.completedAt,
  });

  final int number;
  final String name;
  final WorkflowRunStatus status;
  final WorkflowRunConclusion? conclusion;
  final DateTime? startedAt;
  final DateTime? completedAt;

  factory RunStep.fromJson(Map<String, dynamic> json) => RunStep(
    number: (json['number'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    status: _runStatus(json['status'] as String?),
    conclusion: json['conclusion'] == null
        ? null
        : _runConclusion(json['conclusion'] as String?),
    startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
    completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
  );
}

/// A job of a workflow run, with its steps.
class RunJob {
  const RunJob({
    required this.id,
    required this.name,
    required this.status,
    this.conclusion,
    this.startedAt,
    this.completedAt,
    this.steps = const [],
  });

  final int id;
  final String name;
  final WorkflowRunStatus status;
  final WorkflowRunConclusion? conclusion;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final List<RunStep> steps;

  factory RunJob.fromJson(Map<String, dynamic> json) => RunJob(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    status: _runStatus(json['status'] as String?),
    conclusion: json['conclusion'] == null
        ? null
        : _runConclusion(json['conclusion'] as String?),
    startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
    completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
    steps: [
      for (final step in (json['steps'] as List?) ?? const [])
        if (step is Map) RunStep.fromJson(Map<String, dynamic>.from(step)),
    ],
  );
}

/// A device-flow authorization issued by GitHub.
class GitHubDeviceCode {
  const GitHubDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String? verificationUriComplete;
  final int expiresIn;
  final int interval;

  factory GitHubDeviceCode.fromJson(Map<String, dynamic> json) =>
      GitHubDeviceCode(
        deviceCode: json['device_code'] as String? ?? '',
        userCode: json['user_code'] as String? ?? '',
        verificationUri: json['verification_uri'] as String? ?? '',
        verificationUriComplete: json['verification_uri_complete'] as String?,
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 900,
        interval: (json['interval'] as num?)?.toInt() ?? 5,
      );
}

/// Owner/name pair identifying a repository.
class GitHubRepoRef {
  const GitHubRepoRef({required this.owner, required this.name});

  final String owner;
  final String name;

  String get slug => '$owner/$name';

  @override
  bool operator ==(Object other) =>
      other is GitHubRepoRef && other.owner == owner && other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);
}

/// The runs fetched for one pinned repository. Collapsed by the feed so the
/// list holds at most the latest run of each workflow.
class PinnedRepoRuns {
  const PinnedRepoRuns({
    required this.owner,
    required this.name,
    required this.runs,
  });

  final String owner;
  final String name;
  final List<WorkflowRun> runs;
}

/// Reduces a run list to the latest run of each workflow, ordered by recency.
/// GitHub run ids increase monotonically, so the largest id is the newest run.
List<WorkflowRun> latestRunPerWorkflow(List<WorkflowRun> runs) {
  final latest = <String, WorkflowRun>{};
  for (final run in runs) {
    final existing = latest[run.name];
    if (existing == null || run.id > existing.id) {
      latest[run.name] = run;
    }
  }
  final result = latest.values.toList()..sort((a, b) => b.id.compareTo(a.id));
  return result;
}

/// A consistent snapshot of every pinned repository's runs.
class GitHubRunsSnapshot {
  const GitHubRunsSnapshot({
    required this.repos,
    required this.fetchedAt,
    required this.errors,
  });

  final List<PinnedRepoRuns> repos;
  final DateTime fetchedAt;

  /// Per-repo fetch failures, rendered as a hint under the runs feed.
  final List<String> errors;

  bool get hasLiveRuns =>
      repos.any((repo) => repo.runs.any((run) => run.isLive));

  bool get hasFailures =>
      repos.any((repo) => repo.runs.any((run) => run.failed));

  List<WorkflowRun> get failingRuns => [
    for (final repo in repos) ...repo.runs.where((run) => run.failed),
  ];
}

extension on Map<dynamic, dynamic> {
  Map<String, dynamic> letMap() => Map<String, dynamic>.from(this);
}
