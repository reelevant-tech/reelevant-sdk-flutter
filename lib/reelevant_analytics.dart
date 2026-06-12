import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'reelevant_analytics_platform_interface.dart';
import 'reelevant_client.dart';

export 'reelevant_client.dart';

/// Event define an analytics events compatible with Reelevant Events datsources.
class Event {
  String name;
  Map<String, dynamic> labels;

  Event({required this.name, required this.labels});
}

/// BuiltEvent define the structure of an event sent to Reelevant datasources API.
class BuiltEvent {
  String key;
  String name;
  String url;
  String tmpId;
  String? clientId;
  Map<String, dynamic> data;
  String eventId;
  int v;
  int timestamp;

  BuiltEvent(
      {required this.key,
      required this.name,
      required this.url,
      required this.tmpId,
      this.clientId,
      required this.data,
      required this.eventId,
      required this.v,
      required this.timestamp});

  /// Convert from JSON to BuiltEvent
  BuiltEvent.fromJson(Map<String, dynamic> json)
      : key = json['key'],
        name = json['name'],
        url = json['url'],
        tmpId = json['tmpId'],
        clientId = json['clientId'],
        data = json['data'],
        eventId = json['eventId'],
        v = json['v'],
        timestamp = json['timestamp'];

  /// Convert from BuiltEvent to JSON
  Map<String, dynamic> toJSON() {
    return {
      'key': key,
      'name': name,
      'url': url,
      'tmpId': tmpId,
      'clientId': clientId,
      'data': data,
      'eventId': eventId,
      'v': v,
      'timestamp': timestamp
    };
  }
}

/// Reelevant analytics sdk instance, used to create and send analytics events to Reelevant datasources.
///
/// ### Example
///
/// ```dart
/// final reelevantAnalytics = ReelevantAnalytics(companyId: '<company id>', datasourceId: '<datasource id>');
/// var event = reelevantAnalytics.pageView(labels: {});
/// reelevantAnalytics.send(event);
/// ```
class ReelevantAnalytics {
  String companyId, datasourceId, endpoint;
  int retry;
  String? currentUrl, userAgent;
  http.Client client = http.Client();

  /// Runner endpoint URL for personalization (default: production runner).
  String runnerUrl;

  /// Global timeout for runner calls (default: 5s).
  Duration runnerTimeout;

  /// Fallback strategy when a runner call fails.
  FallbackStrategy fallback;

  /// Custom fallback handler (used when [fallback] is not `empty` or `error`).
  FallbackHandler? fallbackHandler;

  ReelevantAnalytics(
      {required this.companyId,
      required this.datasourceId,
      this.endpoint = '',
      this.retry = 60,
      this.runnerUrl = defaultRunnerUrl,
      this.runnerTimeout = defaultTimeout,
      this.fallback = FallbackStrategy.empty,
      this.fallbackHandler}) {
    if (endpoint == '') {
      endpoint = 'https://collector.reelevant.com/collect/$datasourceId/rlvt';
    }

    () async {
      final prefs = await SharedPreferences.getInstance();

      // Set tmpId
      if (prefs.getString('tmpId') == null) {
        var deviceId = await ReelevantAnalyticsPlatform.instance.getDeviceId();
        prefs.setString('tmpId', deviceId ?? _randomIdentifier());
      }

      // Set user agent
      userAgent = await ReelevantAnalyticsPlatform.instance.getUserAgent();

      // Fail queue
      var queueStream = Stream.periodic(Duration(seconds: retry));
      queueStream.forEach((_) async {
        var failedEvents = await _getFailedEvents();
        if (failedEvents.isNotEmpty) {
          var removedEvent = failedEvents.removeAt(0);
          await prefs.setStringList('failedEvents', failedEvents);
          var decodedRemovedEvent =
              BuiltEvent.fromJson(json.decode(removedEvent));
          var removedEventDate = DateTime.fromMillisecondsSinceEpoch(
              decodedRemovedEvent.timestamp);
          var difference = DateTime.now().difference(removedEventDate);
          if (difference.inMinutes <= 15) {
            _sendRequest(decodedRemovedEvent);
          }
        }
      });
    }();
  }

  // Events

  /// Return a `page_view` event.
  Event pageView({required Map<String, String> labels}) {
    return Event(name: 'page_view', labels: labels);
  }

  /// Return a `add_cart` event.
  Event addCart(
      {required List<String> ids, required Map<String, String> labels}) {
    var mergedLabels = {'ids': ids, ...labels};
    return Event(name: 'add_cart', labels: mergedLabels);
  }

  /// Return a `purchase` event.
  Event purchase(
      {required List<String> ids,
      required num totalAmount,
      required Map<String, String> labels,
      required String transId}) {
    var mergedLabels = {
      'ids': ids,
      'value': totalAmount,
      'transId': transId,
      ...labels
    };
    return Event(name: 'purchase', labels: mergedLabels);
  }

  /// Return a `product_page` event.
  Event productPage({required String id, required Map<String, String> labels}) {
    var mergedLabels = {
      'ids': [id],
      ...labels
    };
    return Event(name: 'product_page', labels: mergedLabels);
  }

  /// Return a `category_view` event.
  Event categoryView(
      {required String id, required Map<String, String> labels}) {
    var mergedLabels = {
      'ids': [id],
      ...labels
    };
    return Event(name: 'category_view', labels: mergedLabels);
  }

