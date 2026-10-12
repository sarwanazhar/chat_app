const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../db');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

// List all chat rooms
router.get('/', authenticateToken, (req, res) => {
  try {
    const rooms = db.prepare('SELECT * FROM rooms ORDER BY created_at ASC').all();
    res.json(rooms);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create a new room
router.post('/', authenticateToken, (req, res) => {
  try {
    const { name } = req.body;
    if (!name) {
      return res.status(400).json({ error: 'Room name is required' });
    }

    const id = uuidv4();
    const createdAt = Date.now();
    db.prepare('INSERT INTO rooms (id, name, created_at) VALUES (?, ?, ?)').run(id, name, createdAt);

    res.status(201).json({ id, name, created_at: createdAt });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Fetch messages delta for a room
router.get('/:roomId/messages', authenticateToken, (req, res) => {
  try {
    const { roomId } = req.params;
    const lastSeq = parseInt(req.query.lastSeq || '0', 10);

    const messages = db
      .prepare('SELECT * FROM messages WHERE room_id = ? AND sequence_id > ? ORDER BY sequence_id ASC')
      .all(roomId, lastSeq);

    res.json(messages);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
