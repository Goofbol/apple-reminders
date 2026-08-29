# Apple Reminders: Cleanup Pass Protocol

Reference file. Load when running an audit, reshuffle, or hygiene workflow. Operational patterns are in [../SKILL.md](../SKILL.md).

---

## Cleanup Pass Protocol (audit and reshuffle workflows)

A cleanup pass covers duplicate detection, missing due dates, day-overloads, time-stacks, and stale far-future items across every configured list. If this skill is used from within an agent that supports a plan/execute/verify split (a planning pass followed by a separate execution pass), run cleanup that way. If it is used as a plain script, the same four phases still apply, just done in sequence by hand.

### Phase 1: Read

1. Run the Batch Read fast pattern: full state, all lists, all open reminders.
2. Run the Validation Script: NO-DUE-DATE, OVERDUE-7D+, FAR-FUTURE flags.
3. Run the Duplicate Check and the Name-Collision Check.
4. Build an issue list or table, sorted by severity:

| Severity | Issue | Example |
|---|---|---|
| Hard | NO-DUE-DATE | A task with no due date at all |
| Hard | Past-due more than 7 days | A task overdue by two weeks |
| Medium | Duplicate within a list | Two near-identical task names in the same list |
| Medium | Time-stack (4+ same time) | Five reminders all due at 22:00 on the same day |
| Medium | Day-overload (8+ items) | A single day with 13 items due |
| Medium | Name collision | A shift or complete matched more items than expected |
| Low | Scattered logical group | Related items split across two lists with no flag |
| Low | FAR-FUTURE (more than a month out) | A task due many months from now with no clear reason |

### Phase 2: Decide

Apply small, obvious fixes automatically, and note them in the output:
- Pair logically related items onto the same date if they were clearly meant to happen together.
- For a NO-DUE item, propose a sensible default date.
- Drop clearly-stale far-future placeholder dates.

Ask for a decision only on:
- Duplicate resolution (which to keep, which to complete).
- Name-collision resolution (which of the matched reminders was actually meant).
- Day-overload trim (which items move off a heavy day).
- Time-stack staggering (which items to spread out).
- A NO-DUE date assignment when there is no sensible default.

Batch these questions into as few prompts as possible rather than asking one at a time.

### Phase 3: Execute

One batched osascript call applying every approved shift, complete, or create. Never one call per operation, both for performance and because a partial failure mid-batch is much easier to reason about when the batch itself is small and deliberate rather than an unbounded stream of individual calls.

### Phase 4: Verify

1. Run a fresh Batch Read query.
2. Show a confirmation table (list, name, due) built from that fresh read, not from what was intended.
3. Print a one-line summary: `N shifts, M completes, K flags resolved`.

### Cleanup Pattern: Example

```
Request: "clean up my reminders"

Phase 1:
- Reads all open reminders across every configured list
- Finds: 1 NO-DUE, 2 duplicates, 1 time-stack (5 at 22:00 today), 1 day-overload (13 items on one day)

Phase 2:
- Auto: pairs two logically related items onto the same date
- Auto: assigns a sensible default date to the NO-DUE item
- Asks: which of the two duplicates to keep? which items to move off the overloaded day?

Answers come back in one round.

Phase 3:
- One osascript call: shifts, completes, creates

Phase 4:
- Fresh query
- Confirmation table shown
- Summary: "5 shifts, 1 complete, 3 flags resolved"
```
