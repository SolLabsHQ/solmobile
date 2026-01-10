# SolMobile v0 — Scope and Constraints

## Purpose

SolMobile v0 is a native iOS client designed to make SolOS usable in daily life while preserving user agency, clarity, and trust.

The goal of v0 is **not** feature completeness.
The goal is to validate the core interaction loop with explicit boundaries and minimal surface area.

--- 

## What SolMobile v0 IS

SolMobile v0 includes:

### 1. Text-first interaction
- Primary input is text
- Voice input may be explored later but is not required for v0
- No conversational “assistant persona” beyond tone defaults

### 2. Local-first threads
- Conversation threads are stored **on-device only**
- Threads are ephemeral by default
- No automatic server-side persistence of conversations

### 3. Explicit memory only
- No background or implicit memory capture
- Memory is saved **only** when the user explicitly chooses to save
- Saved memories are discrete, inspectable records

### 4. Time-bounded local storage
- Default thread TTL: **30 days**
- Expired, unpinned threads are automatically deleted
- Pinned threads persist locally until unpinned or deleted

### 5. Clear separation of concerns
- Client handles capture, display, and local storage
- Server handles inference, validation, and explicit memory storage
- No hidden state shared between client and server

### 6. Cost awareness
- Token usage is tracked per request
- User-visible cost meter shows:
  - Recent usage
  - Daily totals
- No silent or unbounded usage

### 7. Resilient connectivity (no “stuck reconnect”)
- Every request carries a **request_id** for idempotency
- The client maintains a **local outbox** with clear states: pending → sending → acked → failed
- A failed send is always recoverable via **Tap to Retry**
- Retrying reuses the same request_id; the server **dedupes** to prevent double-sends
- No infinite spinner states without a user action path

### 8. Minimal OS integration (Open Loops)
- A lightweight App Intent / Shortcut exists for **“Park Open Loop / Recheck Later”**
- Creates an Apple Reminders item:
  - Title: `Recheck: <thing>`
  - Notes:
    - `Need: <data trigger>`
    - `Then: <next action>`
- Targets an **Open Loops** (or **Waiting on Data**) list
- This is intentionally narrow: capture and offload only (no broad “actions” layer in v0)

### 9. Storage audit (Settings)
- A lightweight **Storage Audit** view exists in Settings
- Shows local storage stats at a glance:
  - Local DB size (approx)
  - Counts: threads, messages, outbox items, evidence records
  - TTL configuration (current defaults)
- Includes a manual **Run TTL Sweep** action
  - Clearly shows what would be deleted (preview) or what was deleted (result)
  - Never touches pinned threads

---

## What SolMobile v0 is NOT

SolMobile v0 explicitly excludes:

- Continuous background listening
- Passive memory accumulation
- Behavioral profiling
- Personality simulation or roleplay UI
- Email, messaging, or third-party app actions
- Automatic long-term context building
- Cloud-synced conversation history
- Images, camera capture, OCR, or attachment pipelines
- Voice capture / transcription (deferred; text-first is the v0 contract)
- Live web browsing or automated web retrieval
- BYO private/paywalled source ingestion (text/PDF share-sheet + redaction review) — deferred to later versions
- Kid profiles, schoolwork safeguards, or parental notification flows (V2/V3)
- Streaming resume with cursors (may arrive after v0 once the core loop is proven)

These are conscious exclusions, not missing features.

---

## Core Constraints

The following constraints are non-negotiable in v0:

- **Explicit user intent governs persistence**
- **Local state is disposable**
- **Server state is inspectable**
- **No silent data flows**
- **All memory has a clear lifecycle**
- **Idempotent sends (request_id) prevent duplicates**
- **Outbox-first delivery prevents message loss under bad networks**
- **Every failure state is visible and recoverable**

If a feature violates these constraints, it does not belong in v0.

---

## Success Criteria

SolMobile v0 is considered successful if:

- A user can conduct meaningful sessions without fear of hidden persistence
- Saved memories are deliberate, reviewable, and limited
- Thread cleanup happens automatically and predictably
- Usage and cost are understandable at a glance
- The system feels calm rather than intrusive

---

## Acceptance Checklist

SolMobile v0 is not “done” until these are true:

### Reliability
- Airplane mode mid-send does **not** lose the user’s typed message
- Retrying after reconnect does **not** duplicate messages (same request_id)
- App relaunch preserves pending outbox items and allows retry
- No “stuck reconnect” loops without a clear user action path

### Cost visibility
- Each response includes token usage metrics
- A basic cost meter shows recent usage and daily totals

### Data lifecycle
- Unpinned threads expire at 30 days and are deleted predictably
- Pinned threads survive TTL cleanup until unpinned or deleted
- A Storage Audit view exists (Settings) showing local DB size + counts (threads/messages/outbox/evidence)
- User can manually trigger a TTL sweep and see the result (pinned threads are never deleted)

---

## Open Questions (Deferred)

The following topics are intentionally deferred beyond v0:

- Voice-first interaction
- On-device ML inference
- Cross-device sync
- Advanced retrieval tuning
- Advanced automation and actions (beyond the narrow “Open Loops” reminder capture)

These will be revisited only after v0 proves its core loop.

---

## Status

This document defines SolMobile v0 scope.
Changes must be intentional and recorded.
