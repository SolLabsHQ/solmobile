# SolMobile v0 Scaffolding Spec

## Purpose
Ship a **modern messaging-style** SolMobile v0 where the user can:
- view a Thread timeline
- compose and send messages **in-context**
- attach “captures” (voice, files, images, URLs, text)
- let captures process asynchronously (transcription/extraction) without blocking the user
- optionally “solidify” important moments via Anchors + Checkpoints

---

## Decisions

### D1 — Thread + Message are the primary timeline primitives
- Messages exist immediately **locally** upon submit.
- Network state is not conflated with “message existence.”

### D2 — Capture is a first-class object **owned by Message**
- `Message.captures[]` supports multiple async attachments processing independently.
- Capture is not a primary navigation surface in v0 (no “Capture tab”).

### D3 — Composer is an in-thread view
- `CaptureComposerView` sits under the message list.
- Submission creates a Message and associates Captures at that moment.

### D4 — Anchors point to Messages
- Anchors are for solidified items.
- Anchor creation can be done by user, assistant, or system.

### D5 — Introduce Checkpoint (capsule) as a first-class concept
- Checkpoint captures “what we were doing / decisions / next / open questions,” and can later reference FactBlocks.
- Anchors can reference Checkpoints.

### D6 — Transmission is a work unit for remote boundaries, backed by a Packet
- Don’t leak networking payload details into Transmission itself.
- Model: `Transmission 1..1 Packet`, and Packet can evolve/subclass.

### D7 — CFB is split: Nav (local) vs Inference (payload)
- **CFB Nav** is a *local-only* session navigation/controller object (arc, stack, active vs parked, decisions, next, persistence ledger, done criteria, mode history).
- **CFB Inference** is a *thin* model payload sent to SolServer only when helpful (primary arc + decisions + next + optional scope guard).
- Pinned context is **mounted law** referenced in the Packet; capsule/CFB are **runtime deltas** in request context.

---

## Domain Model

### User
Represents the local user identity handle.
- **Fields (v0 minimal):**
  - `userId`
  - `displayName?`
- Owns `Preferences`.

### Preferences
User-controlled settings (budgets/toggles).
- `maxOutputTokens`
- `maxRegenerations`
- (future) auto-transcribe settings, privacy toggles, etc.

### Thread
Container for a conversation/work unit.
- `threadId`
- `title`
- `createdAt`
- `lastActiveAt`
- `pinned`
- `expiresAt?` (TTL)

### Message
Atomic entry in a Thread timeline.
- `messageId`
- `threadId`
- `creatorType`: `user | assistant | system`
- `creatorId?` (e.g., persona id, system component id)
- `text` (may be empty if message is “attachments-only”)
- `createdAt`
- `captures[]` (0..n)
- (optional) `assistantUsage?` (tokens/model/latency; only for assistant messages)

### Capture
Attachment-ish unit owned by a Message.
- `captureId`
- `messageId`
- `type`: `audio | file | image | text | url` (audio/file/image types exist in the enum as reserved but are “deferred” per v0 scope)
- `status`: `pending | ready | failed`
- `dataReference` (required): where the payload lives (local file URL/bookmark, doc ref, etc.)
- `dataDescription?` (display label): filename, “Voice note”, page title, etc.
- `data?` (derived payload text): transcript, extracted pdf text, OCR results, fetched URL content snippet, etc.
- `error?`

**Interpretation guidance**
- `dataDescription` = what the UI shows (“voice note”, “receipt.pdf”, “example.com — Title”)
- `data` = what downstream processing uses (transcript/extracted text)

### Anchor
A solidified reference to a Message (and optionally a Checkpoint).
- `anchorId`
- `messageId`
- `title`
- `summary?`
- `type` (bookmark/decision/resume/commitment/etc.)
- `createdAt`
- `createdByType`: `user | assistant | system`
- `createdById?`
- `checkpointId?` (optional link)

### Checkpoint
Capsule summary of “where we are” in a Thread.
- `checkpointId`
- `threadId`
- `createdAt`
- `createdByType`: `user | assistant | system`
- `createdById?`
- `contextSummary` (what we were doing)
- `factBlockRefs[]?` (our context for what we were doing; future: references to FactBlocks)
- `decisions[]`
- `nextSteps[]`
- `openQuestions[]`

> Checkpoint is the durable “capsule.” Anchors can reference it to mark a moment.

