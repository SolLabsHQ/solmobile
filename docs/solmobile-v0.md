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

These are conscious exclusions, not missing features.

---

## Core Constraints

The following constraints are non-negotiable in v0:

- **Explicit user intent governs persistence**
- **Local state is disposable**
- **Server state is inspectable**
- **No silent data flows**
- **All memory has a clear lifecycle**

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

## Open Questions (Deferred)

The following topics are intentionally deferred beyond v0:

- Voice-first interaction
- On-device ML inference
- Cross-device sync
- Advanced retrieval tuning
- Automation and actions

These will be revisited only after v0 proves its core loop.

---

## Status

This document defines SolMobile v0 scope.
Changes must be intentional and recorded.
