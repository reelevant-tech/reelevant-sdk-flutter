[![Tests](https://github.com/reelevant-tech/analytics-flutter/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/reelevant-tech/analytics-flutter/actions/workflows/tests.yml)
![iOS](https://img.shields.io/badge/Platform-iOS-blueviolet)
![Android](https://img.shields.io/badge/Platform-Android-brightgreen)
[![Pub Version](https://img.shields.io/pub/v/reelevant_analytics)](https://pub.dev/packages/reelevant_analytics)
[![Pub Likes](https://img.shields.io/pub/likes/reelevant_analytics)](https://pub.dev/packages/reelevant_analytics/score)
[![Pub Points](https://img.shields.io/pub/points/reelevant_analytics)](https://pub.dev/packages/reelevant_analytics/score)
[![Pub Popularity](https://img.shields.io/pub/popularity/reelevant_analytics)](https://pub.dev/packages/reelevant_analytics/score)
[![Pub Publisher](https://img.shields.io/pub/publisher/reelevant_analytics)](https://pub.dev/publishers/reelevant.com/packages)

# Reelevant SDK for Flutter (iOS and Android)

Analytics tracking **and** real-time personalisation for Flutter apps, powered by Reelevant.

## Install

```
flutter pub add reelevant_analytics
```
See [pub.dev](https://pub.dev/packages/reelevant_analytics/install) for more information.

## How to use

You need a `datasourceId` and a `companyId` to initialise the SDK:

```dart
final rlvt = ReelevantAnalytics(companyId: '<company id>', datasourceId: '<datasource id>');
```

## Analytics

### Sending events

```dart
var event = rlvt.pageView(labels: {});
rlvt.send(event);
```

### Current URL

When a user is browsing a page you should call the `rlvt.setCurrentURL` method if you want to be able to filter on it in Reelevant.

### User identity

To identify a user, call `rlvt.setUser('<user id>')` — the SDK stores the user ID on-device and sends it with every event and personalization call.

### Labels

Each event type allows you to pass additional info via `labels` (`Map<String, String>`) on which you'll be able to filter in Reelevant.

```dart
var event = rlvt.addCart(ids: ['my-product-id'], labels: {'lang': 'en_US'});
```

## Personalisation

The SDK can call the Reelevant runner to fetch personalised content for your app. Identity is automatically resolved from `setUser()` / device ID — no need to pass it manually.

### Configuration

Personalization parameters are optional (defaults work out of the box):

```dart
final rlvt = ReelevantAnalytics(
    companyId: '...',
    datasourceId: '...',
    // optional — defaults below
    runnerUrl: 'https://reelevant.run',
    runnerTimeout: Duration(seconds: 5),
    fallback: FallbackStrategy.empty,
);
```

### Single workflow run

```dart
final result = await rlvt.run(RunOptions(
    workflowId: 'wf-hero',
    entrypoint: '43a490a0',
));

if (result.body is JsonRunContent) {
    final data = (result.body as JsonRunContent).content;
    renderCard(data);
} else if (result.body is HtmlRunContent) {
    loadHtml((result.body as HtmlRunContent).content);
} else if (result.body is ImageRunContent) {
    displayImage((result.body as ImageRunContent).content);
} else {
    showDefault();
}
```

### Multiple workflows in parallel

```dart
final results = await rlvt.runAll([
    RunOptions(workflowId: 'wf-hero', entrypoint: '43a490a0'),
    RunOptions(workflowId: 'wf-sidebar', entrypoint: 'b7e21f3c'),
]);
```

### Click tracking

Every `RunResult` includes a `redirectionUrl` (for use as a link href) and a `trackClick()` method for fire-and-forget server-side tracking:

```dart
// Option 1: Use redirectionUrl as a link
launchUrl(Uri.parse(result.redirectionUrl));

// Option 2: Track the click programmatically
await result.trackClick();
```

### RunResult fields

| Field | Type | Description |
|-------|------|-------------|
| `status` | `int` | HTTP status code (0 for fallback) |
| `source` | `RunSource` | `runner` or `fallback` |
| `body` | `RunContent` | Typed content (`JsonRunContent`, `HtmlRunContent`, `ImageRunContent`, or `EmptyRunContent`) |
| `metadata` | `Map<String, dynamic>` | Metadata from the output node |
| `properties` | `Map<String, dynamic>` | Output properties |
| `runId` | `String?` | Workflow run ID for tracking |
| `executionPath` | `List<String>` | Branch IDs taken during execution |
| `redirectionUrl` | `String` | Pre-built click-through URL |

### Fallback strategies

```dart
// Default — returns an empty result on error
FallbackStrategy.empty

// Throws the underlying error
FallbackStrategy.error
```

### Run options

| Option | Type | Description |
|--------|------|-------------|
| `workflowId` | `String` | Workflow ID |
| `entrypoint` | `String` | Entrypoint shortId |
| `userId` | `String?` | Override identity (default: auto-resolved) |
| `params` | `Map<String, String>?` | URL parameters forwarded to runner |
| `locale` | `String?` | Locale for content resolution |
| `timeout` | `Duration?` | Per-call timeout override |

## Contribute

This project is a Flutter [plug-in package](https://flutter.dev/developing-packages/), a specialized package that includes platform-specific implementation code for Android and iOS.

For help getting started with Flutter development, view the
[online documentation](https://flutter.dev/docs), which offers tutorials, samples, guidance on mobile development, and a full API reference.
