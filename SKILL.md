---
name: apple-reminders
description: Efficient Apple Reminders management via osascript — hard rules, fast patterns, validation, date safety. Drop into any Claude Code / Codex CLI / pure-shell workflow on macOS.
---

# Apple Reminders — osascript Skill

Manages Apple Reminders via `osascript` with a focus on:

- **Safety** — date arithmetic only (no locale-dependent string parsing), dedup checks, no silent deletes.
- **Performance** — batch property access, single osascript calls for multiple operations, named-list iteration (not `every list`).
- **Portability** — pure shell + osascript. No Claude-specific tools, no MCP, no external dependencies. Works the same in Claude Code, Codex CLI, or a bare terminal.

This skill works only on macOS (requires `osascript` + Apple Reminders).

---

## Prerequisites

### 1. Automation permission (first-run)

macOS blocks AppleScript access to Reminders until you grant it. The first `osascript` call that touches Reminders triggers a system prompt:

> "Terminal" wants access to control "Reminders". Allowing control will provide access to documents and data in "Reminders", and to perform actions within that app.

Click **OK**. You can revisit at:

> System Settings → Privacy & Security → Automation → [your terminal] → Reminders

If you automate this from a tool (e.g. Claude Code, Codex CLI, VS Code integrated terminal), each distinct host binary needs its own permission grant.

### 2. macOS & Reminders versions

Patterns here are verified against macOS 14+ (Sonoma) and the built-in Reminders app. `completion date` is available from macOS 10.15+ (Catalina).

### 3. Configured lists

