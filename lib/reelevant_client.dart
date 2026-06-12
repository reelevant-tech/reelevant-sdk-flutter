import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const String defaultRunnerUrl = 'https://reelevant.run';
const Duration defaultTimeout = Duration(seconds: 5);
const String _sdkVersion = 'flutter-0.1.0';

// ---------------------------------------------------------------------------
// Fallback strategies
// ---------------------------------------------------------------------------

/// Controls what happens when a runner call fails or times out.
enum FallbackStrategy {
  /// Return an empty result (default). Your UI renders its default state.
  empty,

  /// Re-throw the underlying error.
  error,
}

/// Signature for custom fallback handlers.
typedef FallbackHandler = Future<RunResult> Function(
    RunOptions options, Object error);

// ---------------------------------------------------------------------------
// Run options
// ---------------------------------------------------------------------------

/// Options for a single workflow run.
class RunOptions {
  final String workflowId;
  final String entrypoint;

  /// Override user identity. `null` = auto-resolve from stored identity.
  final String? userId;

  /// URL parameters forwarded to the runner.
  final Map<String, String>? params;

  /// Locale for content resolution.
  final String? locale;

  /// Per-call timeout override.
  final Duration? timeout;

  RunOptions({
    required this.workflowId,
    required this.entrypoint,
    this.userId,
    this.params,
    this.locale,
    this.timeout,
  });
}

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

/// Base class for discriminated content returned by the runner.
abstract class RunContent {
  String get type;
}

/// HTML string content.
class HtmlRunContent extends RunContent {
  final String content;
  @override
  String get type => 'html';
  HtmlRunContent(this.content);
}

/// Parsed JSON object content.
class JsonRunContent extends RunContent {
  final Map<String, dynamic> content;
  @override
  String get type => 'json';
  JsonRunContent(this.content);
}

/// Raw image bytes.
class ImageRunContent extends RunContent {
  final Uint8List content;
  @override
  String get type => 'image';
  ImageRunContent(this.content);
}

/// No content returned.
class EmptyRunContent extends RunContent {
  @override
  String get type => 'empty';
}

/// Where the result came from.
enum RunSource { runner, fallback }

/// Typed result returned by `run()`.
class RunResult {
  /// HTTP status code from the runner response (0 for fallback/timeout).
  final int status;
  final RunSource source;

  /// Typed content — check `body.type` or use `is` to handle each variant.
  final RunContent body;

  /// Metadata from x-rlvt-output-node-metadata header.
  final Map<String, dynamic> metadata;

  /// Properties from x-rlvt-output-properties header.
  final Map<String, dynamic> properties;

  /// Workflow run ID for tracking correlation.
  final String? runId;

  /// Execution path (branch IDs).
  final List<String> executionPath;

  /// Pre-built click-through URL (runner with mode=click).
  final String redirectionUrl;

  final Future<void> Function() _trackClick;

  RunResult({
    required this.status,
    required this.source,
    required this.body,
    required this.metadata,
    required this.properties,
    this.runId,
    required this.executionPath,
    required this.redirectionUrl,
    Future<void> Function()? trackClick,
  }) : _trackClick = trackClick ?? (() async {});

  /// Fire-and-forget click tracking. Calls the runner click endpoint without following redirects.
  Future<void> trackClick() => _trackClick();
}

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

class ReelevantError implements Exception {
  final String message;
  ReelevantError(this.message);
  @override
  String toString() => 'ReelevantError: $message';
}

class TimeoutError extends ReelevantError {
  final Duration timeoutDuration;
  TimeoutError(this.timeoutDuration)
      : super(
            'Runner call timed out after ${timeoutDuration.inMilliseconds}ms');
}

class RunnerError extends ReelevantError {
  final int statusCode;
  final String body;
  RunnerError(this.statusCode, this.body)
      : super('Runner returned HTTP $statusCode');
}

// ---------------------------------------------------------------------------
// Internal runner helpers
// ---------------------------------------------------------------------------

