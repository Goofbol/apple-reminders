---
name: apple-reminders
description: Use when creating, reading, updating, completing, or validating Apple Reminders on macOS via osascript, including AppleScript date-parsing bugs (locale-dependent MM/DD flips), batch-read performance, carry-over scheduling, morning/evening planning runs, duplicate and name-collision detection, the -1743 Automation-permission trap, or any shell-driven reminder automation from Claude Code, Codex CLI, cron, or bare shell.
---

# Apple Reminders: osascript Skill

Manages Apple Reminders via `osascript` with a focus on:

- **Safety**: date arithmetic only (no locale-dependent string parsing), dedup checks, name-collision detection, no silent deletes.
- **Performance**: batch property access, single osascript calls for multiple operations, named-list iteration (not `every list`).
- **Portability**: pure shell plus osascript. No Claude-specific tools, no MCP, no external dependencies. Works the same in Claude Code, Codex CLI, or a bare terminal.

This skill works only on macOS (requires `osascript` plus the Apple Reminders app).

---

## When to Use

Triggers where this skill applies:

- Creating one or many reminders from shell, CLI, or automation
- Reading all open reminders across lists (morning planning, evening review)
- Updating due dates (carry-overs, reschedules)
- Marking reminders complete (single or batch)
- Validating hygiene (overdue more than 7 days, missing due dates, far-future creep)
- Catching duplicates and name collisions across lists
- Diagnosing "my reminder showed up on the wrong day" bugs, almost always locale-dependent date-string parsing
- Diagnosing silent create failures (-1743, an Automation permission problem)
- Migrating a reminder between lists (no native move API)
- Scheduling recurring tasks (daily standups, weekly reviews)
- Wiring Apple Reminders into Claude Code, Codex CLI, cron, or shell automation

**When NOT to use:**

- You need iOS-specific features (sharing, geofencing, Siri integration): those require Shortcuts, not osascript
- You're on Linux or Windows: osascript is macOS-only
- Your task system is something else (Linear, Jira, Todoist, Things): find the matching skill
- You want a rich interactive UI: use the Reminders app directly

---

## Prerequisites

### 1. Automation permission (first-run)

macOS blocks AppleScript access to Reminders until it is granted. The first `osascript` call that touches Reminders triggers a system prompt:

> "Terminal" wants access to control "Reminders". Allowing control will provide access to documents and data in "Reminders", and to perform actions within that app.

Click OK. Revisit at System Settings, Privacy and Security, Automation, then the calling app, then Reminders.

If this is automated from a tool (a Claude Code or Codex CLI session, an IDE terminal), each distinct host binary needs its own permission grant, and the grant is read at process launch: toggling it on does not take effect in an already-running session, restart the session or the app hosting it.

### 2. macOS and Reminders versions

Patterns here are verified against macOS 14+ (Sonoma) and the built-in Reminders app. `completion date` is available from macOS 10.15+ (Catalina).

### 3. Configured lists

All iteration patterns read from a hardcoded list taxonomy (see Canonical Lists below). Configure once at the top and the rest of the skill uses it.

---

## Canonical Lists: configure these

All osascript patterns below assume a list taxonomy. Replace the placeholders with your own list names before using this skill for real. Update here first, then find-replace across every pattern in this file.

```applescript
set listNames to {"Work", "Personal", "Inbox", "Someday"}
```

If you rename a list in Apple Reminders, update this block and every occurrence of the old name in the patterns below.

---

## List Routing (Example)

A routing table helps agents or scripts pick the right list. Define whatever fits your workflow, this is only an example:

| List | Route to when... |
|------|-----------------|
| **Work** | Default for professional tasks |
| **Personal** | Life admin, errands, personal goals |
| **Inbox** | Unclassified captures, triage later |
| **Someday** | Nice-to-have, not time-bound |

There is no list called "Work" by default in Apple Reminders. Create any lists you intend to use before running patterns that iterate them.

---

## Adapt Your Scheduling Template

