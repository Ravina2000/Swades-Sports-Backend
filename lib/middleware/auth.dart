import 'dart:convert';

import 'package:shelf/shelf.dart';

const allowedUserIds = {'user-1', 'user-2', 'user-3'};

Response? requireUserId(Request request) {
  final userId = request.headers['x-user-id'];
  if (userId == null || userId.isEmpty) {
    return Response(
      401,
      body: jsonEncode({
        'error': 'Missing X-User-Id header',
        'message': 'Send a valid user id: user-1, user-2, or user-3',
      }),
      headers: {'content-type': 'application/json'},
    );
  }
  if (!allowedUserIds.contains(userId)) {
    return Response(
      403,
      body: jsonEncode({
        'error': 'Invalid user',
        'message': 'Unknown user id. Use user-1, user-2, or user-3',
      }),
      headers: {'content-type': 'application/json'},
    );
  }
  return null;
}
