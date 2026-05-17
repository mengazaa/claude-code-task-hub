# Second Brain Task Hub

A Claude Code skill that sets up a local task management dashboard for your Obsidian vault.

## What it does

- **Web Dashboard** at `localhost:5555` — view, create, and manage tasks
- **Auto-capture** — tell Claude "do later", "remind me", or "add task" and it saves automatically
- **Copy Prompt** — one-click copy of task context for your next Claude session
- **Handoff tracking** — track inter-session handoff documents
- **Claude rule** — auto-installed rule teaches Claude to capture tasks from natural language

## Install

```bash
# Copy skill to Claude Code skills directory
cp -R . ~/.claude/skills/task-hub
```

Or install with one command:

```bash
git clone https://github.com/mengazaa/claude-code-task-hub.git ~/.claude/skills/task-hub
```

## Usage

In Claude Code, type:

```
/task-hub
```

Claude will run the setup script, install all files into your vault, and open the dashboard.

## Manual setup

If you prefer to run it manually:

```bash
# From your Obsidian vault root:
bash ~/.claude/skills/task-hub/scripts/setup.sh "$(pwd)"

# Start the server:
cd "_Others/Personal Tasks" && python3 task-server.py
```

Then open http://localhost:5555

## What gets installed

| File | Location | Purpose |
|------|----------|---------|
| `task-server.py` | `_Others/Personal Tasks/` | Python HTTP server (port 5555) |
| `dashboard.html` | `_Others/Personal Tasks/` | Web UI |
| `task-hub.json` | `_Others/Personal Tasks/` | Task data (JSON) |
| `task-hub.md` | `.claude/rules/` | Auto-capture rule |

## Requirements

- Python 3
- Obsidian vault
- Claude Code

## License

MIT
