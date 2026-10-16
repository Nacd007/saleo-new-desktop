import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saleo_app/live_sales_service.dart';
import 'package:saleo_app/sync_service.dart';

void main() {
  test('live stream imports history silently and labels only new sales', () async {
    final live = LiveSalesService();
    final done = Completer<void>();
    final replayFlags = <bool>[];
    final ids = <String>[];
    await http.runWithClient(
      () async {
        live.start(
          baseUrl: 'https://fixture.invalid',
          headers: {'authorization': 'Bearer fixture'},
          onError: (message) => done.completeError(StateError(message)),
          onSales: (rows, replay) async {
            replayFlags.add(replay);
            ids.add(rows.first['transaction_uuid'] as String);
            if (!replay) {
              live.stop();
              done.complete();
            }
          },
        );
        await done.future.timeout(const Duration(seconds: 5));
      },
      () => MockClient.streaming((request, body) async {
        expect(request.headers['authorization'], 'Bearer fixture');
        expect(request.url.queryParameters.containsKey('token'), isFalse);
        final text =
            'event: ready\ndata: {"replay_through":5}\n\n'
            'event: sales\ndata: {"cursor":5,"replay":true,"sales":[{"transaction_uuid":"history"}]}\n\n'
            'event: sales\ndata: {"cursor":6,"replay":false,"sales":[{"transaction_uuid":"new"}]}\n\n';
        final bytes = utf8.encode(text);
        return http.StreamedResponse(
          Stream.fromIterable([
            bytes.sublist(0, 13),
            bytes.sublist(13, 61),
            bytes.sublist(61),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );
    expect(ids, ['history', 'new']);
    expect(replayFlags, [true, false]);
    expect(live.connected, isFalse);
  });

  test('revoked live session stops and reports reauthentication', () async {
    final live = LiveSalesService();
    final error = Completer<String>();
    await http.runWithClient(
      () async {
        live.start(
          baseUrl: 'https://fixture.invalid',
          headers: {},
          onSales: (_, replay) async => fail('Unauthorized data imported'),
          onError: (message) => error.complete(message),
        );
        expect(
          await error.future.timeout(const Duration(seconds: 5)),
          contains('Sign in again'),
        );
        live.stop();
      },
      () => MockClient.streaming(
        (request, body) async =>
            http.StreamedResponse(const Stream.empty(), 401),
      ),
    );
  });

  test('failed storage does not acknowledge a sale cursor', () async {
    final live = LiveSalesService();
    final done = Completer<void>();
    final cursors = <String?>[];
    var imports = 0;
    await http.runWithClient(
      () async {
        live.start(
          baseUrl: 'https://fixture.invalid',
          headers: {},
          onError: (_) {},
          onSales: (rows, replay) async {
            if (++imports == 1) throw StateError('Fixture disk unavailable');
            live.stop();
            done.complete();
          },
        );
        await done.future.timeout(const Duration(seconds: 8));
      },
      () => MockClient.streaming((request, body) async {
        cursors.add(request.url.queryParameters['after']);
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'event: ready\ndata: {"replay_through":7}\n\n'
              'event: sales\ndata: {"cursor":8,"replay":false,"sales":[{"transaction_uuid":"retry"}]}\n\n',
            ),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );
    expect(cursors, ['0', '0']);
  });

  test(
    'sales API errors are visible, not treated as an empty ledger',
    () async {
      final sync = SyncService()..useSession('fixture');
      await http.runWithClient(() async {
        expect(await sync.pullSales(), isNull);
        expect(sync.lastSalesDownloadError, contains('expired'));
      }, () => MockClient((_) async => http.Response('{}', 401)));
      await http.runWithClient(() async {
        expect(await sync.pullSales(), []);
        expect(sync.lastSalesDownloadError, isNull);
      }, () => MockClient((_) async => http.Response('{"sales":[]}', 200)));
    },
  );
}
