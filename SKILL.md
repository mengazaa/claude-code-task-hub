---
name: task-hub
description: Setup a complete Task Hub — local task dashboard with web UI, Python server, and Claude Code auto-capture rule. Use when setting up task management, task tracking, personal task dashboard, or when user says "setup task hub", "install task hub", "/task-hub".
---

# Task Hub

Sets up a local task management system with web dashboard, REST API, and Claude Code auto-capture.

## Usage

```
/task-hub
```

## Step 0: Timestamp

```bash
date "+%H:%M %Z (%A %d %B %Y)"
```

## Step 1: Check Prerequisites

```bash
python3 --version
```

If Python 3 is not found, tell user to install it first.

## Step 2: Detect Vault Root

```bash
VAULT_ROOT=$(pwd)
while [ "$VAULT_ROOT" != "/" ] && [ ! -d "$VAULT_ROOT/.obsidian" ]; do
  VAULT_ROOT=$(dirname "$VAULT_ROOT")
done
if [ ! -d "$VAULT_ROOT/.obsidian" ]; then
  echo "ERROR: Not inside an Obsidian vault."
fi
echo "Vault root: $VAULT_ROOT"
```

If no `.obsidian/` found, ask user to run from inside their Obsidian vault.

## Step 3: Run Setup

```bash
bash ~/.claude/skills/task-hub/scripts/setup.sh "$VAULT_ROOT"
```

This creates all files in the vault. If files already exist, the script skips them (safe to re-run).

## Step 4: Start Dashboard

```bash
cd "$VAULT_ROOT/_Others/Personal Tasks" && python3 task-server.py &
sleep 1
open http://localhost:5555 2>/dev/null || xdg-open http://localhost:5555 2>/dev/null || echo "Open http://localhost:5555 in your browser"
```

## Step 5: Confirm to User

```
Task Hub is ready!

  Dashboard:  http://localhost:5555
  Data file:  _Others/Personal Tasks/task-hub.json
  Rule file:  .claude/rules/task-hub.md

How to use:
  - Open dashboard in browser to view/add/complete tasks
  - Tell Claude "add task", "do later", "remind me" and it auto-captures
  - Press N in dashboard to create new task
  - Click "Copy Prompt" to paste task context into next Claude session

To start manually:
  cd "_Others/Personal Tasks" && python3 task-server.py
```

## Features

- **Auto-capture**: Say "do later", "remind me", "add task" and Claude writes to task-hub.json
- **Web dashboard**: Responsive UI at localhost:5555 with task cards, priority badges, handoff tracking
- **Copy Prompt**: One-click copy of self-contained prompt for fresh Claude session
- **Handoffs**: Track inter-session handoff documents
- **Keyboard shortcuts**: N = new task, Esc = close modal
- **Auto-refresh**: Dashboard polls every 10 seconds for changes from Claude