  /// Return a `brand_view` event.
  Event brandView({required String id, required Map<String, String> labels}) {
    var mergedLabels = {
      'ids': [id],
      ...labels
    };
    return Event(name: 'brand_view', labels: mergedLabels);
  }

  /// Return a `product_hover` event.
  Event productHover(
      {required String id, required Map<String, String> labels}) {
    var mergedLabels = {
      'ids': [id],
      ...labels
    };
    return Event(name: 'product_hover', labels: mergedLabels);
  }

  /// Return a `<name>` event.
  Event custom({required String name, required Map<String, String> labels}) {
    return Event(name: name, labels: labels);
  }

  /// Sends the given event.
  ///
  /// ### Example
  ///
  /// ```dart
  /// var event = reelevantAnalytics.pageView(labels: {});
  /// reelevantAnalytics.send(event);
  /// ```
  Future<void> send(Event event) async {
    var builtEvent = await _buildEventPayload(event.name, event.labels);
    return _sendRequest(builtEvent);
  }

  /// Sets the user identifier and sends an identify event.
  ///
  /// ### Example
  ///
  /// ```dart
  /// reelevantAnalytics.setUser('user-id');
  /// ```
  Future<void> setUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    var storedUserId = prefs.getString('userId');
    if (storedUserId == null || storedUserId != userId) {
      await prefs.setString('userId', userId);
      var builtEvent = await _buildEventPayload('identify', {});
      await _sendRequest(builtEvent);
    }
  }

  /// Sets the current url to identify where the user is when an event is sent.
  ///
  /// ### Example
  ///
  /// ```dart
  /// reelevantAnalytics.setCurrentURL('https://example.com');
  /// ```
  void setCurrentURL(String url) {
    currentUrl = url;
  }

  // ---------------------------------------------------------------------------
  // Personalization API
  // ---------------------------------------------------------------------------

  /// Execute a single workflow run.
  /// Returns a typed [RunResult] with a discriminated `body`.
  /// userId is auto-resolved from stored identity ([setUser] / tmpId) unless overridden in [options].
  ///
  /// ### Example
  ///
  /// ```dart
  /// final result = await rlvt.run(RunOptions(
  ///   workflowId: 'wf-hero',
  ///   entrypoint: '43a490a0',
  /// ));
  /// if (result.body is JsonRunContent) {
  ///   renderCard((result.body as JsonRunContent).content);
  /// }
  /// ```
  Future<RunResult> run(RunOptions options) async {
    try {
      final effectiveUserId = options.userId ?? await _resolveUserId();
      return await executeRunnerCall(
        options: options,
        runnerUrl: runnerUrl,
        timeout: runnerTimeout,
        userId: effectiveUserId,
        client: client,
      );
    } catch (e) {
      return _handleRunError(options, e);
    }
  }

  /// Execute multiple workflow runs in parallel.
  /// Returns results in the same order as the input options.
  Future<List<RunResult>> runAll(List<RunOptions> optionsList) async {
    return Future.wait(optionsList.map((opts) => run(opts)));
  }

  Future<String> _resolveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId') ??
        prefs.getString('tmpId') ??
        _randomIdentifier();
  }

  Future<RunResult> _handleRunError(RunOptions options, Object error) async {
    switch (fallback) {
      case FallbackStrategy.error:
        throw error;
      case FallbackStrategy.empty:
        if (fallbackHandler != null) {
          return fallbackHandler!(options, error);
        }
        return RunResult(
          status: 0,
          source: RunSource.fallback,
          body: EmptyRunContent(),
          metadata: {},
          properties: {},
          executionPath: [],
          redirectionUrl: '',
        );
    }
  }

  // Private methods

  /// Generate a random identifier.
  String _randomIdentifier() {
    var letters =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List<String>.filled(25, '')
        .map((_) => letters[Random().nextInt(62)])
        .join();
  }

  /// Store failed events to retrieve it on next app launch.
  Future<void> _addToFailedEvents(BuiltEvent body) async {
    final prefs = await SharedPreferences.getInstance();
    var failedEvents = prefs.getStringList('faildEvents') ?? [];
    failedEvents.add(jsonEncode(body.toJSON()));
    await prefs.setStringList('failedEvents', failedEvents);
  }

  /// Retrieve failed events from storage.
  Future<List<String>> _getFailedEvents() async {
    final prefs = await SharedPreferences.getInstance();
    var failedEvents = prefs.getStringList('failedEvents') ?? [];
    return failedEvents;
  }

  /// Send http request with event payload to `this.endpoint`.
  Future<void> _sendRequest(BuiltEvent body) async {
    var headers = {
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.userAgentHeader: userAgent ?? 'unknown'
    };

    try {
      var response = await client.post(Uri.parse(endpoint),
          headers: headers, body: jsonEncode(body.toJSON()));
      if (response.statusCode >= 500) {
        developer.log(response.toString());
        throw Exception("Can't publish event.");
      }
    } catch (e) {
      developer.log(e.toString());
      _addToFailedEvents(body);
    }
  }

  /// Create event payload from event generated by events functions.
  Future<BuiltEvent> _buildEventPayload(
      String name, Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();

    var event = BuiltEvent(
        key: companyId,
        name: name,
        url: currentUrl ?? 'unknown',
        tmpId: prefs.getString('tmpId')!,
        clientId: prefs.getString('userId'),
        data: payload,
        eventId: _randomIdentifier(),
        v: 1,
        timestamp: DateTime.now().millisecondsSinceEpoch);
    return event;
  }
}
