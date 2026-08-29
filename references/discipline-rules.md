# Apple Reminders: Hard Rules and Discipline

Reference file. Load when full rule text or rationale is needed. Operational patterns and list routing are in [../SKILL.md](../SKILL.md).

---

## The Write Gate

If this skill is wired into an automated or agent-driven flow, the safest default is: no reminder write of any kind (create, complete, shift, or delete) runs without an explicit human confirmation in the current interaction. A clarifying question back from the human is not consent. A ticked reminder in the app is a signal of intent, not authorisation to write somewhere else on their behalf. A read-only status check is the only operation that should ever run unprompted.

This rule exists because it is easy for an agent that is merely describing what a sync or automation *could* do to instead run it, especially in a long conversation where "should this exist" and "should this run right now" get blurred together. If you are wiring this skill into any agent loop, build this gate in explicitly rather than assuming good judgment will catch it every time.

---

## Hard Rules

> **Locale bug, why date arithmetic matters:**
> AppleScript interprets raw date strings like `"16/9"` based on the system locale, causing month/day flips and year miscalculation depending on where the machine is configured.
>
> Never use `set due date of r to date "MM/DD/YYYY"` or any raw date string. Always use `(current date) + N * days` arithmetic.

1. **No past dates.** Never create a reminder with a due date before today. If the calculated date is in the past, reject and flag.
2. **Sanity cap on future dates.** Cap due dates at a reasonable horizon (for example 30 days) unless the caller explicitly opts out, far-future dates are usually a bug.
3. **Every reminder should have a due date.** An undated reminder is a wish, not a task. Reject or flag creates that omit one.
4. **Date arithmetic only.** Always use `(current date) + N * days`, never raw date strings. This eliminates dd/mm vs mm/dd format errors entirely.
5. **Day name wins.** When a day name and a date conflict, trust the day name.
6. **Check before creating.** Before creating a reminder, check for an existing reminder with the same name in the target list. Prevent duplicates.
7. **Prefix conventions (optional).** If multiple agents share the same list, adopt a prefix convention so each knows which items are theirs. Use whatever convention your workflow needs, this skill does not enforce any specific one.
8. **Complete, never delete.** Use `set completed of r to true` to finish tasks. Never delete unless explicitly asked. Completed reminders remain in history and can be audited.
9. **Moving between lists** means delete from source and create in target, the API has no move operation.
10. **Always stagger by time.** Never set all reminders on the same day to the same time. Stagger due times across the day based on context.

---

## Name-Collision Rule

Matching a reminder by a name fragment is convenient and risky at the same time: two reminders that share a common prefix or a recurring project name can both match a fragment that was meant to identify one specific item. If the fragment is under-specified, a shift or complete helper can silently act on the wrong reminder, or on both.

Match on the most distinguishing fragment available, never a shared prefix that multiple reminders could plausibly contain. Every helper that shifts or completes reminders by name matching should report the matched count before acting. A count above 1 where exactly 1 was expected is not a partial success, it is a collision: stop and surface it rather than acting on the first match or all matches.

If your reminders tend to accumulate related-but-distinct items under a recurring project or client name, that family is the one most at risk of a collision, be more specific with the match fragment for those in particular, or preview the match set first (see the Name-Collision Check script in [validation-scripts.md](validation-scripts.md)).

---

## Planning-Session Discipline

These rules apply on top of the Hard Rules whenever this skill is used inside a longer planning or review conversation, rather than a single one-off command. The failure mode this prevents: an agent plans a task in conversation as "part of this session's work" instead of creating a reminder for it, and later claims the reminder exists without having actually queried Reminders to check.

1. **Every named task becomes a reminder, immediately.** The moment a task is named in conversation, create or verify the reminder. Do not defer it to "this session's plan," that framing is itself the failure mode.

2. **Query-then-show-back after every write.** After any create, shift, delete, or complete, run a fresh Batch Read query and show a confirmation table or list with columns list, name, due. The output should match exactly what the user will see when they open the app.

3. **No inference about state.** If Reminders has not been queried this turn, its state cannot be claimed. "Done" without a fresh query is a lie, however confidently it is stated.

4. **Flag scattered lists.** If reminders for the same logical group end up across multiple lists, surface it explicitly, a view filtered to one list may not show them together.

5. **Flag time-stacks.** When 4 or more reminders share the same due time on the same day, surface the stack so the load is visible and can be staggered or trimmed.

6. **Flag day-overloads.** When a single day has more than 8 items due, surface the count and propose trims.

7. **Flag missing due dates loudly.** Never skip a missing due date silently. Surface it and propose a sensible default, ask if uncertain.

8. **Confirmation format (after any write):**

```
| # | Reminder | List | Due |
|---|---|---|---|
| 1 | <name> | <list> | <day> <date> <time> |
```

Show this every time a write happens in a planning-style session. No exceptions.

---

## Stagger and Load Guidance

Stagger every batch, never repeat a due time across multiple reminders written in the same call. If a carry-over process is rescheduling several overdue items at once, offset each by a few minutes (`+5`, `+10`, `+15`) rather than landing them all on the same clock time.

When a single day accumulates 8 or more items, propose a trim in the same output that surfaces the overload rather than deferring the decision to a later session. If a rolling backlog keeps regenerating unchanged across multiple runs, that is a signal to force an explicit categorisation decision rather than restacking the same pile again.