If you use this skill to plan a day or a week, keep your own working-hours profile somewhere near the top of your planning workflow (a table of windows to time-of-day, similar to a calendar's working-hours setting) and apply it whenever staggering a batch of due times. This skill has no opinion on what your day looks like; it only enforces that whatever profile you use gets applied consistently rather than re-derived from scratch each run.

---

## Writing a Reminder

**Title**: `Context: verb-led action`. Colon separator, not a dash. Under 80 characters. No dates or weekdays in the title, they go stale the moment the reminder is shifted to a different day. No trailing punctuation. Resolve entity names against your own roster or list of known terms before creating, rather than trusting raw dictation or a loose paraphrase.

Example: `Work: Review PR 42`.

**Body**: at most three short lines: why it matters, who is involved, where the detail lives (a file path or a ticket id). No headers, no markdown, no em dashes.

**Due date**: always by day arithmetic, `(current date) + N * days`, never a raw string. Echo the resulting weekday back after the write (see the Hard Rules below).

---

## Due-Time Semantics

Decide once what a due time means for the person you schedule for, write it down here, and apply it on every write. Measured on one operator's store (237 completions over three months): 74% of reminders were ticked after their due time, median 14 hours later, and due times clustered at the starts of their work blocks. For that operator the due time is where work starts, not where it must finish.

- If due time means start of the work window: never schedule backwards from a deadline; put the deadline in the body as words; set a client-visible deadline's reminder one or two days before the deadline itself.
- Spoken ranges ("3-4 pm", "12:30 to 1") become a due time at the start of the range with the duration in the body ("~1h").
- Most operators do not tick as they go. They report in the next planning run and the reminders get completed then, in batch. Ask "which of these are already done?" before proposing anything; a done item still open is normal, not an error.
- If they work from the board rather than the notification, stagger for a readable top-to-bottom plan, not for alert spacing.
- One or two days of carry-over is routine. The same item pulled forward a third day is the signal to cut, not to restack.

## Quick Create (Single Reminder)

For one-off reminders, use the helper script, it validates the list name, checks for duplicates, and uses date arithmetic:

```bash
sh scripts/remind.sh <list> <name> <days_from_now> [body]
```

Example:

```bash
sh scripts/remind.sh "Work" "Review PR 42" 1 "Frontend refactor, 300+ lines"
```

For multiple reminders in one session, use the Batch Create pattern further below.

---

## Hard Rules

> **Locale bug, why date arithmetic matters:**
> AppleScript interprets raw date strings like `"16/9"` based on the system locale. On a US-locale machine, that is September 16. On a different locale, that could be day 16 of September, or it could fail outright. Raw date strings cause silent month/day flips and year miscalculation.
>
> Never use `set due date of r to date "MM/DD/YYYY"` or any raw date string. Always use `(current date) + N * days` arithmetic.

1. **No past dates.** Never create a reminder with a due date before today. If the calculated date is in the past, reject and flag.
2. **Sanity cap on future dates.** Cap due dates at a reasonable horizon (for example 30 days) unless the caller explicitly opts out, far-future dates are usually a bug.
3. **Every reminder should have a due date.** An undated reminder is a wish, not a task. Reject or flag creates that omit one.
4. **Date arithmetic only.** Always use `(current date) + N * days`, never raw date strings. This eliminates dd/mm vs mm/dd format errors entirely.
5. **Day name wins.** When a user says a day name and a date and they conflict (for example "Wednesday April 2" when April 2 is a Thursday), trust the day name.
6. **Check before creating.** Before creating a reminder, check for an existing reminder with the same name in the target list. Prevent duplicates. (Batch Create is an explicit exception, see the caveat below.)
7. **Prefix conventions (optional).** If multiple agents share the same list, adopt a prefix convention so each knows which items are theirs, for example `[AI]` for an autonomous agent task, `[Bot]` for a scripted task, no prefix for a manual task. Use whatever convention your workflow needs, the skill does not enforce any specific one.
8. **Complete, never delete.** Use `set completed of r to true` to finish tasks. Never delete unless explicitly asked. Completed reminders remain in history and can be audited.
9. **Moving between lists** means delete from source and create in target, Reminders has no native move API.
10. **Always stagger by time.** Never set all reminders on the same day to the same time. Stagger due times across the day based on context. If you have calendar access from another tool, fetch free-slot context and stagger around meetings, this skill is pure Reminders and has no calendar awareness, so this rule is best-effort when used standalone.
11. **Midnight-rollover guard, verify the weekday after every write.** A late-night planning session can cross midnight. A blind `+1 * days` keyed to "tomorrow" said at 11 PM can land a day later than intended once the clock rolls over, a silent error with no thrown exception. After any date set, re-read `weekday of` the due date and confirm it matches the day meant. When a day name is given rather than a relative offset, compute the offset to that named weekday (see Safe Date Setting) instead of trusting a relative "+1" guess.
12. **No inference about state, query then show back.** After any batch shift, create, or complete, re-query and present a show-back list or table (list, name, due). Never claim what is in Reminders from memory, only from a fresh read this turn.
13. **Match on the most distinguishing fragment, never a shared prefix.** Any helper that shifts or completes reminders by name matching should report the matched count. A count above 1 where exactly 1 was expected is not a partial success, it is a name collision, stop and surface it rather than acting on the first or all matches.

---

## Batch Read: All Open Reminders (Fast Pattern)

This is the primary read pattern. One osascript call, all lists, pipe-delimited output. Uses batch property access (`name of every reminder`) instead of slow per-reminder iteration.

**Key insight**: `get name of every reminder whose completed is false` is much faster than iterating with `repeat with r in allOpen` and accessing properties individually. Batch property access returns parallel lists, cutting multi-second reads down to sub-second.

```bash
osascript -e '
on zeroPad(n)
    set s to n as string
    if (count of s) < 2 then set s to "0" & s
    return s
end zeroPad

tell application "Reminders"
    set output to ""
    set listNames to {"Work", "Personal", "Inbox", "Someday"}
    repeat with lName in listNames
        tell list lName
            set openNames to name of every reminder whose completed is false
            set openCount to count of openNames
            if openCount > 0 then
                set openDates to due date of every reminder whose completed is false
                repeat with i from 1 to openCount
                    set n to item i of openNames
                    set d to item i of openDates
                    set dStr to (year of d as string) & "-" & my zeroPad(month of d as integer) & "-" & my zeroPad(day of d) & "T" & my zeroPad(hours of d) & ":" & my zeroPad(minutes of d)
                    set output to output & lName & "|" & n & "|" & dStr & linefeed
                end repeat
            end if
        end tell
    end repeat
    return output
end tell'
```

**Output format**: `ListName|TaskName|YYYY-MM-DDTHH:MM` (ISO-compatible, zero-padded, safe for string sort and grep/awk/cut).

**Why this is fast**: batch property access makes one Apple Event call per property per list. The naive `repeat with r in allOpen` pattern makes one Apple Event call per property per reminder, O(n) versus O(1) per list.

**Reads return empty? Activate first.** After a burst of writes, or when Reminders has been idle, backgrounded reads intermittently return empty while the store is busy. Run reads in the foreground; if the first read comes back empty, prefix with `tell application "Reminders" to activate` plus `delay 1`, then retry.

### Performance and mutation limits, measured on a roughly 350-reminder list

1. Every touch of a list costs 20-30 seconds, whatever property you ask for. `name`, `completed`, and `due date` each measured in the high-20-second range on the same list; the cost is traversing the collection, not the property. Budget osascript timeouts at 300 seconds, not the 120-second default, and narrow with a `whose` clause at source before reading anything.
2. A `whose` result cannot be hoisted into a variable and read from. `set m to (every reminder whose name begins with "X")` then `name of m` fails with -1728: binding materialises a plain list of object references, and batch property access needs a live object specifier. Repeat the `whose` clause inside each read instead.
3. Never mutate a `whose` collection while iterating it. Setting `completed` on a member of `every reminder whose completed is false` re-evaluates the query and shifts every later index, it dies with -1719 Invalid index as soon as there is more than one match. Snapshot into a plain list first, then write:
   ```applescript
   set doomed to {}
   repeat with r in (every reminder whose completed is false)
       if (name of r) contains "TARGET" then set end of doomed to r
   end repeat
   repeat with r in doomed
       set completed of r to true
   end repeat
   ```
4. Avoid `whose completed is true` entirely, it scans the full completed history and routinely hangs past 300 seconds. To touch a completed reminder, read `name`/`completed` of every reminder once, find the index in shell or a scripting language, then address `reminder <index>` directly.
5. Do not wrap a per-list read in a bare `try`. A swallowed error reads as "the list is empty," and any sync built on that will happily create duplicates. Let it fail loudly.

**Fallback for missing due dates**: the fast path throws if any reminder lacks a due date (batch `due date of every reminder` cannot return `missing value` cleanly). If some reminders legitimately have no due date, use this slower pattern instead:

```bash
osascript -e '
on zeroPad(n)
    set s to n as string
    if (count of s) < 2 then set s to "0" & s
    return s
end zeroPad

tell application "Reminders"
    set output to ""
    set listNames to {"Work", "Personal", "Inbox", "Someday"}
    repeat with lName in listNames
        tell list lName
            set allOpen to every reminder whose completed is false
            repeat with r in allOpen
                set rName to name of r
                set dStr to "NO-DUE"
                try
                    set d to due date of r
                    set dStr to (year of d as string) & "-" & my zeroPad(month of d as integer) & "-" & my zeroPad(day of d) & "T" & my zeroPad(hours of d) & ":" & my zeroPad(minutes of d)
                end try
                set output to output & lName & "|" & rName & "|" & dStr & linefeed
            end repeat
        end tell
    end repeat
    return output
end tell'
```

**Why named lists beat `every list`**: iterating named lists avoids Reminders resolving all list metadata, including shared or subscribed lists from iCloud. Targeting by name is faster and deterministic.

---

## Safe Date Setting

Always use offset arithmetic. Never construct a date from string components.

```applescript
-- Today at a specific time
set targetDate to current date
set hours of targetDate to 9
set minutes of targetDate to 0
set seconds of targetDate to 0

-- N days from now
set targetDate to (current date) + N * days
set hours of targetDate to HH
set minutes of targetDate to MM
set seconds of targetDate to 0
```

**Calculating day offset from a weekday name:**

```applescript
-- Offset to next occurrence of a weekday (Sun=1, Mon=2, ..., Sat=7)
set today to weekday of (current date)
set todayNum to today as integer
set targetDayNum to 4 -- e.g. Wednesday
set diff to (targetDayNum - todayNum + 7) mod 7
if diff = 0 then set diff to 7 -- same-day -> next week
set targetDate to (current date) + diff * days
```

After every write, re-read `weekday of` the due date and confirm it matches the day meant, this is the check that catches the midnight-rollover bug described in Hard Rule 11.

---

## Create Reminder (Single)

```bash
osascript -e '
tell application "Reminders"
    tell list "LIST_NAME"
        set dueDate to (current date) + N * days
        set hours of dueDate to HH
        set minutes of dueDate to MM
        set seconds of dueDate to 0
        make new reminder with properties {name:"TASK_NAME", body:"NOTES", due date:dueDate, priority:PRIORITY}
    end tell
end tell'
```

Priority values: `0` for none, `1` for high, `5` for medium, `9` for low.

---

## Batch Create (Multiple Reminders, Single Call)

Do not make one osascript call per task. Batch everything into a single call. Grouping multiple operations matters for performance, each osascript invocation is a full process spawn.

```bash
osascript -e '
tell application "Reminders"
    set baseDate to current date

    tell list "Work"
        set d1 to baseDate
        set hours of d1 to 9
        set minutes of d1 to 0
        set seconds of d1 to 0
        make new reminder with properties {name:"Task A", due date:d1, priority:1}
    end tell

    tell list "Personal"
        set d2 to baseDate
        set hours of d2 to 10
        set minutes of d2 to 30
        set seconds of d2 to 0
        make new reminder with properties {name:"Task B", due date:d2, priority:5}
    end tell

    -- Add more tasks here in the same call
end tell'
```

**Important**: each `set dN to baseDate` creates a copy in AppleScript, so modifying hours or minutes on `d2` does not affect `d1`. It is safe to reuse `baseDate`.

**Duplicate-check caveat (Hard Rule 6 interaction)**: Batch Create does not enforce Rule 6 dedup, it is a perf path that prioritises single-call throughput. To prevent duplicates, run the Batch Read pattern first, filter names you intend to create against the already-open set, and pass only the survivors into Batch Create. The single-reminder helper script (`scripts/remind.sh`) still enforces dedup for one-off creates.

---

## Resilient Batch Create (Error-Tolerant)

If one reminder in a batch fails to create (bad list name, an app glitch), the default Batch Create pattern kills the whole batch. This version wraps each operation in a `try` block and logs outcomes, useful for automation that must not lose the rest of the batch.

```bash
osascript -e '
tell application "Reminders"
    set baseDate to current date
    set report to ""

    try
        tell list "Work"
            set d to baseDate
            set hours of d to 9
            set minutes of d to 0
            set seconds of d to 0
            make new reminder with properties {name:"Task A", due date:d, priority:1}
        end tell
        set report to report & "OK|Work|Task A" & linefeed
    on error errMsg
        set report to report & "FAIL|Work|Task A|" & errMsg & linefeed
    end try

    try
        tell list "Personal"
            set d to baseDate
            set hours of d to 10
            set minutes of d to 30
            set seconds of d to 0
            make new reminder with properties {name:"Task B", due date:d, priority:5}
        end tell
        set report to report & "OK|Personal|Task B" & linefeed
    on error errMsg
        set report to report & "FAIL|Personal|Task B|" & errMsg & linefeed
    end try

    return report
end tell'
```

Output format: `OK|ListName|TaskName` per success, `FAIL|ListName|TaskName|errorMessage` per failure. Downstream scripts can parse this to retry or alert.

---

## Recurring Reminders

Apple Reminders supports recurrence via the `recurrence` property. Valid values are RRule-style strings. Daily standup example:

```bash
osascript -e '
tell application "Reminders"
    tell list "Work"
        set d to (current date) + 1 * days
        set hours of d to 9
        set minutes of d to 30
        set seconds of d to 0
        make new reminder with properties {name:"Daily stand-up", due date:d, recurrence:"FREQ=DAILY;INTERVAL=1"}
    end tell
end tell'
```

Common recurrence strings:

| Pattern | RRule |
|---------|-------|
| Every day | `FREQ=DAILY;INTERVAL=1` |
| Every weekday | `FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR` |
| Every Monday | `FREQ=WEEKLY;BYDAY=MO` |
| Every 2 weeks | `FREQ=WEEKLY;INTERVAL=2` |
| 1st of each month | `FREQ=MONTHLY;BYMONTHDAY=1` |

Recurrence strings are brittle, AppleScript's support for full RRule syntax varies across macOS versions. Test a pattern once in the Reminders GUI before relying on it in automation.

---

## Complete a Reminder

```bash
osascript -e '
tell application "Reminders"
    tell list "LIST_NAME"
        set matchedReminders to every reminder whose name is "TASK_NAME" and completed is false
        repeat with r in matchedReminders
            set completed of r to true
        end repeat
    end tell
end tell'
```

Check `(count of matchedReminders)` before writing. A count above 1 where exactly one was expected is a name collision (Hard Rule 13), stop and confirm which reminder was meant rather than completing all matches.

---

## Batch Complete (Multiple Tasks, Single Call)

```bash
osascript -e '
tell application "Reminders"
    set pairs to {{"Work", "Task 1"}, {"Personal", "Task 2"}}
    repeat with p in pairs
        set lName to item 1 of p
        set tName to item 2 of p
        tell list lName
            set matched to every reminder whose name is tName and completed is false
            repeat with r in matched
                set completed of r to true
            end repeat
        end tell
    end repeat
end tell'
```

---

## Update Due Date (Carry-Over)

For tasks that already exist, update their due date instead of creating duplicates.

```bash
osascript -e '
tell application "Reminders"
    tell list "LIST_NAME"
        set matched to every reminder whose name is "TASK_NAME" and completed is false
        repeat with r in matched
            set newDate to (current date) + 1 * days
            set hours of newDate to HH
            set minutes of newDate to MM
            set seconds of newDate to 0
            set due date of r to newDate
        end repeat
    end tell
end tell'
```

Stagger every batch of carry-overs, never the same time twice in one call.

---

## Filter by Date Range

Reminders predicates are unreliable for date ranges. Fetch all, filter in-script.

```applescript
set rangeStart to current date
set hours of rangeStart to 0
set minutes of rangeStart to 0
set seconds of rangeStart to 0
set rangeEnd to rangeStart + 1 * days

tell list lName
    set allOpen to every reminder whose completed is false
    repeat with r in allOpen
        try
            set d to due date of r
            if d >= rangeStart and d < rangeEnd then
                -- include this item
            end if
        end try
    end repeat
end tell
```

---

## Read Completed Reminders (Date Range)

```bash
osascript -e '
tell application "Reminders"
    set dayStart to current date
    set hours of dayStart to 0
    set minutes of dayStart to 0
    set seconds of dayStart to 0
    -- For yesterday: set dayStart to dayStart - 1 * days
    set dayEnd to dayStart + 1 * days
    set output to ""
    set listNames to {"Work", "Personal", "Inbox", "Someday"}
    repeat with lName in listNames
        tell list lName
            set doneItems to (every reminder whose completed is true and completion date >= dayStart and completion date < dayEnd)
            repeat with r in doneItems
                set output to output & lName & "|" & name of r & linefeed
            end repeat
        end tell
    end repeat
    return output
end tell'
```

---

## Move Between Lists

No native move API. Delete from source, create in target.

```bash
osascript -e '
tell application "Reminders"
    tell list "SOURCE_LIST"
        set matched to every reminder whose name is "TASK_NAME" and completed is false
        if (count of matched) > 0 then
            set r to item 1 of matched
            set rBody to body of r
            set rPrio to priority of r
            set rDue to due date of r
            delete r
        end if
    end tell
    tell list "TARGET_LIST"
        make new reminder with properties {name:"TASK_NAME", body:rBody, due date:rDue, priority:rPrio}
    end tell
end tell'
```

Check `(count of matched)` on the source list before touching anything, more than one match is a name collision (Hard Rule 13), stop and confirm which one was meant.

---

## Validation Rules

Run periodically (morning planning, evening review, or any hygiene pass) to catch issues.

1. No task should have a due date more than 1 month from today
2. No task should have a due date in the past (flag for triage if overdue more than 7 days)
3. Every task should have a due date
4. No duplicate task names within the same list
5. Prefix-tagged tasks should be actionable by the intended agent

### Validation Script

```bash
osascript -e '
tell application "Reminders"
    set now to current date
    set maxDate to now + 30 * days
    set overdueThreshold to now - 7 * days
    set output to ""
    set listNames to {"Work", "Personal", "Inbox", "Someday"}
    repeat with lName in listNames
        tell list lName
            set allOpen to every reminder whose completed is false
            repeat with r in allOpen
                set rName to name of r
                set flag to ""
                try
                    set d to due date of r
                    if d > maxDate then set flag to "FAR-FUTURE"
                    if d < overdueThreshold then set flag to "OVERDUE-7D+"
                on error
                    set flag to "NO-DUE-DATE"
                end try
                if flag is not "" then
                    set output to output & flag & "|" & lName & "|" & rName & linefeed
                end if
            end repeat
        end tell
    end repeat
    return output
end tell'
```

Output flags:
- `FAR-FUTURE`, due date more than 30 days out, verify intent
- `OVERDUE-7D+`, overdue by more than 7 days, triage (break down, delegate, or kill)
- `NO-DUE-DATE`, missing due date, must be assigned one

### Duplicate Check

```bash
osascript -e '
tell application "Reminders"
    set output to ""
    set listNames to {"Work", "Personal", "Inbox", "Someday"}
    repeat with lName in listNames
        tell list lName
            set allOpen to every reminder whose completed is false
            set nameList to {}
            repeat with r in allOpen
                set rName to name of r
                if rName is in nameList then
                    set output to output & "DUPLICATE|" & lName & "|" & rName & linefeed
                else
                    set end of nameList to rName
                end if
            end repeat
        end tell
    end repeat
    return output
end tell'
```

### Name-Collision Check

For any helper that matches by name (complete, shift, move), preview the match count before writing:

```bash
osascript -e '
tell application "Reminders"
    set output to ""
    set listNames to {"Work", "Personal", "Inbox", "Someday"}
    repeat with lName in listNames
        tell list lName
            set matched to every reminder whose name contains "FRAGMENT" and completed is false
            set c to count of matched
            if c > 0 then
                repeat with r in matched
                    set output to output & lName & "|" & (name of r) & linefeed
                end repeat
            end if
        end tell
    end repeat
    return output
end tell'
```

Count the output lines before deciding to write. More than one line for a fragment expected to be unique is a collision, stop and confirm which reminder was meant.

---

## Common Mistakes

| Mistake | What goes wrong | Fix |
|---------|-----------------|-----|
| Raw date strings (`"10/5/2026"`) | Locale-dependent parsing flips MM/DD on different systems; years sometimes jump silently | Use `(current date) + N * days` arithmetic only |
| Piling reminders at 9 AM | All fire simultaneously, notification fatigue, nothing gets done | Stagger across the day (Hard Rule 10) |
| `repeat with r in allOpen` for property reads | 100 reminders means 100+ Apple Event round-trips; multi-second reads | Batch property access: `name of every reminder whose completed is false` |
| `delete r` to "finish" a task | Loses history, completion timestamp, audit trail | `set completed of r to true` (Hard Rule 8) |
| `repeat with L in every list` | Slow (resolves shared/subscribed lists), non-deterministic | Iterate a named-list constant, see Canonical Lists |
| Batch-create without pre-dedup | Silently creates duplicates, Hard Rule 6 is enforced by the single-create helper, not by batch | Run batch-read first, filter client-side, then batch-create survivors |
| Omitting a due date | Reminder becomes a permanent wish, never actionable | Every reminder should have a due date (Hard Rule 3); the validator flags NO-DUE-DATE |
| Fast-path batch-read crashes with "Can't get due date" | A reminder has no due date; the fast path cannot return `missing value` | Use the fallback (try-wrapped) pattern instead |
| Calling `zeroPad(x)` directly inside `tell application` | AppleScript cannot resolve handler scope from inside `tell` | Call as `my zeroPad(x)` |
| Same due time on every batched carry-over | User gets N simultaneous notifications at the reschedule boundary | Stagger minute offsets (`+5`, `+10`, `+15`) when batch-updating |
| A `whose` result hoisted into a variable | `set m to (every reminder whose ...)` then `name of m` fails with -1728 | Repeat the `whose` clause inside each read |
| Mutating a `whose` collection while iterating | Setting `completed` inside a live `whose completed is false` loop dies with -1719 past the first match | Snapshot to a plain list, then write |
| A name fragment matches more than one reminder | The wrong reminder gets shifted or completed | Match on the most distinguishing fragment; report the matched count; treat a count above 1 as a collision |

---

## Cross-Tool Compatibility

- All patterns use only `osascript` and standard shell, no MCP, no SDKs, no tool-specific APIs.
- Works identically in Claude Code, Codex CLI, a bare `bash`/`zsh` terminal, cron jobs, or shell scripts.
- Output is pipe-delimited for easy parsing (`cut -d'|' -f1,2,3`, `awk -F'|'`, or `grep`).
- All date operations use `(current date) + N * days` arithmetic, no locale-dependent formatting.
- Timezone is always the system's local timezone (what Reminders itself uses). No UTC conversion.

---

## Troubleshooting

**"Not authorized to send Apple events" error (-1743):**
This is a denial, not a missing-grant prompt. macOS does not re-prompt once it has been denied. Grant Automation permission at System Settings, Privacy and Security, Automation, then the calling process (the actual binary running osascript, not necessarily the terminal app hosting it). Grants are read at process launch, restart the session after granting. `tccutil reset AppleEvents` clears every Automation grant on the machine, not just the broken one, so it is a last resort, not a first troubleshooting step.

**Reminders created but don't appear:**
Check iCloud sync status. The Reminders app needs network and an iCloud account signed in if your lists sync. Offline creates land locally and sync later.

**AppleScript timeout on large batches:**
Default Apple Event timeout is 120 seconds, but a traversal of a few hundred reminders alone measures 20-30 seconds regardless of the property read, so budget higher. For very large batches, wrap in:

```applescript
with timeout of 600 seconds
    tell application "Reminders"
        -- long-running batch here
    end tell
end timeout
```

**Batch read fails with "Can't get due date of reminder X":**
Some reminder has no due date. Use the fallback pattern (with `try` wrapping on due date access) instead of the fast path.

---

## License

MIT, see [LICENSE](LICENSE).