All iteration patterns read from a hardcoded list taxonomy (see [Canonical Lists](#canonical-lists)). Configure once at the top and the rest of the skill uses it.

---

## Canonical Lists

All osascript patterns below assume this list taxonomy. Replace with your own list names. Update here first, then find-replace across every pattern in this file.

```applescript
set listNames to {"Work", "Personal", "Inbox", "Someday"}
```

If you rename a list in Apple Reminders, update this block AND every occurrence of the old name in the patterns below.

---

## List Routing (Example)

A routing table helps agents/scripts pick the right list. Define whatever fits your workflow. Example:

| List | Route to when... |
|------|-----------------|
| **Work** | Default for professional tasks |
| **Personal** | Life admin, errands, personal goals |
| **Inbox** | Unclassified captures — triage later |
| **Someday** | Nice-to-have, not time-bound |

There is **no list** called "Work" by default in Apple Reminders — create any lists you intend to use before running patterns that iterate them.

---

## Quick Create (Single Reminder)

For one-off reminders, use the helper script — it validates the list name, checks for duplicates, and uses date arithmetic:

```bash
sh scripts/remind.sh <list> <name> <days_from_now> [body]
```

Example:

```bash
sh scripts/remind.sh "Work" "Review PR #42" 1 "Frontend refactor, 300+ lines"
```

For multiple reminders in one session, use the **Batch Create** pattern (single osascript call) further below.

---

## Hard Rules

> **Locale bug — why date arithmetic matters:**
> AppleScript interprets raw date strings like `"16/9"` based on the system locale. On a US-locale machine, that's September 16. On an India-locale machine, that's September 16 OR 9 (sometimes it chokes). Raw date strings cause silent month/day flips and year miscalculation.
>
> **NEVER use `set due date of r to date "MM/DD/YYYY"` or any raw date string. ALWAYS use `(current date) + N * days` arithmetic.**

1. **No past dates.** NEVER create a reminder with a due date before today. If the calculated date is in the past, reject and flag.
2. **Sanity cap on future dates.** Cap due dates at a reasonable horizon (e.g. 30 days) unless the caller explicitly opts out — far-future dates are usually a bug.
3. **Every reminder should have a due date.** An undated reminder is a wish, not a task. Reject or flag creates that omit one.
4. **Date arithmetic only.** Always use `(current date) + N * days` — NEVER raw date strings. This eliminates dd/mm vs mm/dd format errors entirely.
5. **Day name wins.** When a user says a day name AND a date and they conflict (e.g. "Wednesday April 2" when April 2 is a Thursday), trust the DAY NAME.
6. **Check before creating.** Before creating a reminder, check for an existing reminder with the same name in the target list. Prevent duplicates. (Batch Create is an explicit exception — see caveat below.)
7. **Prefix conventions (optional):** If multiple agents share the same list, adopt a prefix convention so each knows which items are theirs:
   - `[AI]` = autonomous agent task
   - `[Bot]` = scripted task
   - No prefix = user does it manually
   Use whatever convention your workflow needs — the skill doesn't enforce any specific one.
8. **Complete, never delete.** Use `set completed of r to true` to finish tasks. NEVER delete unless explicitly asked. Completed reminders remain in history and can be audited.
9. **Moving between lists** = delete from source + create in target (Reminders has no native move API).
10. **Always stagger by time.** NEVER set all reminders on the same day to the same time (e.g. all at 9 AM). Stagger due times across the day based on context. If you have calendar access from another tool, fetch free-slot context and stagger around meetings — this skill is pure Reminders and has no calendar awareness, so Rule #10 is best-effort when used standalone.

---

## Batch Read: All Open Reminders (Fast Pattern)

This is the primary read pattern. One osascript call, all lists, pipe-delimited output. Uses batch property access (`name of every reminder`) instead of slow per-reminder iteration.

**Key insight:** `get name of every reminder whose completed is false` is MUCH faster than iterating with `repeat with r in allOpen` and accessing properties individually. Batch property access returns parallel lists, cutting multi-second reads down to sub-second.

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

**Output format:** `ListName|TaskName|YYYY-MM-DDTHH:MM` (ISO-compatible, zero-padded — safe for string sort and grep/awk/cut).

**Why this is fast:** Batch property access (`name of every reminder whose...`) makes one Apple Event call per property per list. The naive `repeat with r in allOpen` pattern makes one Apple Event call per property per reminder — O(n) vs O(1) per list.

**Fallback for missing due dates:** The fast path throws if any reminder lacks a due date (batch `due date of every reminder` can't return `missing value` cleanly). If some reminders legitimately have no due date, use the safer (slower) pattern:

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

**Why named lists beat `every list`:** Iterating named lists avoids Reminders resolving all list metadata (including shared/subscribed lists from iCloud). Targeting by name is faster and deterministic.

---

## Safe Date Setting

ALWAYS use offset arithmetic. Never construct a date from string components.

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
if diff = 0 then set diff to 7 -- same-day → next week
set targetDate to (current date) + diff * days
```

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

Priority values: `0` = none, `1` = high, `5` = medium, `9` = low.

---

## Batch Create (Multiple Reminders, Single Call)

Do NOT make one osascript call per task. Batch everything into a single call. Grouping multiple operations is critical for performance — each osascript invocation is a full process spawn.

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

**Important:** Each `set dN to baseDate` creates a COPY in AppleScript, so modifying hours/minutes on `d2` does not affect `d1`. Safe to reuse `baseDate`.

**Duplicate-check caveat (Rule #6 interaction):** Batch Create does NOT enforce Rule #6 dedup — it is a perf path that prioritizes single-call throughput. To prevent duplicates, run the Batch Read pattern first, filter names you intend to create against the already-open set, and pass only the survivors into Batch Create. The single-reminder helper script (`scripts/remind.sh`) still enforces dedup for one-off creates.

---

## Resilient Batch Create (Error-Tolerant)

If one reminder in a batch fails to create (bad list name, Reminders app glitch), the default Batch Create pattern kills the whole batch. This version wraps each operation in a `try` block and logs outcomes — useful for automation that must not lose the rest of the batch.

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

Recurrence strings are brittle — AppleScript's support for full RRule syntax varies across macOS versions. Test a pattern once in the Reminders GUI before relying on it in automation.

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

---

## Validation Rules

Run periodically (e.g. morning planning, evening wind-down) to catch hygiene issues.

1. No task should have a due date more than 1 month from today
2. No task should have a due date in the past (flag for triage if overdue > 7 days)
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
- `FAR-FUTURE` — due date more than 30 days out; verify intent
- `OVERDUE-7D+` — overdue by more than 7 days; triage (break down, delegate, or kill)
- `NO-DUE-DATE` — missing due date; must be assigned one

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

---

## Cross-Tool Compatibility

- All patterns use only `osascript` and standard shell — no MCP, no SDKs, no tool-specific APIs.
- Works identically in Claude Code, Codex CLI, a bare `bash`/`zsh` terminal, cron jobs, or shell scripts.
- Output is pipe-delimited for easy parsing (`cut -d'|' -f1,2,3`, `awk -F'|'`, or `grep`).
- All date operations use `(current date) + N * days` arithmetic — no locale-dependent formatting.
- Timezone is always the system's local timezone (what Reminders itself uses). No UTC conversion.

---

## Troubleshooting

**"Not authorized to send Apple events" error:**
Grant Automation permission to your terminal (System Settings → Privacy & Security → Automation).

**Reminders created but don't appear:**
Check iCloud sync status. Reminders app needs network + iCloud account signed in if your lists sync. Offline creates land locally and sync later.

**AppleScript timeout on large batches:**
Default Apple Event timeout is 120 seconds. For very large batches, wrap in:

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

MIT — see [LICENSE](LICENSE).
