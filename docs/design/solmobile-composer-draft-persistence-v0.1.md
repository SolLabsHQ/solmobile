# SolMobile Composer Draft Persistence + Restoration (v0 → v0.1)

## Intent
Prevent loss of in-progress message drafts when:
- app backgrounds
- OS kills the app
- app crashes
- user switches threads and returns

Goal UX:
- returning to a thread restores the draft automatically in the composer
- minimal cognitive overhead for the user ("it just works")
- deterministic cleanup when a draft is sent or cleared

Non-goals (v0.x)
- multiple drafts per thread
- cross-device sync of drafts
- rich attachment draft persistence (optional later)

---

## User stories
1) As a user, if I type a long message and background the app, I want the text still there when I return.
2) As a user, if the app is killed, I want my draft restored when I reopen the thread.
3) As a user, once I successfully send a message, I do not want old draft text to reappear.
4) As a user, I want a simple way to discard a recovered draft.

---

## Data model (local-first)
### DraftRecord
- draft_id: UUID
- thread_id: UUID
- content: String (raw text as typed)
- updated_at: Date
- cursor_start: Int? (optional)
- cursor_end: Int? (optional)
- last_sent_message_id: UUID? (optional; helps guard stale restore)

Storage options:
- v0: SQLite table (preferred) OR CoreData entity OR small file-per-thread
- Must be synchronous-safe on background save (no long transactions)

---

## Save triggers (reliability over cleverness)
We persist draft text through three mechanisms:

1) Debounced autosave while typing:
- Save ~700ms after the last keystroke.
- Also enforce a max-interval save (e.g., every 10 seconds) as a safety net.

2) Background hard save:
- On sceneWillResignActive / sceneDidEnterBackground, save immediately.

3) Best-effort crash recovery:
- Draft exists from autosave/back-save; no special crash logic required.

Delete rules:
- If trimmed content is empty → delete DraftRecord for thread.
- On send success → delete DraftRecord for thread.

---

## Restore behavior
On thread open:
- Load DraftRecord for thread_id.
- Restore into composer if:
  - draft exists, AND
  - draft.updated_at is newer than the last successful send for that thread (if tracked), AND
  - user has not explicitly discarded it this session.

Optional UX:
- Show a subtle non-blocking banner:
  - "Recovered draft • <relative time>" [Discard]

If user taps Discard:
- clear composer
- delete DraftRecord

---

## Thread switching behavior
When user navigates away from the thread:
- ensure debounced save fires (or force-save on navigation event)
When user navigates back:
- restore draft (same logic)

---

## Implementation sketch (controller pattern)
Create a DraftController bound to a thread:
- onTextChanged(text, cursor) → debounced save
- onBackground(text, cursor) → immediate save
- onSendSuccess() → delete

The composer view owns:
- draft restore onAppear
- banner display
- discard action

---

## Observability (local only for v0.x)
Add lightweight logs/metrics (local):
- draft_saves_count
- draft_restores_count
- recovered_draft_discarded_count
- restore_age_seconds (distribution)

No content telemetry.

---

## Edge cases
- If a send fails: DO NOT delete draft.
- If user edits and then sends: delete draft after confirmed send.
- If cursor indices are out of range on restore: ignore cursor, restore content only.
- If thread_id changes due to migration: map old thread IDs if needed (future).

---

## Security / privacy
- Drafts are stored locally.
- Respect device lock; rely on iOS storage protection defaults (NSFileProtectionComplete unless app needs background access).
- No cloud sync in v0.x.

---

## Rollout plan
- v0: draft persistence + restore (no banner)
- v0.1: add banner + discard action + cursor restore (if stable)