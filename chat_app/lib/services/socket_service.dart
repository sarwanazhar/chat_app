import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef SocketEventHandler = void Function(Map<String, dynamic> data);

class SocketService {
  WebSocketChannel? _channel;
  final String serverUrl;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  SocketService({this.serverUrl = 'ws://10.0.2.2:4000/ws'});

  void connect({required String token}) {
    if (_isConnected) return;

    try {
      final uri = Uri.parse('$serverUrl?token=$token');
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(decoded);
          } catch (e) {
            // Ignore malformed json
          }
        },
        onError: (error) {
          _isConnected = false;
        },
        onDone: () {
          _isConnected = false;
        },
      );
    } catch (e) {
      _isConnected = false;
    }
  }

  void joinRoom({required String roomId, required String userId, int lastSeq = 0}) {
    send({
      'type': 'join',
      'roomId': roomId,
      'userId': userId,
      'lastSeq': lastSeq,
    });
  }

  void sendChatMessage({
    required String id,
    required String roomId,
    required String senderId,
    required String content,
  }) {
    send({
      'type': 'chat_message',
      'id': id,
      'roomId': roomId,
      'senderId': senderId,
      'content': content,
    });
  }

  void sendReceipt({
    required String roomId,
    required String userId,
    required String status,
    required int sequenceId,
  }) {
    send({
      'type': 'receipt',
      'roomId': roomId,
      'userId': userId,
      'status': status,
      'sequenceId': sequenceId,
    });
  }

  void send(Map<String, dynamic> event) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(event));
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}
