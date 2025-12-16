# SolMobile Roadmap

**Definition:** Local/offline means **on-device SQLite + FTS5**, not SolServer.

This roadmap is the version ladder. ADRs are authoritative for decisions.
For the exact “what ships in v0”, see: `docs/solmobile-v0.md`.

---

## Principles (always true)

- **Local-first by default**: threads live on-device; server is not a required dependency for core UX.
- **Explicit memory only**: no passive capture, no hidden persistence.
- **Resilience first**: no message loss, no duplicate sends, no dead-end reconnect loops.
- **Cost visibility**: user can see usage; no silent runaway spend.
- **OS primitives over custom glue**: Reminders and Notes are first-class surfaces when we offload.

---

## v0 — Minimal, resilient daily driver (ship first)
See docs/solmobile-v0.md for the full v0 contract.

**Goal:** Prove the local-first capture loop with trust, clarity, and reliability.

**Scope (must-have)**
- Text-first interaction
- Local-first threads stored **on-device only**
- Explicit memory only (no implicit background memory capture)
- Default TTL for threads: **30 days**
  - Unpinned threads expire and delete predictably
  - Pinned threads persist until unpinned or deleted
- Clear separation of concerns
  - Client handles capture, display, local storage
  - Server handles inference/validation/explicit memory storage
  - No hidden shared state
- Cost awareness
  - token usage tracked per request
  - basic cost meter (recent usage + daily totals)
- Resilient connectivity (no “stuck reconnect”)
  - `request_id` idempotency for every request
  - local outbox queue: pending → sending → acked → failed
  - Tap to Retry always available
  - retry reuses `request_id` and server dedupes
- Minimal OS integration: **Open Loops**
  - Shortcut/App Intent: “Park Open Loop / Recheck Later”
  - Creates Apple Reminders item: `Recheck: <thing>` with `Need:` and `Then:` notes

**Explicitly out of scope**
- Search (local or server)
- Images, camera, OCR, attachment pipelines
- Voice capture / transcription
- Cloud-synced conversation history
- BYO private/paywalled source ingest (share-sheet text/PDF + redaction) — deferred
- Streaming resume with cursors
- Kid profiles / schoolwork safeguards / parental flows

---

## v0.1 — Search + re-entry (ADR-018)

**Goal:** Add reliable on-device finding and re-entry.

- SQLite **FTS5** global search (on-device)
- Deep-link to exact `message_id`
- In-thread Find (next/prev with match count)
- Return Stack: “Back to where I was” when search invoked inside a thread

---

## v0.2 — Retention foundations (ADR-019)

**Goal:** Scale storage predictably as data grows (especially attachments).

- Pinning overrides TTL (enforced consistently)
- Attachments treated as primary storage driver (offload hooks)
- BackgroundTasks maintenance hooks:
  - FTS optimize
  - compaction and vacuum strategy
  - cache cleanup
- Thread cleanup & retention UX
  - Multi-select threads for bulk archive / delete
  - Quick action: archive threads older than X days (skip pinned)
  - Archived threads hidden from default view but remain searchable
  - Pinning overrides all auto-cleanup rules
  - Optional auto-archive / auto-delete policies (off by default)
  - Background maintenance aligns with retention rules
  - ADR-020 (future): Thread Retention & Bulk Cleanup UX

---

## v1.0 — Optional cold archive (ADR-019)

**Goal:** Enable long-term storage without making SolServer mandatory.

- Optional encrypted iCloud cold archive (CryptoKit + iCloud Drive app container)
- Local Archive Catalog for discoverability
- “Search iCloud archive” at end of results when online
- On-demand fetch and decrypt per thread

---

## v2 / v3 — Kids + schoolwork + parental safeguards (later)

**Goal:** Kids can use it safely; academic integrity enforced.

- Kid profile (stricter defaults)
- Coach Mode for graded work (teach/hints/check attempts; no verbatim completion)
- SchoolworkIntegrityGate (server) with intent labels: practice | study | graded
- Parental notifications for disallowed attempts
- On-device redaction + review becomes standard for child flows

**IP boundary rule**
Implement safeguards as SolMobile features with generic naming and clean architecture boundaries.
Maintain KinCart–SolOS separation.