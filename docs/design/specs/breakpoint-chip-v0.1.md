# SolMobile Spec: Breakpoint Chip (Permission Gate) (v0.1)

**Status:** Proposed  
**Owner:** Jam (Lead Dev + Chief Architect)  
**Goal:** Make “action needed” moments explicit, anchored, and consent-driven.  
**Non-goals:** Full tool execution UI, multi-step wizards, rich approvals beyond simple yes/no.

---

## Problem
When the assistant suggests an external action (e.g., create reminder, add calendar event), the app must:
- prevent “momentum capture” (assistant doing things without consent)
- make the decision point visible *in-context* (not buried in logs)
- allow “Not now” without penalty
- keep the thread readable (no huge forms)

This is the UI expression of the Explicit Decision Boundary.

---

## 4B Primitive

### Bounds
- The chip is a **UI gate**: it does not execute anything by itself.
- Only appears when the response explicitly declares `action_needed`.
- Chip supports only two decisions in v0.1:
  - **Approve**
  - **Not now**
- Any additional configuration is deferred (v0.2+).

### Buffer
- Default posture is calm and reversible:
  - “Not now” is always safe
  - Approval requires explicit tap
- Avoid repeated prompts for the same action unless the user re-asks.

### Breakpoints
1) Assistant response arrives with `action_needed` metadata
2) Chip renders inline and awaits user decision
3) User taps Approve / Not now
4) If Approve → actuate action flow (separate component), show success/failure result inline
5) If Not now → close chip (or leave collapsed) and record deferral

### Beat
- v0.1: small, consistent, low-friction
- v0.2+: optional expansion into detail/config

---

## UI Placement
- The Breakpoint Chip renders **inline at the bottom of the assistant message** that introduced the action.
- It stays attached to that message even as the thread grows.
- It does not float or detach (avoids “where did that prompt come from?”).

---

## Chip States

### State A: Collapsed (default)
**Purpose:** fast decision without blocking reading.

Content:
- Leading icon: small “permission” glyph (or subtle dot)
- Title: `Needs permission`
- Action label: `<ActionLabel>` (short)
- Buttons:
  - **Approve**
  - **Not now**

Example:
`Needs permission: Create Reminder   [Approve] [Not now]`

Rules:
- Collapsed by default.
- Does not auto-expand unless criteria met (see Auto-expand).

### State B: Expanded (details)
**Purpose:** explain what will happen, without turning into a form.

Expanded content (max height: 6–10 lines):
- `What will happen` (1–3 bullets, provided by server)
- `Tool / Target` (e.g., Reminders / Calendar) (optional)
- `Data used` (high-level, non-sensitive) (optional)
- `Why asking` (one line, optional)

Buttons stay present at bottom:
- **Approve**
- **Not now**

### State C: Approved (pending execution)
**Purpose:** show the action is being attempted.

UI:
- Replace buttons with:
  - `Approved` + spinner: `Creating…`
- Provide `Cancel` only if your actuation pipeline supports safe cancel (optional v0.1; default OFF).

### State D: Completed (success)
**Purpose:** close the loop with a durable receipt.

UI:
- `Done: <OutcomeSummary>` (one line)
- Optional: `View` deep-link (e.g., open Reminders/Calendar item) if available.
- Chip collapses into a small receipt pill:
  - `Reminder created` ✓

### State E: Completed (failed)
**Purpose:** preserve agency and offer retry.

UI:
- `Failed: <ShortReason>` (one line, human)
- Buttons:
  - **Retry**
  - **Dismiss**

---

## Auto-expand Heuristics (v0.1 minimal)
Auto-expand the chip only when ALL are true:
- App is foreground
- User is in the same thread
- User is not actively typing
- User is not fast-scrolling

Then:
- Expand to show **only the first line** of “What will happen” (micro-expand), not the full details, to avoid jumping the UI.

If any condition fails, remain collapsed.

---

## Data Contract (SolServer → SolMobile)

Required fields for the chip:
- `request_id` (for de-dupe and state linking)
- `action_needed: true`
- `action_id` (stable id for this suggested action, unique per response)
- `action_label` (short string shown in collapsed view)
- `action_kind` (enum/string: create_reminder, create_calendar_event, etc.)
- `action_summary_bullets` (1–3 short bullets, shown in expanded view)

Optional fields:
- `action_target` (e.g., "Reminders", "Calendar")
- `action_data_used` (1–2 phrases: "title, due date")
- `action_why` (one line: "You asked me to remind you tomorrow morning.")
- `action_payload_preview` (structured, for later v0.2 config; do not show raw in v0.1)

---

## Actuation Handoff (v0.1)
On Approve:
- SolMobile sends an actuation request:
  - `POST /v1/actions/execute` (or equivalent)
  - includes `action_id`, `request_id`, and any required user confirmation fields
- UI transitions to Approved/Pending state.

On Not now:
- SolMobile records a deferral locally:
  - `action_decision = deferred`
- No server call required unless you want analytics (default no).

---

## Telemetry (local-only v0.1)
No content, only counts:
- breakpoint_shown_count
- breakpoint_autoexpanded_count
- breakpoint_approved_count
- breakpoint_deferred_count
- breakpoint_retry_count
- breakpoint_success_count
- breakpoint_failed_count
- time_to_decision_ms (approved/deferred)

---

## Accessibility
- Buttons must be reachable and large enough.
- VoiceOver labels:
  - “Needs permission: <ActionLabel>”
  - “Approve”
  - “Not now”
- Expanded details should be read in a logical order (what/target/data/why).

---

## Acceptance Criteria
- Chip appears only when `action_needed` is present.
- User can approve or defer in one tap.
- Decision remains anchored to the originating assistant message.
- Approve produces an inline receipt (success/failure).
- No accidental execution without explicit tap.

---

## Open Questions
- Do we need “Snooze” (remind me later) as a third button? (likely v0.2)
- Should “Not now” collapse and hide, or remain visible as deferred receipt? (lean: show a small “Deferred” receipt)
- Should we allow editing fields before approval (time/date/title)? (v0.2+)