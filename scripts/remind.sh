#!/bin/sh
# remind.sh: Apple Reminders single-create helper
#
# Creates one reminder with:
#   Date arithmetic, never raw date strings
#   Duplicate check within the target list
#   List name validation against a configured set
#   Default due time of 9:00 AM
#   If NAME contains a space-em-dash-space, rewrites it to a colon before
#   creating, and says so on stdout, per the title convention in SKILL.md
#   Reads the created reminder back and prints name, list, and due date
#   with weekday, rather than assuming the write landed
#
# Usage:
#   remind.sh <list> <name> <days_from_now> [body]
#
# Examples:
#   remind.sh "Work" "Review PR 42" 1
#   remind.sh "Personal" "Dentist appointment" 3 "Dr. Smith, 2 PM"
#
# Configure:
#   Edit VALID_LISTS below to match your Apple Reminders lists.

set -eu

VALID_LISTS="Work Personal Inbox Someday"

LIST="${1:-}"
NAME="${2:-}"
DAYS="${3:-1}"
BODY="${4:-}"

if [ -z "$LIST" ] || [ -z "$NAME" ]; then
    echo "Usage: remind.sh <list> <name> <days_from_now> [body]" >&2
    exit 1
fi

# Validate list name
MATCHED=0
for L in $VALID_LISTS; do
    if [ "$L" = "$LIST" ]; then
        MATCHED=1
        break
    fi
done
if [ "$MATCHED" -eq 0 ]; then
    echo "ERROR: Invalid list '$LIST'" >&2
    echo "Valid: $VALID_LISTS" >&2
    exit 1
fi

# Validate days is a non-negative integer
case "$DAYS" in
    ''|*[!0-9]*)
        echo "ERROR: days_from_now must be a non-negative integer (got '$DAYS')" >&2
        exit 1
        ;;
esac

# Rewrite a space-em-dash-space title separator to the colon convention.
# The em dash (U+2014) is expressed as an escape here, not a literal
# character in this file, to keep source text free of the character itself.
EMDASH=$(printf '\342\200\224')
case "$NAME" in
    *" ${EMDASH} "*)
        OLD_NAME="$NAME"
        NAME=$(printf '%s' "$NAME" | sed "s/ ${EMDASH} /: /")
        echo "Title convention: renamed '$OLD_NAME' to '$NAME'"
        ;;
esac

# Check for duplicate, then create
osascript <<APPLESCRIPT
tell application "Reminders"
    set targetList to list "$LIST"

    -- Check for duplicate
    set isDuplicate to false
    repeat with r in (every reminder of targetList whose completed is false)
        if name of r is "$NAME" then
            set isDuplicate to true
            exit repeat
        end if
    end repeat

    if isDuplicate then
        return "SKIPPED: Duplicate exists: $NAME"
    end if

    -- Calculate due date
    set dueDate to (current date) + $DAYS * days
    set hours of dueDate to 9
    set minutes of dueDate to 0
    set seconds of dueDate to 0

    tell targetList
        if "$BODY" is "" then
            make new reminder with properties {name:"$NAME", due date:dueDate}
        else
            make new reminder with properties {name:"$NAME", due date:dueDate, body:"$BODY"}
        end if
    end tell
end tell
APPLESCRIPT

# Read the reminder back rather than assuming the write landed. This confirms
# the actual name, list, and due date with weekday, per Hard Rule 11
# (midnight-rollover guard) and Hard Rule 12 (query then show back).
osascript <<APPLESCRIPT
tell application "Reminders"
    tell list "$LIST"
        set matched to every reminder whose name is "$NAME" and completed is false
        if (count of matched) > 0 then
            set r to item 1 of matched
            set d to due date of r
            return "CREATED: " & (name of r) & " in $LIST (due " & (weekday of d as string) & " " & (date string of d) & ")"
        else
            return "WARNING: reminder not found on read-back: $NAME"
        end if
    end tell
end tell
APPLESCRIPT
