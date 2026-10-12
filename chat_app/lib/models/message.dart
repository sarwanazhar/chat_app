class Message {
  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final int? sequenceId;
  final String status; // 'pending' | 'sent' | 'delivered' | 'read'
  final int createdAt;

  Message({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    this.sequenceId,
    required this.status,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      roomId: (json['roomId'] ?? json['conversation_id'] ?? json['room_id'] ?? '') as String,
      senderId: (json['senderId'] ?? json['sender_id'] ?? '') as String,
      content: json['content'] as String,
      sequenceId: json['sequenceId'] ?? json['sequence_id'],
      status: (json['status'] ?? 'sent') as String,
      createdAt: json['createdAt'] ?? json['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roomId': roomId,
      'senderId': senderId,
      'content': content,
      'sequenceId': sequenceId,
      'status': status,
      'createdAt': createdAt,
    };
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'conversation_id': roomId,
      'sender_id': senderId,
      'content': content,
      'sequence_id': sequenceId,
      'status': status,
      'created_at': createdAt,
    };
  }

  Message copyWith({
    String? id,
    String? roomId,
    String? senderId,
    String? content,
    int? sequenceId,
    String? status,
    int? createdAt,
  }) {
    return Message(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      sequenceId: sequenceId ?? this.sequenceId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
