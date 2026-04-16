#!/bin/sh
# batch-read.sh — Read all open reminders across configured lists
#
# Output: ListName|TaskName|YYYY-MM-DDTHH:MM  (one line per reminder)
#
# Uses the fallback (try-wrapped) pattern, which is slightly slower than the
# fast path but handles reminders without due dates gracefully.

osascript <<'APPLESCRIPT'
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
end tell
APPLESCRIPT
