# Apple Reminders: Common Mistakes

Reference file. Load when diagnosing failures, unexpected behavior, or a post-incident review. Operational patterns are in [../SKILL.md](../SKILL.md).

---

## Locale / Date-Parsing Bug

> AppleScript interprets raw date strings like `"16/9"` based on the system locale, causing month/day flips and year miscalculation.
>
> Never use `set due date of r to date "MM/DD/YYYY"` or any raw date string. Always use `(current date) + N * days` arithmetic.

This is the single most common root cause of wrong dates in any Reminders automation. No exceptions.

---

## -1743 and Automation Permission

-1743, "Not authorised to send Apple events," means macOS has explicitly denied Automation access. Under this error a create can fail silently, no exception is thrown to the user-visible output in some call paths, the reminder simply never appears, which makes it especially easy to miss.

What it means and where to look:

- -1743 is a denial, not a missing-grant prompt. macOS does not re-prompt once it has been denied, the permission has to be granted manually.
- The setting lives under System Settings, Privacy and Security, Automation, not under the Reminders pane. Automation lists each app that has asked to control another app, and the toggle for Reminders sits under the calling process's own entry.
- The process requesting access is the calling binary, not necessarily the terminal app hosting it. If a CLI tool or agent is invoking osascript, look for that tool's own process name in the Automation list, not "Terminal" or your terminal emulator.
- Grants are read at process launch. Toggling the permission on does not take effect in an already-running session, restart the session (or the app hosting it) before the grant applies.
- A full Automation permission reset (`tccutil reset AppleEvents` on macOS) clears every Automation grant on the machine, not just the broken one. Do not run it as a first troubleshooting step.

Fastest diagnosis: run a read-only sanity check, `osascript -e 'tell application "Reminders" to count of every reminder'`. If that returns a number, permission is fine and the bug is elsewhere. If it throws -1743 or hangs on a permission dialog, it is the Automation grant.

---

## Midnight-Rollover Worked Example

A planning session that runs past midnight is a common trigger for a specific date bug. Say a session starts at 11 PM and someone asks for a task "tomorrow." The agent computes `(current date) + 1 * days` early in the conversation, when the wall clock still reads the earlier day. If the write itself happens later, after the clock has rolled over past midnight, that same "+1" now lands on the day after the one that was meant, a full day late, and silently: no error is thrown, the write succeeds, it is just wrong.

The fix is Hard Rule 11: after any date write, re-read `weekday of` the due date object that was actually written and compare it to the day meant, not to an offset computed earlier in the conversation. Concretely:

```applescript
set targetDate to (current date) + 1 * days
-- ... set hours/minutes/seconds, write due date ...
return weekday of targetDate as string
```

If the intended day was Monday and this returns Tuesday, the write is wrong even though the arithmetic ran without error. When a specific weekday is named rather than a relative offset, prefer the named-weekday offset formula in Safe Date Setting over a relative "+1" guess, it is immune to the clock having moved during the conversation.

---

## Mistake Table

| Mistake | What happens | Fix |
|---------|----------------|-----|
| Raw date strings, locale flips | Dates parse differently depending on machine locale; years can jump silently | Date arithmetic only, `(current date) + N * days` (Hard Rule 4) |
| Docs that teach the banned recipe | A README, prompt, or instructions file recommends raw date strings somewhere else in the stack | Docs that teach a banned pattern are themselves the bug; keep one canonical source and point everything else at it |
| Midnight rollover | A late-night "+1 day" lands a day later than intended once the clock rolls over | Verify `weekday of` after every write; use the named-weekday offset formula for named days (Hard Rule 11) |
| Tasks discussed but no reminder created | A task gets planned in conversation and never actually written to Reminders, then "done" gets claimed without it existing | Every named task becomes a reminder immediately (Planning-Session Discipline) |
| Claiming state without a fresh read | Reminders state described from memory, not matching what the app actually shows | Query then show back after every write |
| Name collision on a shared fragment | A name-fragment match hits more than one reminder, the wrong one gets shifted or completed | Match on the most distinguishing fragment; report the matched count; a count above 1 stops the run |
| Every touch of a large list costs 20-30s | A full property read on a list of a few hundred items measures in the high-20-second range regardless of which property is read | Narrow with `whose` at source; set osascript timeouts to 300s, not the 120s default |
| Hoisting a `whose` result into a variable | `set m to (every reminder whose ...)` then `name of m` fails with -1728 | Repeat the `whose` clause inside each read |
| Mutating a `whose` collection while iterating | Setting `completed` inside a live `whose completed is false` loop dies with -1719 Invalid index past the first match | Snapshot to a plain list, then write |
| `whose completed is true` | Scans the full completed history, hangs past 300s | Never; read name/completed once, find the index in shell, address `reminder <index>` |
| Bare `try` around a per-list read | A real error looks identical to "empty list"; a sync built on that assumption creates duplicates | Fail loudly, no silent swallow |
| Reads empty or hang after a write burst | A read right after a batch write, or against a cold app, intermittently returns empty | Read in the foreground; on empty, `activate` plus `delay 1`, retry |
| Per-reminder repeat for reads | 30-60s for a full read via `repeat with r in allOpen` | Batch property access instead |
| `zeroPad(x)` called directly inside `tell` | AppleScript cannot resolve handler scope from inside a `tell` block | Call as `my zeroPad(x)` |
| Fast batch read crashes on a missing due date | "Can't get due date of reminder X" | Try-wrapped fallback emitting `NO-DUE` |
| Batch create with no dedup | Silently creates duplicates | Batch read first, filter client-side, create only survivors |
| Deleting to finish a task | Loses history, completion timestamp, audit trail | Complete, never delete |
| Everything scheduled at the same time | Carry-overs or a batch update leave several reminders with identical due times | Stagger; `+5`/`+10`/`+15` minute offsets on batch updates |
| Invented list names | A script references a list name that does not exist in the actual Reminders app | Configure the real list names once at the top of the skill and keep every pattern in sync with that |
| A weekday string baked into a title | The title reads "Monday task" but the reminder gets shifted to Wednesday, and the title never updates | No dates or weekdays inside titles |
| Dictation or paraphrase mis-named entities | A voice-to-text or loosely-summarised name diverges from the actual list or project name | Resolve entity names against known lists and terms before creating |
| A large batch of cleanup operations run directly, one call at a time | Errors compound across calls, a failure partway through is hard to reason about, and the whole thing needs re-running | Use the 4-phase cleanup protocol: read, decide, execute, verify, all writes in one batched call |
| A reminder ticked without the underlying work being done | State drifts from reality; un-completing loses the completion timestamp | Recreate with a corrected body rather than un-completing |
| A full-list dump used to answer a simple count question | Wastes tokens or round-trips computing something a pre-filtered read would answer directly | Filter at the AppleScript layer (see the Filtered Read pattern) rather than filtering client-side after a full read |
| Same logical group of reminders scattered across lists | Related items split across lists with no flag, so a filtered view misses some of them | Flag scattered lists explicitly |
| Comparing an overdue reminder's due date against the source system's raw (past) date | Reports drift, and re-writes the same value, every single run for as long as the item stays overdue | Compare against the clamped date (today, not the past source date) once an item is overdue |
