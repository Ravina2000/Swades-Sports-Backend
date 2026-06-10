import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'package:quickslot_backend/database.dart';
import 'package:quickslot_backend/routes/bookings.dart';
import 'package:quickslot_backend/routes/venues.dart';

Middleware cors() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-User-Id',
};

Handler createHandler(AppDatabase database) {
  final router = Router();

  router.get('/health', (Request request) {
    return Response.ok('ok');
  });

  router.mount('/', venuesRouter(database.db));
  router.mount('/', bookingsRouter(database.db));

  router.all('/<ignored|.*>', (Request request) {
    return Response.notFound('Not found');
  });

  return Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(cors())
      .addHandler(router.call);
}

Future<void> main(List<String> args) async {
  final port = int.tryParse(
        Platform.environment['PORT'] ?? (args.isNotEmpty ? args.first : '8080'),
      ) ??
      8080;

  final database = AppDatabase();
  final handler = createHandler(database);

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('QuickSlot API running on http://${server.address.host}:${server.port}');
  print('Users: user-1, user-2, user-3 (send as X-User-Id header)');

  ProcessSignal.sigint.watch().listen((_) {
    database.close();
    exit(0);
  });
}
