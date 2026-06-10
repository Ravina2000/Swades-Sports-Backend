import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Simulates two users booking the same slot at the same instant.
/// Run while the server is up: dart run test/concurrency_test.dart
Future<void> main() async {
  const base = 'http://127.0.0.1:8080';
  // Use a unique slot each run so repeated tests don't collide with prior bookings.
  final hour = 6 + (DateTime.now().millisecondsSinceEpoch % 16);
  const date = '2026-06-20';
  final body = jsonEncode({'venue_id': 1, 'date': date, 'start_hour': hour});

  Future<Map<String, dynamic>> bookAs(String userId) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$base/bookings'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-User-Id', userId);
      request.write(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return {'user': userId, 'status': response.statusCode, 'body': text};
    } finally {
      client.close();
    }
  }

  final results = await Future.wait([
    bookAs('user-1'),
    bookAs('user-2'),
  ]);

  final successes = results.where((r) => r['status'] == 201).length;
  final conflicts = results.where((r) => r['status'] == 409).length;

  print('Concurrent booking results:');
  for (final r in results) {
    print('  ${r['user']}: HTTP ${r['status']} -> ${r['body']}');
  }

  if (successes == 1 && conflicts == 1) {
    print('\nPASS: exactly one booking succeeded, one got 409.');
  } else {
    print('\nFAIL: expected 1 success and 1 conflict, got '
        '$successes success(es) and $conflicts conflict(s).');
    exitCode = 1;
  }
}
