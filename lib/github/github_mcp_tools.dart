import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'github_api.dart';
import 'github_providers.dart';

/// Read-only GitHub tools served to agents through the local MCP server.
///
/// All tools go through the same approval flow as other read-only MCP tools:
/// they are safe to auto-review because they only read GitHub state. They
/// require a signed-in GitHub account on this device.
class GitHubMcpToolHandlers {
  GitHubMcpToolHandlers(this.ref);

  final Ref ref;

  /// Whether [name] is one of this handler's GitHub tools. The executor uses
  /// this to hide the GitHub surface from agents when no account is signed in.
  static bool isGitHubTool(String name) => name.startsWith('github_');

  static const definitions = <Map<String, dynamic>>[
    {
      'name': 'github_list_runs',
      'description':
          'List the latest workflow runs of a GitHub repository. Returns id, '
          'name, branch, status, and conclusion for each run.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'owner': {
            'type': 'string',
            'description': 'Repository owner (user or organization).',
          },
          'name': {'type': 'string', 'description': 'Repository name.'},
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of runs to return (default 10).',
          },
        },
        'required': ['owner', 'name'],
      },
    },
    {
      'name': 'github_get_run',
      'description':
          'Get one workflow run with its jobs and steps. Returns run id, '
          'status, conclusion, and per-job step results.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'owner': {
            'type': 'string',
            'description': 'Repository owner (user or organization).',
          },
          'name': {'type': 'string', 'description': 'Repository name.'},
          'run_id': {'type': 'integer', 'description': 'Id of the run.'},
        },
        'required': ['owner', 'name', 'run_id'],
      },
    },
    {
      'name': 'github_list_jobs',
      'description': 'List the jobs of a workflow run.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'owner': {
            'type': 'string',
            'description': 'Repository owner (user or organization).',
          },
          'name': {'type': 'string', 'description': 'Repository name.'},
          'run_id': {'type': 'integer', 'description': 'Id of the run.'},
        },
        'required': ['owner', 'name', 'run_id'],
      },
    },
  ];

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final api = await _api();
    return switch (name) {
      'github_list_runs' => _runs(
        api,
        _string(arguments, 'owner'),
        _string(arguments, 'name'),
        _int(arguments, 'limit', fallback: 10),
      ),
      'github_get_run' => _run(
        api,
        _string(arguments, 'owner'),
        _string(arguments, 'name'),
        _int(arguments, 'run_id'),
      ),
      'github_list_jobs' => _jobs(
        api,
        _string(arguments, 'owner'),
        _string(arguments, 'name'),
        _int(arguments, 'run_id'),
      ),
      _ => throw ArgumentError('Unknown tool: $name'),
    };
  }

  Future<GithubApi> _api() async {
    final cwt = await ref.read(githubTokenForConnectionProvider.future);
    if (cwt == null) {
      throw ArgumentError(
        'No GitHub account is signed in. Sign in on the GitHub tab first.',
      );
    }
    return GithubApi(token: cwt.token);
  }

  Future<Map<String, dynamic>> _runs(
    GithubApi api,
    String owner,
    String name,
    int limit,
  ) async {
    final runs = await api.listRuns(owner, name);
    return {
      'repository': '$owner/$name',
      'runs': [
        for (final run in runs.take(limit))
          {
            'id': run.id,
            'run_number': run.runNumber,
            'workflow': run.name,
            'title': run.displayTitle,
            'branch': run.headBranch,
            'status': run.status.name,
            'conclusion': run.conclusion?.name,
            'actor': run.actorLogin,
            'html_url': run.htmlUrl,
          },
      ],
    };
  }

  Future<Map<String, dynamic>> _run(
    GithubApi api,
    String owner,
    String name,
    int runId,
  ) async {
    final runs = await api.listRuns(owner, name);
    final run = runs.where((item) => item.id == runId).firstOrNull;
    if (run == null) {
      throw ArgumentError('Run $runId not found in $owner/$name.');
    }
    final jobs = await api.listJobs(owner, name, runId);
    return {
      'id': run.id,
      'run_number': run.runNumber,
      'workflow': run.name,
      'title': run.displayTitle,
      'branch': run.headBranch,
      'status': run.status.name,
      'conclusion': run.conclusion?.name,
      'actor': run.actorLogin,
      'html_url': run.htmlUrl,
      'jobs': [
        for (final job in jobs)
          {
            'name': job.name,
            'status': job.status.name,
            'conclusion': job.conclusion?.name,
            'steps': [
              for (final step in job.steps)
                {
                  'name': step.name,
                  'status': step.status.name,
                  'conclusion': step.conclusion?.name,
                },
            ],
          },
      ],
    };
  }

  Future<Map<String, dynamic>> _jobs(
    GithubApi api,
    String owner,
    String name,
    int runId,
  ) async {
    final jobs = await api.listJobs(owner, name, runId);
    return {
      'run_id': runId,
      'jobs': [
        for (final job in jobs)
          {
            'id': job.id,
            'name': job.name,
            'status': job.status.name,
            'conclusion': job.conclusion?.name,
            'steps': [
              for (final step in job.steps)
                {
                  'name': step.name,
                  'status': step.status.name,
                  'conclusion': step.conclusion?.name,
                },
            ],
          },
      ],
    };
  }

  static String _string(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError('$key is required.');
    }
    return value.trim();
  }

  static int _int(Map<String, dynamic> arguments, String key, {int? fallback}) {
    final value = arguments[key];
    if (value == null && fallback != null) return fallback;
    if (value is! num) throw ArgumentError('$key must be an integer.');
    return value.toInt();
  }
}
