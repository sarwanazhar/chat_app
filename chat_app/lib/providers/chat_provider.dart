import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/socket_service.dart';

class ChatProvider with ChangeNotifier {
  final SocketService _socketService = SocketService();
  final Uuid _uuid = const Uuid();

  StreamSubscription? _socketSub;
  String? _currentRoomId;
  String? _currentUserId;

  final List<Message> _messages = [];
  bool _isConnected = false;

  List<Message> get messages => List.unmodifiable(_messages);
  String? get currentRoomId => _currentRoomId;
  bool get isConnected => _isConnected;

  void initialize(String token, String userId) {
    _currentUserId = userId;
    _socketService.connect(token: token);

    _socketSub?.cancel();
    _socketSub = _socketService.messageStream.listen(_handleIncomingEvent);
    _isConnected = true;
    notifyListeners();
  }

  void joinRoom(String roomId) {
    _currentRoomId = roomId;
    _messages.clear();

    if (_currentUserId != null) {
      _socketService.joinRoom(
        roomId: roomId,
        userId: _currentUserId!,
        lastSeq: 0,
      );
    }
    notifyListeners();
  }

  void sendMessage(String content) {
    if (_currentRoomId == null || _currentUserId == null || content.trim().isEmpty) {
      return;
    }

    final messageId = _uuid.v4();
    final localMsg = Message(
      id: messageId,
      roomId: _currentRoomId!,
      senderId: _currentUserId!,
      content: content.trim(),
      status: 'pending',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    _messages.add(localMsg);
    notifyListeners();

    _socketService.sendChatMessage(
      id: messageId,
      roomId: _currentRoomId!,
      senderId: _currentUserId!,
      content: content.trim(),
    );
  }

  void sendReceipt(String messageId, int sequenceId, String status) {
    if (_currentRoomId == null || _currentUserId == null) return;
    _socketService.sendReceipt(
      roomId: _currentRoomId!,
      userId: _currentUserId!,
      status: status,
      sequenceId: sequenceId,
    );
  }

  void _handleIncomingEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;

    switch (type) {
      case 'ack':
        final id = event['id'] as String?;
        final seq = event['sequenceId'] as int?;
        if (id != null) {
          final idx = _messages.indexWhere((m) => m.id == id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              sequenceId: seq,
              status: 'sent',
            );
            notifyListeners();
          }
        }
        break;

      case 'new_message':
        final msgData = event['message'] as Map<String, dynamic>?;
        if (msgData != null) {
          final msg = Message.fromJson(msgData);
          final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
          if (existingIdx != -1) {
            _messages[existingIdx] = msg;
          } else {
            _messages.add(msg);
          }
          notifyListeners();
        }
        break;

      case 'sync_batch':
        final list = event['messages'] as List<dynamic>?;
        if (list != null) {
          for (final item in list) {
            final msg = Message.fromJson(item as Map<String, dynamic>);
            final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
            if (existingIdx != -1) {
              _messages[existingIdx] = msg;
            } else {
              _messages.add(msg);
            }
          }
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          notifyListeners();
        }
        break;

      case 'receipt_update':
        final seq = event['sequenceId'] as int?;
        final status = event['status'] as String?;
        if (seq != null && status != null) {
          for (var i = 0; i < _messages.length; i++) {
            final m = _messages[i];
            if (m.sequenceId != null && m.sequenceId! <= seq) {
              _messages[i] = m.copyWith(status: status);
            }
          }
          notifyListeners();
        }
        break;
    }
  }

  void leaveRoom() {
    _currentRoomId = null;
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _socketService.dispose();
    super.dispose();
  }
}
