const { WebSocketServer } = require('ws');
const url = require('url');
const db = require('./db');
const { verifyWsToken } = require('./middleware/auth');

function setupWebSocketServer(server) {
  const wss = new WebSocketServer({ noServer: true });

  // Map to store connected clients by roomId: roomId -> Set of ws clients
  const rooms = new Map();

  server.on('upgrade', (request, socket, head) => {
    const parsedUrl = url.parse(request.url, true);
    const { pathname, query } = parsedUrl;

    if (pathname === '/ws') {
      const token = query.token;
      const user = verifyWsToken(token);

      if (!user) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      wss.handleUpgrade(request, socket, head, (ws) => {
        ws.user = user;
        wss.emit('connection', ws, request);
      });
    } else {
      socket.destroy();
    }
  });

  wss.on('connection', (ws) => {
    let currentRoomId = null;

    ws.on('message', (data) => {
      try {
        const payload = JSON.parse(data.toString());
        const { type } = payload;

        switch (type) {
          case 'join': {
            const { roomId, lastSeq = 0 } = payload;
            currentRoomId = roomId;

            // Register room client
            if (!rooms.has(roomId)) {
              rooms.set(roomId, new Set());
            }
            rooms.get(roomId).add(ws);

            // Send sync_batch with messages > lastSeq
            const messages = db
              .prepare(
                'SELECT sequence_id AS sequenceId, id, sender_id AS senderId, content, created_at AS createdAt FROM messages WHERE room_id = ? AND sequence_id > ? ORDER BY sequence_id ASC'
              )
              .all(roomId, lastSeq);

            const latest = messages.length > 0 ? messages[messages.length - 1].sequenceId : lastSeq;

            ws.send(
              JSON.stringify({
                type: 'sync_batch',
                messages,
                latestSeq: latest,
              })
            );
            break;
          }

          case 'chat_message': {
            const { id, roomId, content } = payload;
            const senderId = ws.user.id;
            const createdAt = Date.now();

            if (!id || !roomId || !content) {
              return;
            }

            // Ensure room exists
            db.prepare('INSERT OR IGNORE INTO rooms (id, name, created_at) VALUES (?, ?, ?)').run(
              roomId,
              roomId,
              createdAt
            );

            // Enforce idempotency: INSERT OR IGNORE
            const stmt = db.prepare(`
              INSERT OR IGNORE INTO messages (id, room_id, sender_id, content, created_at)
              VALUES (?, ?, ?, ?, ?)
            `);
            const info = stmt.run(id, roomId, senderId, content, createdAt);

            // Fetch the persisted message
            const savedMsg = db
              .prepare(
                'SELECT sequence_id AS sequenceId, id, sender_id AS senderId, content, created_at AS createdAt FROM messages WHERE id = ?'
              )
              .get(id);

            if (!savedMsg) return;

            // Acknowledge back to sender
            ws.send(
              JSON.stringify({
                type: 'ack',
                id: savedMsg.id,
                sequenceId: savedMsg.sequenceId,
                createdAt: savedMsg.createdAt,
              })
            );

            // Broadcast new_message to all other connected room clients
            const roomClients = rooms.get(roomId);
            if (roomClients) {
              const eventPayload = JSON.stringify({
                type: 'new_message',
                message: savedMsg,
              });

              for (const client of roomClients) {
                if (client !== ws && client.readyState === 1) {
                  client.send(eventPayload);
                }
              }
            }
            break;
          }

          case 'receipt': {
            const { roomId, status, sequenceId } = payload;
            const userId = ws.user.id;

            if (roomId && status && sequenceId !== undefined) {
              // Upsert receipt
              const isRead = status === 'read';
              db.prepare(`
                INSERT INTO receipts (user_id, room_id, last_delivered_seq, last_read_seq)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(user_id, room_id) DO UPDATE SET
                  last_delivered_seq = MAX(last_delivered_seq, excluded.last_delivered_seq),
                  last_read_seq = MAX(last_read_seq, excluded.last_read_seq)
              `).run(userId, roomId, isRead ? sequenceId : sequenceId, isRead ? sequenceId : 0);

              // Broadcast receipt_update to room clients
              const roomClients = rooms.get(roomId);
              if (roomClients) {
                const receiptPayload = JSON.stringify({
                  type: 'receipt_update',
                  roomId,
                  userId,
                  status,
                  sequenceId,
                });

                for (const client of roomClients) {
                  if (client !== ws && client.readyState === 1) {
                    client.send(receiptPayload);
                  }
                }
              }
            }
            break;
          }

          default:
            break;
        }
      } catch (err) {
        console.error('Error handling WebSocket message:', err);
      }
    });

    ws.on('close', () => {
      if (currentRoomId && rooms.has(currentRoomId)) {
        rooms.get(currentRoomId).delete(ws);
        if (rooms.get(currentRoomId).size === 0) {
          rooms.delete(currentRoomId);
        }
      }
    });
  });

  return wss;
}

module.exports = { setupWebSocketServer };
