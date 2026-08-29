# apple-reminders

A Claude Code, Codex CLI, or pure-shell skill for managing Apple Reminders on macOS via `osascript`.

No MCP. No SDKs. No external services. Just safe, fast, reusable shell patterns.

## What's in here

| File | Purpose |
|------|---------|
| [`SKILL.md`](SKILL.md) | The skill itself, load into `~/.claude/skills/` or reference from any shell-driven workflow |
| [`references/`](references/) | Full rule rationale, common mistakes and incident-style write-ups, the cleanup protocol, and validation scripts with measured performance numbers |
| [`scripts/remind.sh`](scripts/remind.sh) | Helper for creating one reminder with dedup, date-arithmetic safety, title-convention rewriting, and a read-back confirmation |
| [`examples/`](examples/) | Stand-alone example scripts you can run directly |

## Why this exists

Raw `osascript` for Apple Reminders has traps that bite everyone:

1. **Date parsing is locale-dependent.** `"16/9"` means different things on different machines, and AppleScript sometimes silently flips month and day rather than erroring.
2. **Per-reminder property access is slow.** A naive loop over a few hundred reminders takes tens of seconds per property read. Batch property access does it in a fraction of the time.
3. **No native move between lists.** A move is really a delete and a recreate, and if body, priority, or due date are not carried over, data is lost silently.
4. **Automation permission failures are silent.** A denied Automation grant (error -1743) can make a create simply not happen, with no visible error in some call paths.
5. **Mutating what you are iterating breaks AppleScript in specific ways.** Setting a property on a member of a live `whose` query while iterating it fails with an index error as soon as there is more than one match.

The skill encodes fixes for all of these, plus validation rules (overdue, duplicates, missing due dates, name collisions) and hygiene conventions (complete-don't-delete, stagger-by-context, a consistent title and body shape).

## Quick start

### 1. Grant Automation permission

The first time `osascript` touches Reminders, macOS prompts for permission. Click OK. If it was missed or denied: System Settings, Privacy and Security, Automation, then the calling app, then Reminders. Grants are read at process launch, so restart the session after granting.

### 2. Configure your list names

Edit the `listNames` array in `SKILL.md` (and any example script you use) to match your actual Apple Reminders lists. Default placeholders: `{"Work", "Personal", "Inbox", "Someday"}`. This is marked "configure these" in `SKILL.md`, replace it before relying on this skill for anything real.

### 3. Create your first reminder

```bash
sh scripts/remind.sh "Work" "Ship the feature" 1
```

This creates a reminder in the "Work" list, due tomorrow at 9:00 AM, with duplicate prevention, and prints the reminder back with its actual weekday once the write completes.

### 4. Read all open reminders

```bash
sh examples/batch-read.sh
```

Output is pipe-delimited: `ListName|TaskName|YYYY-MM-DDTHH:MM`. Pipe into `grep`, `awk`, `cut` as needed.

### 5. See the title and body convention in practice

```bash
sh examples/write-reminder.sh "Work" 1
```

Creates a reminder using the `Context: verb-led action` title shape and a three-line body, then reads it back with its weekday.

## Using it as a Claude Code / Codex CLI / bare shell skill

### Claude Code

```bash
git clone <this-repo-url> ~/.claude/skills/apple-reminders
```

Claude Code auto-loads skills from `~/.claude/skills/`. Reference it in any session by name.

### Codex CLI

Follow your Codex skill-loading convention. The patterns are pure shell, no adaptation needed.

### Bare shell

Copy the patterns from `SKILL.md` directly into your own scripts, or call `scripts/remind.sh` and the `examples/` scripts as-is.

## Core principles

- **Date arithmetic only**, `(current date) + N * days`. Never raw date strings.
- **Complete, never delete**, completed reminders stay in history.
- **Batch over loop**, one osascript call per operation set, not one per task.
- **Named lists beat `every list`**, faster, deterministic, skips shared or subscribed list noise.
- **Stagger due times**, never pile all reminders at the same time.
- **Match on the most distinguishing fragment**, never a shared prefix; report the matched count; a count above one where one was expected is a collision, not a match.
- **Query then show back**, never claim what is in Reminders from memory, only from a fresh read.

Full rationale in [`SKILL.md`](SKILL.md) and [`references/`](references/).

## Compatibility

- macOS 14+ (Sonoma), tested
- macOS 10.15+ (Catalina), should work (`completion date` API added here)
- Requires `osascript` (built into macOS)
- Requires the Apple Reminders app (built into macOS)

## Contributing

Pull requests welcome. If you find a bug or have a pattern to add, open an issue first and describe the use case.

## Changelog

### 2026-08

Folded in a round of production-use learnings:
- Added the -1743 Automation-permission failure mode: what the error means, why it fails silently, where the permission actually lives, and why a session restart is required after granting it.
- Added name-collision detection: any helper matching by a name fragment now has guidance to report the matched count and treat a count above one as a stop condition, not a partial success, plus a preview script to check a match before writing.
- Added the title and body convention: `Context: verb-led action` with a colon separator instead of a dash, no dates or weekdays inside titles, and a three-line body shape (why it matters, who is involved, where the detail lives).
- Added the weekday echo-back: `scripts/remind.sh` and the new `examples/write-reminder.sh` now read a reminder back after creating it and print its actual weekday, catching the class of bug where a relative day offset lands on the wrong date once a session crosses midnight.
- Documented measured performance numbers from a sync job run against a roughly 350-item list: every touch of the collection costs 20-30 seconds regardless of which property is read, motivating the 300-second timeout guidance and the "narrow with `whose` before reading" rule.
- Documented the `whose`-collection mutation failure modes (-1728 for hoisting a filtered result into a variable, -1719 for mutating what you're iterating) with the snapshot-then-write pattern that avoids both.
- Added a write-gate note to the discipline reference for anyone wiring this skill into an autonomous or agent-driven flow: reads and status checks are safe to run unprompted, writes are not.

## License

MIT, see [LICENSE](LICENSE).
