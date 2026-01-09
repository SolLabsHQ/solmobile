# SolMobile Spec: Response Arrival Cues + Breakpoint Attention (v0.1)

**Status:** Proposed  
**Owner:** Jam (Lead Dev + Chief Architect)  
**Goal:** Make assistant response arrival *felt* (reliability + orientation) without turning SolMobile into a noisy notifier.  
**Non-goals:** Fancy animation, streaming token-by-token polish, cross-device sync behavior.

---

## Problem
Users often send a message and then:
- look away / close eyes waiting for response
- switch threads within the app
- background the app during a long response

We need cues that:
- confirm completion without forcing constant visual attention
- differentiate normal completion vs “action needed”
- respect quiet / avoid repeated interruptions

---

## 4B Primitive

### Bounds
- Foreground cues default to **haptics only**.
- Background cues default to **no notifications** for normal completions.
- Background notifications are **opt-in** and only for:
  - **Action needed** (Breakpoint required)
  - **Failed** (retry needed)
- No repeated cues for the same response completion.
- No sound by default.

### Buffer
- “Do not disturb” posture:
  - one cue per response completion
  - suppress cues while user is actively typing or fast-scrolling
  - delay slightly when user is interacting to avoid “buzz slap”

### Breakpoints
- Cue decision is evaluated at:
  1) Send initiated
  2) Response completed
  3) Breakpoint required (action needed)
  4) Failure / retry
  5) App foreground/background transition while pending

### Beat
- Minimal in v0.1:
  - one subtle completion haptic (foreground)
  - distinct subtle haptic when completion includes Breakpoint
  - in-app banner only when user is in a different thread
  - local notification only for action-needed/failed (opt-in)

---

## Definitions

### Thread / view states
- **Same thread:** user is viewing the conversation that initiated the request.
- **Different thread:** user is within SolMobile but not viewing the initiating conversation.
- **Background:** app not active (home/lock/other app).

### Request lifecycle states
- `pending` — request sent, awaiting server/provider
- `streaming` — partial response arriving (optional; v0.1 may not stream)
- `completed` — response finished successfully
- `completed_action_needed` — response finished and requires explicit user permission (Breakpoint)
- `failed` — response failed (network/server/validation)

### Interaction signals
- `user_interacting_typing` — user is typing in composer
- `user_interacting_scrolling_fast` — user is rapidly scrolling in a message list
- `last_user_input_at` — timestamp of last tap/scroll/type

---

## UX Components

### 1) Completion Cue (foreground)
**Purpose:** tell the user “it landed” without requiring eyes on screen.

- **Normal completion:** one light haptic
- **Completion + Breakpoint:** distinct light haptic (different pattern)

**Suppression / delay rules:**
- If `user_interacting_typing` OR `user_interacting_scrolling_fast` is true:
  - delay haptic by 300–700ms OR skip if interaction continues
- No repeated cues for the same `request_id`

### 2) In-app Banner (foreground, different thread)
**Purpose:** user is in SolMobile but not in the initiating thread.

Show a lightweight banner/toast:
- Title: `Response ready`
- Subtitle: conversation name / snippet
- Action: `Tap to jump`
- Optional: light haptic (setting-controlled; default OFF)

Banner does not appear if user is already in same thread.

### 3) Breakpoint Chip (inline permission gate)
**Purpose:** make “action needed” visible and anchored in the conversation.

When response includes `completed_action_needed`:
- Render a chip at bottom of assistant message:
  - `Needs permission: <ActionLabel>`
  - Buttons: **Approve** / **Not now**
- Tapping the chip expands “Details”:
  - What will happen (1–3 bullets)
  - Tool/action name
  - Data to be used (high level)
  - Why asking (one line)

**Auto-expand behavior:**
- If app is foreground and same thread AND user is not interacting:
  - auto-expand one extra line (“What will happen”) for discoverability

### 4) Failure State (retry)
On `failed`:
- Inline status pill near composer or message footer:
  - `Failed to send` / `Failed to fetch response`
  - Action: **Retry**
- Optional local notification if app backgrounded and user opted in to “failed” alerts.

### 5) Queued / Offline
If send occurs while offline OR request is queued:
- Status pill: `Queued`
- No notification by default
- Retry/resume happens automatically when connectivity returns (per existing design)

---

## Cue Policy Matrix

### A) App foreground, same thread
- On `completed`: haptic (light)
- On `completed_action_needed`: distinct haptic + breakpoint chip inline
- On `failed`: show inline failure + optional light haptic (TBD; default OFF)

### B) App foreground, different thread
- On `completed`: in-app banner “Response ready”
- On `completed_action_needed`: in-app banner “Action needed” + optional distinct haptic (TBD)
- On `failed`: in-app banner “Failed” + retry link

### C) App background
Default:
- On `completed`: no notification
- On `completed_action_needed`: local notification (opt-in)
- On `failed`: local notification (opt-in)

---

## Settings (v0.1 minimal)
Expose in Settings > Notifications/Cues:

1) **Completion haptic (foreground):**
- Off
- Same thread only
- Every completion (foreground)  ← recommended default for Jam-style usage

2) **Background notifications:**
- Off (default)
- Action needed + Failed
- All completions (power user; default OFF)

3) **Different-thread banner:**
- On (default)
- Off

---

## Data / API Hooks (SolServer → SolMobile)
SolMobile needs response metadata to decide cues:

Required fields (v0.1):
- `request_id` (for de-dupe)
- `status`: completed | completed_action_needed | failed
- If action needed:
  - `action_label` (e.g., "Create Reminder")
  - `action_kind` (enum/string)
  - `action_summary` (1–3 bullets max)
  - `action_payload_preview` (high-level; no sensitive details)

Optional:
- `estimated_cost_usd` (for cost meter)
- `audit` fields (pinned context hash/version, routeMode, etc.) for Details panel (future)

---

## Telemetry (local-only in v0.1)
Record minimal counts for tuning (no content):
- completion_haptic_fired_count
- completion_haptic_suppressed_count
- banner_shown_count
- notification_shown_count (background)
- breakpoint_present_count
- avg_time_to_completion_ms

---

## Acceptance Criteria
- User can reliably perceive response completion in same-thread foreground without looking.
- User can discover action-needed breakpoints without hunting.
- No repeated cues for same completion.
- Different-thread scenario produces an in-app banner that navigates back correctly.
- Background notifications only fire under opt-in rules.

---

## Open Questions
- Should `failed` fire a haptic in foreground by default? (lean no)
- Should breakpoint cue be stronger than normal completion? (lean distinct pattern only, not louder)
- Should “auto-expand one extra line” be always-on or gated by “user_waiting”? (v0.2)