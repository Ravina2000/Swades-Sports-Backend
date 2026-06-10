import 'package:sqlite3/sqlite3.dart';

const hardcodedUsers = [
  {'id': 'user-1', 'name': 'Alice Sharma'},
  {'id': 'user-2', 'name': 'Bob Patel'},
  {'id': 'user-3', 'name': 'Charlie Mehta'},
];

const seedVenues = [
  {
    'name': 'Smash Arena Badminton',
    'type': 'badminton',
    'location': 'Satellite, Ahmedabad',
    'description': '6 indoor courts with professional flooring',
  },
  {
    'name': 'Green Turf Sports Hub',
    'type': 'turf',
    'location': 'Bodakdev, Ahmedabad',
    'description': 'FIFA-standard 5-a-side turf with floodlights',
  },
  {
    'name': 'Ace Shuttle Club',
    'type': 'badminton',
    'location': 'Vastrapur, Ahmedabad',
    'description': 'Premium badminton facility with coaching',
  },
  {
    'name': 'Urban Kick Turf',
    'type': 'turf',
    'location': 'SG Highway, Ahmedabad',
    'description': '7-a-side turf ground for football and cricket',
  },
  {
    'name': 'Rally Point Badminton',
    'type': 'badminton',
    'location': 'Maninagar, Ahmedabad',
    'description': 'Budget-friendly courts, open 6 AM – 10 PM daily',
  },
];

/// Hourly slots from 6 AM (start_hour 6) through 9 PM (start_hour 21, ends 10 PM).
const slotStartHour = 6;
const slotClosingHour = 22;
const lastSlotStartHour = slotClosingHour - 1;

void seedIfEmpty(Database db) {
  final count =
      db.select('SELECT COUNT(*) AS c FROM venues').first['c'] as int;
  if (count > 0) return;

  for (final user in hardcodedUsers) {
    db.execute(
      'INSERT INTO users (id, name) VALUES (?, ?)',
      [user['id'], user['name']],
    );
  }

  for (final venue in seedVenues) {
    db.execute(
      '''
      INSERT INTO venues (name, type, location, description)
      VALUES (?, ?, ?, ?)
      ''',
      [venue['name'], venue['type'], venue['location'], venue['description']],
    );
  }
}

String formatHour(int hour) =>
    '${hour.toString().padLeft(2, '0')}:00';

bool isValidSlotHour(int hour) =>
    hour >= slotStartHour && hour <= lastSlotStartHour;

bool isValidDate(String date) {
  final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').firstMatch(date);
  if (match == null) return false;
  try {
    DateTime.parse(date);
    return true;
  } catch (_) {
    return false;
  }
}
