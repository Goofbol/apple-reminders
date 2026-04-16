#!/bin/sh
# validate.sh — Hygiene check across all configured lists
#
# Flags:
#   FAR-FUTURE    — due date more than 30 days out
#   OVERDUE-7D+   — overdue by more than 7 days
#   NO-DUE-DATE   — reminder without a due date
#
# Output: FLAG|ListName|TaskName

osascript <<'APPLESCRIPT'
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
end tell
APPLESCRIPT
