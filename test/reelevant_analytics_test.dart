import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:reelevant_analytics/reelevant_analytics.dart';
import 'package:reelevant_analytics/reelevant_analytics_platform_interface.dart';
import 'package:reelevant_analytics/reelevant_analytics_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockReelevantAnalyticsPlatform
    with MockPlatformInterfaceMixin
    implements ReelevantAnalyticsPlatform {
  @override
  Future<String?> getUserAgent() => Future.value('foo agent');
  @override
  Future<String?> getDeviceId() => Future.value('42');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ReelevantAnalyticsPlatform initialPlatform =
      ReelevantAnalyticsPlatform.instance;
  var tmpId = 'tmp-id';
  var userId = 'user-id';
  var currentURL = 'https://example.com';

  test('$MethodChannelReelevantAnalytics is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelReelevantAnalytics>());
  });

  test('identify user', () async {
    SharedPreferences.setMockInitialValues({'tmpId': tmpId});
    ReelevantAnalytics reelevantAnalytics = ReelevantAnalytics(
        companyId: 'company-id', datasourceId: 'datasource-id');
    MockReelevantAnalyticsPlatform fakePlatform =
        MockReelevantAnalyticsPlatform();
    ReelevantAnalyticsPlatform.instance = fakePlatform;

    BuiltEvent? result;
    // Replace client use in instance by the mocked client
    reelevantAnalytics.client = MockClient((request) async {
      result = BuiltEvent.fromJson(json.decode(request.body));
      return Response('', 200);
    });

    // Set user id
    await reelevantAnalytics.setUser(userId);
    // Expect an identify event
    expect(result?.name, 'identify');
    result = null;

    // Ensure we doesn't send a 2nd req with the same user
    await reelevantAnalytics.setUser(userId);
    expect(result, null);
  });

  test('purchase', () async {
    SharedPreferences.setMockInitialValues({'tmpId': tmpId});
    ReelevantAnalytics reelevantAnalytics = ReelevantAnalytics(
        companyId: 'company-id', datasourceId: 'datasource-id');
    MockReelevantAnalyticsPlatform fakePlatform =
        MockReelevantAnalyticsPlatform();
    ReelevantAnalyticsPlatform.instance = fakePlatform;

    BuiltEvent? result;
    // Replace client use in instance by the mocked client
    reelevantAnalytics.client = MockClient((request) async {
      result = BuiltEvent.fromJson(json.decode(request.body));
      return Response('', 200);
    });

    // Set user id
    await reelevantAnalytics.setUser(userId);
    // Expect an identify event
    expect(result?.name, 'identify');
    // Set current url
    reelevantAnalytics.setCurrentURL(currentURL);
    // Send purchase event
    var event = reelevantAnalytics.purchase(
        ids: ['1', '2'],
        totalAmount: 101,
        transId: 'uuid',
        labels: {'foo': 'bar'});
    await reelevantAnalytics.send(event);
    // Expect a purchase events
    expect(result?.name, 'purchase');
    expect(result?.key, 'company-id');
    expect(result?.clientId, userId);
    expect(result?.url, currentURL);
    expect(result?.v, 1);
    expect(result?.eventId, isNot(''));
    expect(result?.tmpId, tmpId);
    expect(result?.timestamp, isNot(0));
    expect(result?.data['ids'], ['1', '2']);
    expect(result?.data['value'], 101);
    expect(result?.data['transId'], 'uuid');
    expect(result?.data['foo'], 'bar');
  });

  test('retry events', () async {
    SharedPreferences.setMockInitialValues({'tmpId': tmpId});
    ReelevantAnalytics reelevantAnalytics = ReelevantAnalytics(
        companyId: 'company-id', datasourceId: 'datasource-id', retry: 1);
    MockReelevantAnalyticsPlatform fakePlatform =
        MockReelevantAnalyticsPlatform();
    ReelevantAnalyticsPlatform.instance = fakePlatform;

    BuiltEvent? result;
    int count = 0;
    // Replace client use in instance by the mocked client
    reelevantAnalytics.client = MockClient((request) async {
      // Return a 500 status code the first time
      if (count == 0) {
        count++;
        return Response('', 500);
      }
      // Return a 200 status code the second time
      result = BuiltEvent.fromJson(json.decode(request.body));
      return Response('', 200);
    });

    // Send page_view event
    var event = reelevantAnalytics.pageView(labels: {});
    await reelevantAnalytics.send(event);

    expect(result, null);
    var prefs = await SharedPreferences.getInstance();
    var failedEvents = prefs.getStringList('failedEvents');
    expect(failedEvents, isNotEmpty);

    // Wait the failed events queue loop
    await Future.delayed(const Duration(seconds: 2));

    // Expect a page_view events from the failed events queue
    expect(result?.name, 'page_view');
  });
}
