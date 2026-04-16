#!/bin/sh
# completed-today.sh — Read reminders marked complete between midnight today and now.
# Change `set dayStart to dayStart - 1 * days` to read yesterday.
#
# Output: ListName|TaskName

osascript <<'APPLESCRIPT'
tell application "Reminders"
    set dayStart to current date
    set hours of dayStart to 0
    set minutes of dayStart to 0
    set seconds of dayStart to 0
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
end tell
APPLESCRIPT
