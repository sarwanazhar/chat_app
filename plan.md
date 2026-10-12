# AGENT DIRECTIVE: Local-First WhatsApp-Style Realtime Chat

You are an expert mobile and distributed systems engineer specializing in React Native (Expo) and Cloudflare Workers (Hono, Durable Objects). Your goal is to scaffold and implement a production-grade, local-first real-time messaging engine.


## 1. System Vision & Architecture

Build a local-first messaging client where the UI reads and writes **exclusively** to local device storage (`expo-sqlite`). The remote server is treated as an asynchronous replication target. The app must function seamlessly offline, queue pending actions, and reconcile state automatically upon reconnection.

### Tech Stack
- **Mobile Client:** Expo (SDK 52+), React Native, TypeScript, `expo-sqlite`, `@react-native-community/netinfo`, `@shopify/flash-list`, `zustand`, `uuid` (UUIDv7).
- **Edge Backend:** Cloudflare Workers, Hono, Durable Objects with **WebSocket Hibernation API** and **Embedded DO SQLite** (`ctx.storage.sql`).
- **No external cloud databases or S3/R2 at this phase.**


## 2. Core Engineering Invariants

1. **Local-First Isolation:** The UI must never block on a network request. Sending a message writes to local SQLite immediately.
2. **Strict Ordering:** Outbox mutations must be pushed in chronological order. A failure on message $N$ pauses dispatch of message $N+1$.
3. **Idempotency:** Every client-created message uses a client-generated UUIDv7 (`id`). The server enforces `UNIQUE(id)`. Re-submitting an existing ID returns the existing `sequence_id` with HTTP/WS 200 without creating duplicates.
4. **Watermark Synchronization:** Reconnection sync retrieves delta records using a monotonic integer watermark (`sequence_id > last_synced_sequence_id`). Never sync entire chat histories.
5. **Tick State Progression:** Messages transition strictly forward through:
   `pending` (local only) $\rightarrow$ `sent` (server persisted) $\rightarrow$ `delivered` (recipient received) $\rightarrow$ `read` (recipient opened).


## 3. Data Schemas

### A. Edge Durable Object SQLite Schema
Every room is an isolated Durable Object instance.

```sql
CREATE TABLE IF NOT EXISTS messages (
  sequence_id INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT UNIQUE NOT NULL,             -- Client UUIDv7
  sender_id TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL          -- Unix epoch in milliseconds
);

CREATE TABLE IF NOT EXISTS receipts (
  user_id TEXT NOT NULL PRIMARY KEY,
  last_delivered_seq INTEGER DEFAULT 0,
  last_read_seq INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_messages_seq ON messages(sequence_id);

```

### B. Mobile Local SQLite Schema (`expo-sqlite`)

```sql
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,                 -- room_id
  name TEXT NOT NULL,
  last_sequence_id INTEGER DEFAULT 0,  -- Watermark tracking
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,                 -- Client UUIDv7
  conversation_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  content TEXT NOT NULL,
  sequence_id INTEGER,                 -- Nullable until acknowledged by DO
  status TEXT NOT NULL,                -- 'pending' | 'sent' | 'delivered' | 'read' | 'failed'
  created_at INTEGER NOT NULL,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

CREATE TABLE IF NOT EXISTS outbox_queue (
  id TEXT PRIMARY KEY,                 -- Matches messages.id
  conversation_id TEXT NOT NULL,
  payload TEXT NOT NULL,               -- JSON serialized payload
  attempts INTEGER DEFAULT 0,
  last_attempt_at INTEGER,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_convo ON messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox_queue(created_at ASC);

```

---

## 4. WebSocket Protocol & Type Definitions

```typescript
// Shared Protocol Types
export type ClientEvent =
  | { type: 'join'; roomId: string; userId: string; lastSeq: number }
  | { type: 'chat_message'; id: string; roomId: string; senderId: string; content: string }
  | { type: 'receipt'; roomId: string; userId: string; status: 'delivered' | 'read'; sequenceId: number };

export type ServerEvent =
  | { type: 'ack'; id: string; sequenceId: number; createdAt: number }
  | { type: 'new_message'; message: { id: string; sequenceId: number; senderId: string; content: string; createdAt: number } }
  | { type: 'sync_batch'; messages: Array<{ id: string; sequenceId: number; senderId: string; content: string; createdAt: number }>; latestSeq: number }
  | { type: 'receipt_update'; roomId: string; userId: string; status: 'delivered' | 'read'; sequenceId: number };

```

---

## 5. Implementation Roadmap for Agent

### Task 1: Cloudflare Hono & Durable Object Setup

* Initialize Hono worker handling route `GET /ws/:roomId`.
* Upgrade connection to WebSocket and forward to Durable Object using `env.CHAT_ROOM.get(env.CHAT_ROOM.idFromName(roomId))`.
* In the DO class:
* Implement `fetch()` with `ctx.acceptWebSocket(ws, [userId])`.
* Implement `webSocketMessage(ws, message)`:
* Handle `join`: query messages where `sequence_id > lastSeq`, emit `sync_batch`.
* Handle `chat_message`: execute `INSERT OR IGNORE INTO messages`, emit `ack` to sender, broadcast `new_message` to all other connected clients using `ctx.getWebSockets()`.
* Handle `receipt`: upsert into `receipts`, broadcast `receipt_update`.


* Implement `webSocketClose(ws, code, reason, wasClean)`.



### Task 2: Mobile SQLite Database Provider

* Create `src/db/client.ts` initializing `expo-sqlite` with PRAGMA settings (`journal_mode = WAL`, `foreign_keys = ON`).
* Write migration runner setting up `conversations`, `messages`, and `outbox_queue`.
* Provide typed repository functions:
* `insertPendingMessage(conversationId, senderId, content)`: atomically writes to both `messages` and `outbox_queue`.
* `markMessageSent(id, sequenceId)`: updates message status to `'sent'` and removes from `outbox_queue`.
* `applySyncBatch(conversationId, messages, latestSeq)`: upserts messages into local DB in a single SQLite transaction and updates `conversations.last_sequence_id`.



### Task 3: Resilient Outbox Sync Engine

* Create `src/services/SyncEngine.ts`.
* Hook into `@react-native-community/netinfo`.
* When connectivity restores or app launches:
* Read oldest item from `outbox_queue`.
* Push message to WebSocket or HTTP endpoint.
* On success: remove from `outbox_queue` and process next item.
* On failure: apply exponential backoff jitter (`min(2^attempts * 500ms, 30000ms)`), increment `attempts`, and break out of loop to preserve ordering.



### Task 4: UI & State Integration

* Use `@shopify/flash-list` with `inverted={true}` for chat bubble rendering.
* Render tick indicator based on `status`:
* `'pending'`: Clock icon (gray).
* `'sent'`: Single checkmark (gray).
* `'delivered'`: Double checkmark (gray).
* `'read'`: Double checkmark (blue).


* Trigger read receipt updates when `ChatScreen` gains focus or scrolls to bottom.

---

## 6. Verification & Test Scenarios

1. **Airplane Mode Test:**
* Put device in airplane mode. Send 5 consecutive messages.
* Verify they show as `'pending'` immediately and exist in `outbox_queue`.
* Restore network connection. Verify all 5 messages send in exact FIFO order and update to `'sent'`.


2. **Reconnection Catch-Up:**
* Disconnect recipient. Send 10 messages from sender.
* Reconnect recipient. Ensure `join` event delivers the exact 10 missed messages via `sync_batch` without duplicates.


3. **App Kill Durability:**
* Send offline message and force-quit the application process.
* Relaunch app: verify message persists in UI and auto-sends once online.