### Transmission
Persisted unit of work targeting a remote boundary (SolServer now; possibly iCloud later).
- `transmissionId`
- `type`: `chat | memorySave | usage | sync` (or more later)
- `requestId` (idempotency key)
- `status`: `queued | sending | succeeded | failed`
- `createdAt`
- `packetId`
- `deliveryAttempts[]`

### DeliveryAttempt
Retry/telemetry record for a Transmission.
- `attemptId`
- `transmissionId`
- `startedAt`
- `endedAt?`
- `status`
- `errorCode?`
- `latencyMs?`

### Packet
Encapsulated payload for a Transmission (extensible).
- `packetId`
- `packetType` (maps to Transmission.type or can diverge later)
- `threadId`
- `messageIds[]`
- `checkpointIds[]?`
- `factBlockIds[]?`
- `budgets?`
- `contextRefs?` (pinned context ref/version/hash, etc.)
- `payload` (opaque JSON/text blob if needed)

> This keeps Transmission stable while Packet evolves.

### Conversation Fact Block (CFB)
SolMobile maintains two related objects:

#### CFB Nav (local-only)
A richer UI/session controller used for re-anchors and drift control.

#### CFB Inference (payload)
A thin subset optionally included in SolServer requests to reduce drift.

> CFB Nav is not sent to SolServer. CFB Inference may be included in request `context` when relevant.

---

## Relationships (Cardinality)
- `User 1—1 Preferences`
- `User 1—* Thread`
- `Thread 1—* Message`
- `Message 0..* Capture`
- `Anchor 1—1 Message`
- `Checkpoint 1—1 Thread`
- `Anchor 0..1 — 1 Checkpoint`
- `Transmission 1—1 Packet`
- `Transmission 0..* DeliveryAttempt`

---

## UI Scaffolding (v0)

### Tabs / Primary Navigation
- **Threads**
- **Anchors**
- **Preferences**

### ThreadDetailView (the main experience)
- Scrollable message timeline
- Inline `CaptureComposerView` at bottom:
  - text input
  - attach: audio/file/image/url/text
  - submit CTA

### Composer submit rules
- Always creates Message locally immediately.
- Associates Captures (0..n) at submit time.
- Captures may be `pending` and update later without blocking new messages.

### Anchors
- “Anchor this message” action on a message
- Anchors list navigates to message-in-thread
- Optional display of linked Checkpoint

### Preferences
- budgets + toggles (v0 minimal)

---

## v0 Flows

### Flow A — Typed message
1. user types
2. submit → `Message(user)` created immediately
3. update thread UI

### Flow B — Voice attachment
1. user records audio → `Capture(audio, pending)` created with `dataReference` to local audio
2. submit → `Message(user)` created with this Capture
3. transcription updates `Capture.status`, `Capture.dataDescription`, `Capture.data`

### Flow C — File/image/url attachments
1. attach item(s) → create one Capture per item (recommended)
2. submit → message created with captures
3. extraction/OCR/fetch updates Capture records independently

### Flow D — Remote chat request (SolServer)
1. create `Transmission(chat)` with a `Packet` that includes:
   - `requestId` (idempotency)
   - thread + message ids
   - `contextRefs` including `pinnedContextRef` (mounted law)
   - optional checkpoint/fact refs
   And request `context` deltas including:
   - capsule summary
   - optional **CFB Inference**
2. attempts recorded in `DeliveryAttempt[]`
3. on success → append `Message(assistant)` with usage metadata

---

## Application Components (for C4 L3 later)
- UI Shell (Tabs, routing)
- ThreadStore
- MessageStore
- CaptureProcessor (transcribe/extract/fetch)
- AnchorStore
- CheckpointStore
- CFBNavStore (local session navigation + re-anchor state)
- TransmissionStore (persistence + retry)
- SolServerClient
- PreferencesStore
- Environment (config)
- Observability hooks

---


---

## CFB Nav Schema

CFB Nav is maintained locally by SolMobile as a session navigation controller (re-anchor state). The canonical schema now lives in:

- `docs/design/cfb-nav-schema.md`

Only the thin **CFB Inference** subset is optionally sent to SolServer in request `context`.

(Planned) A consolidated domain object schema YAML (all v0 objects in one place) can live at:

- `docs/schema/solmobile-v0-domain.yaml`
