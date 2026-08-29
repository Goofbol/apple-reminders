# Apple Reminders: Validation Scripts

Reference file. Load during a morning or evening review, a hygiene pass, or any before-you-trust-the-output checkpoint. Operational patterns are in [../SKILL.md](../SKILL.md).

---

## Validation Rules

Run periodically to catch hygiene issues.

1. No task should have a due date more than 1 month from today
2. No task should have a due date in the past (flag for triage if overdue more than 7 days)
3. Every task should have a due date
4. No duplicate task names within the same list
5. Prefix-tagged tasks should be actionable by the intended agent

---

## Performance Limits, Measured

Measured against a live list of roughly 350 reminders while building a two-way sync against an external ticket system.

- **Every touch of the collection costs 20-30 seconds, regardless of which property is asked for.** Reading `name`, `completed`, or `due date` of every reminder on a list that size each measured in the high-20-second range independently. Three separate property reads therefore cost roughly a minute and a half total, because the cost is the traversal, not the property. Consequence: narrow with a `whose` clause at the source before reading anything, and set osascript timeouts to 300 seconds, not the 120-second default.
- **Per-reminder iteration (`repeat with r in allOpen`, reading properties inside the loop) costs 30-60 seconds** for a full read, because it makes one Apple Event round-trip per property per reminder rather than one per property per list.

## Mutation Constraints

- **A `whose` result cannot be hoisted into a variable and read from.** `set m to (every reminder whose name begins with "X")` followed by `name of m` fails with -1728: binding materialises a plain list of object references, and batch property access needs a live object specifier. Repeat the `whose` clause inside each read instead, it is still far cheaper than an unfiltered traversal.
- **Never mutate a `whose` collection while iterating it.** Setting `completed` on a member of `every reminder whose completed is false` re-evaluates the query and shifts every later index, it dies with -1719 Invalid index as soon as there is more than one match. Snapshot into a list first, then write:
  ```applescript
  set doomed to {}
  repeat with r in (every reminder whose completed is false)
      if (name of r) contains "TARGET" then set end of doomed to r
  end repeat
  repeat with r in doomed
      set completed of r to true
  end repeat
  ```
- **Avoid `whose completed is true` entirely.** It scans the full completed history and routinely hangs past 300 seconds. To touch a completed reminder, read `name`/`completed` of every reminder once, find the index in a script, then address `reminder <index>` directly.
- **Do not wrap a per-list read in a bare `try`.** A swallowed error is indistinguishable from "the list is empty," and any sync built on that will happily create duplicates. Let it fail loudly.

---

## Hygiene Validation Script

Flags FAR-FUTURE, OVERDUE-7D+, and NO-DUE-DATE across all lists.

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
- `OVERDUE-7D+`, overdue by more than 7 days, needs triage (break down, delegate, or kill)
- `NO-DUE-DATE`, missing due date, must be assigned one

---

## Duplicate Check Script

Detects reminders with duplicate names within the same list.

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

## Name-Collision Check

For any helper that matches by name (shift, complete, move), read the match count before writing. This script previews what a name fragment would match, without touching anything:

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

## Batch Read Fallback (Missing Due Dates)

When the fast pattern errors ("Can't get due date"), use this try-wrapped fallback. Slower but safe.

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

## Read Completed Reminders (Yesterday/Today)

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

## Before-You-Trust-the-Output Checklist

After any batch write (create, shift, complete), verify before declaring done:

1. Run Batch Read (from SKILL.md), confirm all expected reminders appear in the output.
2. Run the Hygiene Validation script, confirm no new NO-DUE-DATE or FAR-FUTURE flags were introduced.
3. Run the Duplicate Check, confirm no accidental duplicates came out of a batch-create.
4. Run the Name-Collision Check on any fragment matched during the write, confirm the count was 1 where 1 was expected.
5. Show a confirmation table built from that fresh read.

Never claim a write is done without a fresh query. See [common-mistakes.md](common-mistakes.md) for the failure patterns this guards against.
