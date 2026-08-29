#!/bin/sh
# write-reminder.sh: demonstrates the title/body convention and the
# weekday echo-back after a write.
#
# Title convention:
#   "Context: verb-led action"
#   Colon separator, not a dash. Under 80 characters. No dates or
#   weekdays inside the title, they go stale the moment the reminder
#   is shifted to a different day.
#
# Body convention:
#   At most three short lines: why it matters, who is involved, where
#   the detail lives (a file path or a ticket id). No headers, no
#   markdown, no em dashes.
#
# Weekday echo:
#   After creating, read the reminder back rather than assuming the
#   write landed, and print its actual weekday alongside its date.
#   This is the check that catches a midnight-rollover bug, where a
#   relative "+1 day" computed late at night lands on the wrong day
#   once the clock rolls over.
#
# Usage:
#   write-reminder.sh <list> <days_from_now>

set -eu

LIST="${1:-Work}"
DAYS="${2:-1}"

TITLE="Work: Review the quarterly numbers"
BODY="Deadline is end of week
Owner: finance lead
Detail: see the shared budget sheet"

osascript <<APPLESCRIPT
tell application "Reminders"
    tell list "$LIST"
        set dueDate to (current date) + $DAYS * days
        set hours of dueDate to 9
        set minutes of dueDate to 0
        set seconds of dueDate to 0
        make new reminder with properties {name:"$TITLE", due date:dueDate, body:"$BODY"}
    end tell
end tell
APPLESCRIPT

# Read it back and print the actual weekday, not an assumed one.
osascript <<APPLESCRIPT
tell application "Reminders"
    tell list "$LIST"
        set matched to every reminder whose name is "$TITLE" and completed is false
        if (count of matched) > 0 then
            set r to item 1 of matched
            set d to due date of r
            return "CREATED: " & (name of r) & " (due " & (weekday of d as string) & " " & (date string of d) & ")"
        else
            return "WARNING: reminder not found on read-back: $TITLE"
        end if
    end tell
end tell
APPLESCRIPT
