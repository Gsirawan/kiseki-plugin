# Kiseki Plugin

Persistent identity, real-time awareness, and cultural context for AI coding assistants. Supports both [OpenCode](https://github.com/opencode-ai/opencode) and [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Your AI starts every session knowing *who it is* and *when it is*. Time context updates with **every message** — if a conversation spans afternoon to evening, the AI knows.

## Features

| Feature | OpenCode | Claude Code |
|---------|----------|-------------|
| Foundation injection | Per-message (cached) | Session start |
| Time context (per-message) | Per-message | Per-message (`UserPromptSubmit`) |
| Hijri/Islamic calendar | Kuwaiti algorithm | Kuwaiti algorithm (bash) |
| Ramadan detection | Date ranges | Algorithmic (from Hijri month) |
| Dynamic reminders | File watcher + polling | Read on each message |
| Compaction preservation | Identity context | Identity context |
| Session briefing (scribe) | Ephemeral session | Not supported (use external tools) |

## Repository Structure

```
kiseki-plugin/
├── README.md
├── LICENSE
├── .gitignore
├── opencode/                    # OpenCode plugin (TypeScript)
│   ├── kiseki-oc-plugin.ts
│   ├── kiseki.json.example
│   └── package.json
└── claudecode/                  # Claude Code plugin (bash hooks)
    ├── .claude-plugin/
    │   └── plugin.json
    ├── hooks/
    │   └── hooks.json
    └── scripts/
        ├── session-start.sh     # Foundation file injection
        ├── user-prompt.sh       # Time + Hijri + reminders (19ms)
        └── pre-compact.sh       # Identity preservation
```

## OpenCode Installation

### 1. Clone and register

```bash
git clone https://github.com/Gsirawan/kiseki-plugin.git
```

Add to your `opencode.json`:
```json
{
  "plugins": [
    "/path/to/kiseki-plugin/opencode/kiseki-oc-plugin.ts"
  ]
}
```

### 2. Create project config

```bash
mkdir -p .opencode
cp /path/to/kiseki-plugin/opencode/kiseki.json.example .opencode/kiseki.json
```

See the `opencode/` directory for full OpenCode configuration reference.

## Claude Code Installation

### 1. Clone and register

```bash
git clone https://github.com/Gsirawan/kiseki-plugin.git
```

Add to `~/.claude/settings.json`:
```json
{
  "pluginDirs": [
    "/path/to/kiseki-plugin/claudecode"
  ]
}
```

### 2. Create project config

Create `.claude/kiseki.json` in each project where you want Kiseki active:

```json
{
  "foundation_paths": [
    "/path/to/your/identity.md",
    "/path/to/your/context.md"
  ],
  "timezone": "Asia/Dubai",
  "reminders_path": "~/list.md"
}
```

If the config file is absent, the plugin does nothing (safe for projects that don't use it).

### Claude Code Configuration Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `foundation_paths` | `string[]` | No | Absolute paths to files injected at session start. `~` is expanded. Missing files are skipped silently. |
| `timezone` | `string` | No | IANA timezone (e.g., `"Asia/Dubai"`, `"America/New_York"`). Defaults to `UTC`. |
| `reminders_path` | `string` | No | Path to a markdown file with reminders. Supports `~` and relative paths. Read fresh on every message. |

### Claude Code Hooks

| Hook | When | What |
|------|------|------|
| `SessionStart` | Once, at session start | Injects foundation files as system context |
| `UserPromptSubmit` | Every message you send | Injects fresh time context, Hijri date, Ramadan flag, and reminders |
| `PreCompact` | Before context compaction | Instructs the model to preserve identity and relational context |

## Time Context

Both plugins inject a block like this (updated every message):

```
<!-- KISEKI TIME CONTEXT -->
Current time: Thursday, March 19, 2026 at 11:05 AM (Asia/Dubai)
Period: morning
Islamic date: 30 Ramadan 1447 AH
🌙 Ramadan Mubarak - be mindful of fasting hours and spiritual context.
[your reminders here]
<!-- END KISEKI TIME CONTEXT -->
```

### Period of Day

| Hour Range | Period |
|------------|--------|
| 00:00–04:59 | late night |
| 05:00–11:59 | morning |
| 12:00–16:59 | afternoon |
| 17:00–20:59 | evening |
| 21:00–23:59 | night |

### Hijri Calendar

Calculated using the Kuwaiti/tabular algorithm. No external dependencies. Accurate to +/-1 day (appropriate since actual Islamic dates are determined by moon sighting).

### Reminders

Point `reminders_path` to any markdown file. Edit it any time — changes are picked up on the next message.

```markdown
Did you sit with your daughters for 30 minutes?
Check the deployment status
Remember to drink water
```

## Requirements

**OpenCode:** OpenCode with plugin support + Node.js runtime

**Claude Code:** Claude Code with plugin/hook support + `jq` + `date` with tzdata

## License

MIT
