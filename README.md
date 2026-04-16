# apple-reminders

A Claude Code / Codex CLI / pure-shell skill for managing Apple Reminders on macOS via `osascript`.

No MCP. No SDKs. No external services. Just safe, fast, reusable shell patterns.

## What's in here

| File | Purpose |
|------|---------|
| [`SKILL.md`](SKILL.md) | The skill itself — load into `~/.claude/skills/` or reference from any shell-driven workflow |
| [`scripts/remind.sh`](scripts/remind.sh) | Helper for creating one reminder with dedup + date-arithmetic safety |
| [`examples/`](examples/) | Stand-alone example scripts you can run directly |

## Why this exists

Raw `osascript` for Apple Reminders has three traps that bite everyone:

1. **Date parsing is locale-dependent.** `"16/9"` means different things on different machines. Even worse, AppleScript sometimes silently flips month/day rather than erroring.
2. **Per-reminder property access is O(n) Apple Events.** A naive `repeat` over 100 reminders takes tens of seconds. Batch property access does it in under a second.
3. **No native move between lists.** You have to delete + recreate, and if you don't preserve body/priority/due-date, you lose data.

The skill encodes fixes for all three, plus validation rules (overdue, duplicates, missing due dates) and hygiene conventions (complete-don't-delete, stagger-by-context, prefix-by-agent).

## Quick start

### 1. Grant Automation permission

The first time `osascript` touches Reminders, macOS prompts for permission. Click **OK**. If you miss it: **System Settings → Privacy & Security → Automation → [your terminal] → Reminders**.

### 2. Configure your list names

Edit the `listNames` array in `SKILL.md` (and any example script you use) to match your actual Apple Reminders lists. Default placeholder: `{"Work", "Personal", "Inbox", "Someday"}`.

### 3. Create your first reminder

```bash
sh scripts/remind.sh "Work" "Ship the feature" 1
```

This creates a reminder in the "Work" list, due tomorrow at 9:00 AM, with duplicate prevention.

### 4. Read all open reminders

```bash
sh examples/batch-read.sh
```

Output is pipe-delimited: `ListName|TaskName|YYYY-MM-DDTHH:MM`. Pipe into `grep`, `awk`, `cut` as needed.

## Using it as a Claude Code / Codex skill

### Claude Code

```bash
# Clone the repo into your skills folder
git clone https://github.com/Goofbol/apple-reminders.git ~/.claude/skills/apple-reminders
```

Claude Code auto-loads skills from `~/.claude/skills/`. Reference it in any session by name.

### Codex CLI

Follow your Codex skill-loading convention. The patterns are pure shell — no adaptation needed.

### Bare shell

Just copy the patterns from `SKILL.md` directly into your own scripts.

## Core principles

- **Date arithmetic only** — `(current date) + N * days`. Never raw date strings.
- **Complete, never delete** — completed reminders stay in history.
- **Batch over loop** — one osascript call per operation set, not one per task.
- **Named lists beat `every list`** — faster, deterministic, skips shared/subscribed list noise.
- **Stagger due times** — never pile all reminders at 9 AM.

Full rationale in [`SKILL.md`](SKILL.md).

## Compatibility

- macOS 14+ (Sonoma) — tested
- macOS 10.15+ (Catalina) — should work (completion date API added here)
- Requires `osascript` (built into macOS)
- Requires Apple Reminders app (built into macOS)

## Contributing

Pull requests welcome. If you find a bug or have a pattern to add, open an issue first and describe the use case.

## License

MIT — see [LICENSE](LICENSE).
