import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../seed.dart';

Handler venuesRouter(Database db) {
  final router = Router();

  router.get('/venues', (Request request) {
    final rows = db.select('''
      SELECT id, name, type, location, description
      FROM venues
      ORDER BY id
    ''');

    final venues = rows
        .map(
          (row) => {
            'id': row['id'],
            'name': row['name'],
            'type': row['type'],
            'location': row['location'],
            'description': row['description'],
          },
        )
        .toList();

    return Response.ok(
      jsonEncode(venues),
      headers: {'content-type': 'application/json'},
    );
  });

  router.get('/venues/<id>/slots', (Request request, String id) {
    final venueId = int.tryParse(id);
    if (venueId == null) {
      return _badRequest('Invalid venue id');
    }

    final date = request.url.queryParameters['date'];
    if (date == null || date.isEmpty) {
      return _badRequest('Query parameter "date" is required (YYYY-MM-DD)');
    }
    if (!isValidDate(date)) {
      return _badRequest('Invalid date format. Use YYYY-MM-DD');
    }

    final venue = db.select(
      'SELECT id, name FROM venues WHERE id = ?',
      [venueId],
    );
    if (venue.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'Venue not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final bookings = db.select(
      '''
      SELECT b.user_id, b.start_hour, u.name AS user_name
      FROM bookings b
      JOIN users u ON u.id = b.user_id
      WHERE b.venue_id = ? AND b.slot_date = ? AND b.status = 'confirmed'
      ''',
      [venueId, date],
    );

    final bookingByHour = {
      for (final row in bookings)
        row['start_hour'] as int: {
          'user_id': row['user_id'],
          'user_name': row['user_name'],
        },
    };

    final currentUserId = request.headers['x-user-id'];

    final slots = <Map<String, dynamic>>[];
    for (var hour = slotStartHour; hour <= lastSlotStartHour; hour++) {
      final booking = bookingByHour[hour];
      String status;
      if (booking == null) {
        status = 'available';
      } else if (currentUserId != null && booking['user_id'] == currentUserId) {
        status = 'booked_by_you';
      } else {
        status = 'booked';
      }

      slots.add({
        'start_hour': hour,
        'end_hour': hour + 1,
        'start_time': formatHour(hour),
        'end_time': formatHour(hour + 1),
        'status': status,
        if (booking != null) 'booked_by': booking['user_id'],
      });
    }

    return Response.ok(
      jsonEncode({
        'venue_id': venueId,
        'venue_name': venue.first['name'],
        'date': date,
        'slots': slots,
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  return router.call;
}

Response _badRequest(String message) => Response(
      400,
      body: jsonEncode({'error': 'Invalid input', 'message': message}),
      headers: {'content-type': 'application/json'},
    );