Future<RunResult> executeRunnerCall({
  required RunOptions options,
  required String runnerUrl,
  required Duration timeout,
  required String userId,
  required http.Client client,
}) async {
  final effectiveTimeout = options.timeout ?? timeout;
  final url = _buildRunnerUrl(runnerUrl, options, userId);
  final redirectionUrl = _buildRedirectionUrl(runnerUrl, options, userId);

  final response = await client
      .get(
        url,
        headers: {'x-rlvt-sdk-version': _sdkVersion},
      )
      .timeout(effectiveTimeout);

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw RunnerError(response.statusCode, response.body);
  }

  final contentType = response.headers['content-type'] ?? '';
  final runId = response.headers['x-rlvt-workflow-run-id'];
  final executionPathHeader = response.headers['x-rlvt-execution-path'];
  final metadataHeader = response.headers['x-rlvt-output-node-metadata'];
  final propertiesHeader = response.headers['x-rlvt-output-properties'];

  final executionPath =
      executionPathHeader?.split(',') ?? <String>[];
  final metadata =
      metadataHeader != null ? _safeJsonParse(metadataHeader) : <String, dynamic>{};
  final properties =
      propertiesHeader != null ? _safeJsonParse(propertiesHeader) : <String, dynamic>{};
  final body = _parseResponseBody(response, contentType);

  return RunResult(
    status: response.statusCode,
    source: RunSource.runner,
    body: body,
    metadata: metadata,
    properties: properties,
    runId: runId,
    executionPath: executionPath,
    redirectionUrl: redirectionUrl.toString(),
    trackClick: () => _fireAndForgetClick(redirectionUrl.toString(), effectiveTimeout, client),
  );
}

Future<void> _fireAndForgetClick(
    String url, Duration timeout, http.Client client) async {
  try {
    await client
        .get(
          Uri.parse(url),
          headers: {'x-rlvt-sdk-version': _sdkVersion},
        )
        .timeout(timeout);
  } catch (_) {
    // Fire-and-forget — swallow all errors
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

Uri _buildRunnerUrl(
    String runnerUrl, RunOptions options, String userId) {
  final params = <String, String>{
    'rlvt-u': userId,
  };
  if (options.locale != null) params['locale'] = options.locale!;
  if (options.params != null) {
    final userParams = Map<String, String>.from(options.params!);
    userParams.remove('rlvt-u');
    params.addAll(userParams);
  }
  return Uri.parse('$runnerUrl/${options.workflowId}/${options.entrypoint}')
      .replace(queryParameters: params);
}

Uri _buildRedirectionUrl(
    String runnerUrl, RunOptions options, String userId) {
  return Uri.parse('$runnerUrl/${options.workflowId}/${options.entrypoint}')
      .replace(queryParameters: {'rlvt-u': userId, 'mode': 'click'});
}

RunContent _parseResponseBody(http.Response response, String contentType) {
  if (contentType.contains('text/html')) {
    return response.body.trim().isEmpty
        ? EmptyRunContent()
        : HtmlRunContent(response.body);
  }

  if (contentType.contains('image/')) {
    return response.bodyBytes.isEmpty
        ? EmptyRunContent()
        : ImageRunContent(response.bodyBytes);
  }

  if (contentType.contains('application/json')) {
    return _parseJsonBody(response.body);
  }

  // Unknown content-type: try JSON, fall back to HTML
  if (response.body.trim().isEmpty) return EmptyRunContent();
  try {
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) return JsonRunContent(data);
    return HtmlRunContent(response.body);
  } catch (_) {
    return HtmlRunContent(response.body);
  }
}

RunContent _parseJsonBody(String body) {
  if (body.trim().isEmpty) return EmptyRunContent();
  try {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) return JsonRunContent(data);
    return EmptyRunContent();
  } catch (_) {
    return EmptyRunContent();
  }
}

Map<String, dynamic> _safeJsonParse(String str) {
  try {
    final data = jsonDecode(str);
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}
