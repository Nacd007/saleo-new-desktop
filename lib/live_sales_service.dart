import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Foreground-only SSE. A batch is acknowledged only after local persistence.
class LiveSalesService {
  http.Client? _client;
  int _generation = 0;
  bool connected = false;

  void stop() {
    _generation++;
    connected = false;
    _client?.close();
    _client = null;
  }

  void start({
    required String baseUrl,
    required Map<String, String> headers,
    required Future<void> Function(List<Map<String, dynamic>>, bool replay)
    onSales,
    required void Function(String) onError,
  }) {
    stop();
    final generation = _generation;
    unawaited(_listen(baseUrl, headers, onSales, onError, generation));
  }

  Future<void> _listen(
    String baseUrl,
    Map<String, String> headers,
    Future<void> Function(List<Map<String, dynamic>>, bool replay) onSales,
    void Function(String) onError,
    int generation,
  ) async {
    var cursor = 0;
    int? replayThrough;
    var failures = 0;
    while (generation == _generation) {
      final client = http.Client();
      _client = client;
      try {
        final uri =
            Uri.parse(
              '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/sales/live',
            ).replace(
              queryParameters: {
                'after': '$cursor',
                if (replayThrough != null) 'replay_through': '$replayThrough',
              },
            );
        final request = http.Request('GET', uri)
          ..headers.addAll({...headers, 'accept': 'text/event-stream'});
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        if (generation != _generation) return;
        if (response.statusCode != 200 ||
            !(response.headers['content-type'] ?? '').contains(
              'text/event-stream',
            )) {
          if (response.statusCode == 401 || response.statusCode == 403) {
            onError(
              'Live sale alerts require a valid administrator session. Sign in again.',
            );
            return;
          }
          throw StateError(
            response.statusCode == 404
                ? 'Live sale alerts need the updated backend deployed.'
                : 'Live sale alerts are disconnected. Reconnecting…',
          );
        }
        connected = true;
        failures = 0;
        var event = '';
        final data = <String>[];
        await for (final line
            in response.stream
                .timeout(const Duration(seconds: 45))
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (generation != _generation) return;
          if (line.startsWith('event:')) event = line.substring(6).trim();
          if (line.startsWith('data:')) data.add(line.substring(5).trimLeft());
          if (line.isEmpty) {
            if (event == 'ready' && data.isNotEmpty) {
              final ready = jsonDecode(data.join('\n')) as Map<String, dynamic>;
              replayThrough = (ready['replay_through'] as num).toInt();
            }
            if (event == 'auth_error') {
              onError('Live sale alerts require signing in again.');
              return;
            }
            if (event == 'sales' && data.isNotEmpty) {
              final payload =
                  jsonDecode(data.join('\n')) as Map<String, dynamic>;
              final rows = (payload['sales'] as List)
                  .map((row) => (row as Map).cast<String, dynamic>())
                  .toList();
              await onSales(rows, payload['replay'] == true);
              // Failed storage keeps the old cursor, so reconnect retries safely.
              cursor = (payload['cursor'] as num).toInt();
            }
            event = '';
            data.clear();
          }
        }
      } catch (error) {
        if (generation != _generation) return;
        failures++;
        onError(
          error is StateError
              ? error.message.toString()
              : 'Live sale alerts are disconnected. Reconnecting…',
        );
      } finally {
        client.close();
        if (generation == _generation) {
          connected = false;
          _client = null;
        }
      }
      if (generation != _generation) return;
      // Normal 30-second stream rotation reconnects immediately; failures back off.
      if (failures > 0) {
        await Future<void>.delayed(
          Duration(seconds: (1 << failures.clamp(0, 5).toInt())),
        );
      }
    }
  }
}
