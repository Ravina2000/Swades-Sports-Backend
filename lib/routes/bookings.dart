import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../database.dart';
import '../middleware/auth.dart';
import '../seed.dart';

Handler bookingsRouter(Database db) {
  final router = Router();

  router.post('/bookings', (Request request) async {
    final authError = requireUserId(request);
    if (authError != null) return authError;
    final userId = request.headers['x-user-id']!;

    final body = await request.readAsString();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return _badRequest('Request body must be valid JSON');
    }

    final venueId = payload['venue_id'];
    final date = payload['date'];
    final startHour = payload['start_hour'];

    if (venueId is! int && venueId is! num) {
      return _badRequest('venue_id must be an integer');
    }
    if (date is! String || !isValidDate(date)) {
      return _badRequest('date must be YYYY-MM-DD');
    }
    if (startHour is! int && startHour is! num) {
      return _badRequest('start_hour must be an integer');
    }

    final parsedVenueId = (venueId as num).toInt();
    final parsedStartHour = (startHour as num).toInt();
    final parsedEndHour = parsedStartHour + 1;

    if (!isValidSlotHour(parsedStartHour)) {
      return _badRequest(
        'start_hour must be between $slotStartHour and $lastSlotStartHour (inclusive)',
      );
    }

    final venue = db.select(
      'SELECT id FROM venues WHERE id = ?',
      [parsedVenueId],
    );
    if (venue.isEmpty) {
      return Response(
        404,
        body: jsonEncode({'error': 'Venue not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    try {
      db.execute('BEGIN IMMEDIATE;');

      db.execute(
        '''
        INSERT INTO bookings (user_id, venue_id, slot_date, start_hour, end_hour, status)
        VALUES (?, ?, ?, ?, ?, 'confirmed')
        ''',
        [userId, parsedVenueId, date, parsedStartHour, parsedEndHour],
      );

      final bookingId = db.lastInsertRowId;
      db.execute('COMMIT;');

      final row = db.select(
        '''
        SELECT b.id, b.user_id, b.venue_id, v.name AS venue_name,
               b.slot_date, b.start_hour, b.end_hour, b.status, b.created_at
        FROM bookings b
        JOIN venues v ON v.id = b.venue_id
        WHERE b.id = ?
        ''',
        [bookingId],
      ).first;

      return Response(
        201,
        body: jsonEncode(_bookingJson(row)),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      db.execute('ROLLBACK;');

      if (isSqliteUniqueViolation(e)) {
        return Response(
          409,
          body: jsonEncode({
            'error': 'Slot already taken',
            'message':
                'This slot was just booked by someone else. Please pick another time.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      rethrow;
    }
  });

  router.get('/users/<id>/bookings', (Request request, String id) {
    if (!allowedUserIds.contains(id)) {
      return Response(
        404,
        body: jsonEncode({'error': 'User not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final rows = db.select(
      '''
      SELECT b.id, b.user_id, b.venue_id, v.name AS venue_name,
             b.slot_date, b.start_hour, b.end_hour, b.status, b.created_at
      FROM bookings b
      JOIN venues v ON v.id = b.venue_id
      WHERE b.user_id = ? AND b.status = 'confirmed'
      ORDER BY b.slot_date, b.start_hour
      ''',
      [id],
    );

    return Response.ok(
      jsonEncode(rows.map(_bookingJson).toList()),
      headers: {'content-type': 'application/json'},
    );
  });

  router.delete('/bookings/<id>', (Request request, String id) {
    final authError = requireUserId(request);
    if (authError != null) return authError;
    final userId = request.headers['x-user-id']!;

    final bookingId = int.tryParse(id);
    if (bookingId == null) {
      return _badRequest('Invalid booking id');
    }

    final existing = db.select(
      'SELECT id, user_id, status FROM bookings WHERE id = ?',
      [bookingId],
    );
    if (existing.isEmpty) {
      return Response(
        404,
        body: jsonEncode({'error': 'Booking not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final booking = existing.first;
    if (booking['user_id'] != userId) {
      return Response(
        403,
        body: jsonEncode({
          'error': 'Forbidden',
          'message': 'You can only cancel your own bookings',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    if (booking['status'] != 'confirmed') {
      return Response(
        410,
        body: jsonEncode({'error': 'Booking already cancelled'}),
        headers: {'content-type': 'application/json'},
      );
    }

    db.execute(
      "UPDATE bookings SET status = 'cancelled' WHERE id = ?",
      [bookingId],
    );

    return Response.ok(
      jsonEncode({'message': 'Booking cancelled', 'id': bookingId}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router.call;
}

Map<String, dynamic> _bookingJson(Map<String, Object?> row) => {
      'id': row['id'],
      'user_id': row['user_id'],
      'venue_id': row['venue_id'],
      'venue_name': row['venue_name'],
      'date': row['slot_date'],
      'start_hour': row['start_hour'],
      'end_hour': row['end_hour'],
      'start_time': formatHour(row['start_hour']! as int),
      'end_time': formatHour(row['end_hour']! as int),
      'status': row['status'],
      'created_at': row['created_at'],
    };


Response _badRequest(String message) => Response(
      400,
      body: jsonEncode({'error': 'Invalid input', 'message': message}),
      headers: {'content-type': 'application/json'},
    );
