# SolMobile Roadmap (Release Cuts)

## Intent
Ship a **minimal but resilient** SolMobile client first, then expand capabilities without blowing up scope, cost, or trust.

This doc is the **version ladder**.
For the exact “what ships in v0”, see: [solmobile-v0.md](./solmobile-v0.md)

---

## v0 — Minimal, resilient daily driver
**Goal:** Text-first core loop that never loses user input and never double-sends.

### Must-have
- Text chat (no images, no voice)
- request_id per /v1/chat request (idempotent)
- Local outbox queue: pending → sent → acked
- Manual “Retry last send” (reuses same request_id; server dedupe)
- Thread + message local store with TTL cleanup (default 30d unless pinned)
- Pinned context reference (server-side template id/version/hash; client sends ref only)
- Capsule summary per thread (small, refreshed periodically)
- Explicit memory saves only (no auto long-term memory)
- Cost meter basics (tokens + estimated cost per request; daily totals)
- App Intents / Shortcuts (text)
  - Park Open Loop / Recheck Later → Apple Reminders item in Open Loops list
  - Quick capture → append to thread or create new thread

### Non-goals
- Images, voice, OCR, camera
- Streaming resume cursoring
- BYO private sources ingest
- Parental controls / kid profile / schoolwork safeguards

---

## v0.1 — Early hardening + one “wow”
**Goal:** Make connectivity behavior feel professional, plus add one major input modality.

### Add
- Automatic retry with backoff (still idempotent)
- Better connection-state UI (“sent…”, “reconnecting…”, “tap to retry”)
- Optional streaming (no resume requirement yet)

### Pick ONE
- Voice capture (on-device speech → text → review → send)
OR
- Images (attach/upload) as “experimental” with tight limits

---

## v1 — Baseline product quality
**Goal:** Trustable, observable, and ready for wider TestFlight.

### Add
- Streaming resume with cursor (true continuation after drop)
- More robust outbox (replay safety, exactly-once feel)
- Stronger cost controls
  - hard budgets per request (input/output token caps)
  - runaway thread guardrails + user-facing warnings

### BYO Private Sources (text/PDF)
**Default strategy:** BYO content (most legal + least brittle)
- Share-sheet ingest (text/PDF)
- On-device redaction
- User review + approve outbound payload
- Server stores summaries unless explicit Save

---

## v2 / v3 — Kids + schoolwork + parental safeguards
**Goal:** Kids can use it safely; academic integrity enforced.

### Add
- Kid profile (stricter defaults)
- Coach Mode for graded work (teach/hints/check attempts; no verbatim completion)
- SchoolworkIntegrityGate (server) with intent labels: practice | study | graded
- Parental notifications
  - If child attempts disallowed schoolwork help: notify parent with context + refusal summary
- On-device redaction + review becomes standard for child flows

### IP boundary rule
Implement these safeguards as SolOS Mobile features with generic naming and clean architecture boundaries.
Maintain KinCart–SolOS separation.