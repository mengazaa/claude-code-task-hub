#!/usr/bin/env bash
# setup.sh — Second Brain Task Hub installer
# Usage: bash setup.sh <VAULT_ROOT>
# Idempotent: safe to re-run; skips files that already exist.

set -euo pipefail

# ── Arg check ────────────────────────────────────────────────────────────────
VAULT_ROOT="${1:-}"
if [ -z "$VAULT_ROOT" ]; then
  echo "Usage: bash setup.sh <VAULT_ROOT>"
  echo "  VAULT_ROOT = absolute path to the Obsidian vault root"
  exit 1
fi

TASK_DIR="$VAULT_ROOT/_Others/Personal Tasks"
RULE_DIR="$VAULT_ROOT/.claude/rules"

# ── 1. Create directories ───────────────────────────────────────────────────
echo "Creating directories..."
mkdir -p "$TASK_DIR"
mkdir -p "$RULE_DIR"

# ── 2. task-server.py ────────────────────────────────────────────────────────
if [ -f "$TASK_DIR/task-server.py" ]; then
  echo "task-server.py already exists — skipping"
else
  echo "Creating task-server.py..."
  cat > "$TASK_DIR/task-server.py" << 'PYEOF'
#!/usr/bin/env python3
"""Second Brain Task Hub — local HTTP server (port 5555)."""

import json
import os
import sys
from datetime import datetime, timezone
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

PORT = 5555
DIR = Path(__file__).resolve().parent
DATA = DIR / "task-hub.json"
DASH = DIR / "dashboard.html"


def _read_data():
    """Return the parsed JSON data, creating the file if needed."""
    if not DATA.exists():
        DATA.write_text(json.dumps({"tasks": [], "handoffs": []}, indent=2))
    return json.loads(DATA.read_text())


def _write_data(data):
    DATA.write_text(json.dumps(data, indent=2, ensure_ascii=False))


def _next_id(tasks):
    today = datetime.now(timezone.utc).strftime("%Y%m%d")
    existing = [t["id"] for t in tasks if t["id"].startswith(f"t-{today}-")]
    n = len(existing) + 1
    return f"t-{today}-{n:03d}"


class Handler(SimpleHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _json_response(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self._cors()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            body = DASH.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self._cors()
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/api/tasks":
            self._json_response(200, _read_data())
        else:
            self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw) if raw.strip() else {}
        except json.JSONDecodeError:
            body = {}

        path = self.path

        # POST /api/tasks — create new task
        if path == "/api/tasks":
            data = _read_data()
            now = datetime.now(timezone.utc).isoformat()
            task = {
                "id": _next_id(data["tasks"]),
                "title": body.get("title", "Untitled"),
                "status": "pending",
                "priority": body.get("priority", "medium"),
                "category": body.get("category", "work"),
                "created": now,
                "completed": None,
                "source": body.get("source", "dashboard"),
                "details": body.get("details", ""),
                "prompt": body.get("prompt", ""),
                "output": "",
            }
            data["tasks"].append(task)
            _write_data(data)
            self._json_response(201, task)
            return

        # POST /api/tasks/{id}/done
        if path.startswith("/api/tasks/") and path.endswith("/done"):
            tid = path.split("/")[3]
            data = _read_data()
            for t in data["tasks"]:
                if t["id"] == tid:
                    t["status"] = "done"
                    t["completed"] = datetime.now(timezone.utc).isoformat()
                    break
            _write_data(data)
            self._json_response(200, {"ok": True})
            return

        # POST /api/tasks/{id}/reopen
        if path.startswith("/api/tasks/") and path.endswith("/reopen"):
            tid = path.split("/")[3]
            data = _read_data()
            for t in data["tasks"]:
                if t["id"] == tid:
                    t["status"] = "pending"
                    t["completed"] = None
                    break
            _write_data(data)
            self._json_response(200, {"ok": True})
            return

        # POST /api/tasks/{id}/delete
        if path.startswith("/api/tasks/") and path.endswith("/delete"):
            tid = path.split("/")[3]
            data = _read_data()
            data["tasks"] = [t for t in data["tasks"] if t["id"] != tid]
            _write_data(data)
            self._json_response(200, {"ok": True})
            return

        # POST /api/handoffs/{id}/done
        if path.startswith("/api/handoffs/") and path.endswith("/done"):
            hid = path.split("/")[3]
            data = _read_data()
            for h in data.get("handoffs", []):
                if h.get("id") == hid:
                    h["status"] = "done"
                    h["completed"] = datetime.now(timezone.utc).isoformat()
                    break
            _write_data(data)
            self._json_response(200, {"ok": True})
            return

        self.send_error(404)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[TaskHub] {fmt % args}\n")


if __name__ == "__main__":
    _read_data()  # ensure file exists
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Task Hub running at http://localhost:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()
PYEOF
  chmod +x "$TASK_DIR/task-server.py"
fi

# ── 3. dashboard.html ────────────────────────────────────────────────────────
if [ -f "$TASK_DIR/dashboard.html" ]; then
  echo "dashboard.html already exists — skipping"
else
  echo "Creating dashboard.html..."
  cat > "$TASK_DIR/dashboard.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Second Brain Task Hub</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#f8faf8;--card:#fff;--border:#e2e8f0;--text:#1a202c;--muted:#64748b;
--green:#059669;--green-light:#d1fae5;--red:#dc2626;--red-light:#fee2e2;
--amber:#d97706;--amber-light:#fef3c7;--blue:#2563eb;--blue-light:#dbeafe;
--radius:12px;--shadow:0 1px 3px rgba(0,0,0,.08)}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
background:var(--bg);color:var(--text);line-height:1.5}
/* ── Header ─────────────────────────────────────── */
.header{position:sticky;top:0;z-index:100;background:var(--card);
border-bottom:1px solid var(--border);padding:16px 24px;
display:flex;align-items:center;justify-content:space-between;gap:16px}
.header-left{display:flex;align-items:center;gap:12px}
.header h1{font-size:20px;font-weight:700;letter-spacing:-.3px}
.pulse{width:8px;height:8px;border-radius:50%;background:var(--green);
animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
.clock{font-size:13px;color:var(--muted);font-variant-numeric:tabular-nums}
.btn{display:inline-flex;align-items:center;gap:6px;padding:8px 16px;
border-radius:8px;border:none;font-size:14px;font-weight:600;cursor:pointer;
transition:all .15s}
.btn-primary{background:var(--green);color:#fff}
.btn-primary:hover{background:#047857}
.btn-sm{padding:4px 10px;font-size:12px;border-radius:6px}
.btn-ghost{background:transparent;color:var(--muted)}
.btn-ghost:hover{background:#f1f5f9}
/* ── Stats ──────────────────────────────────────── */
.stats{display:flex;gap:12px;padding:16px 24px;flex-wrap:wrap}
.pill{display:flex;align-items:center;gap:6px;padding:6px 14px;
border-radius:20px;font-size:13px;font-weight:600;border:1px solid var(--border);
background:var(--card)}
.pill .num{font-size:16px}
/* ── Grid ───────────────────────────────────────── */
.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px;padding:0 24px 24px}
@media(max-width:800px){.grid{grid-template-columns:1fr}}
.col h2{font-size:15px;font-weight:700;margin-bottom:12px;color:var(--muted);
text-transform:uppercase;letter-spacing:.5px}
/* ── Cards ──────────────────────────────────────── */
.card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);
padding:14px 16px;margin-bottom:10px;box-shadow:var(--shadow);
transition:all .25s;position:relative}
.card.removing{opacity:0;transform:translateX(40px);max-height:0;
padding:0 16px;margin-bottom:0;overflow:hidden}
.card-top{display:flex;justify-content:space-between;align-items:flex-start;gap:8px}
.card-title{font-size:15px;font-weight:600;flex:1}
.card-title.done{text-decoration:line-through;color:var(--muted)}
.card-detail{font-size:13px;color:var(--muted);display:-webkit-box;
-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;margin-top:4px}
.badges{display:flex;gap:6px;margin-top:8px;flex-wrap:wrap}
.badge{font-size:11px;font-weight:700;padding:2px 8px;border-radius:4px;
text-transform:uppercase;letter-spacing:.3px}
.badge-high{background:var(--red-light);color:var(--red)}
.badge-medium{background:var(--amber-light);color:var(--amber)}
.badge-low{background:var(--blue-light);color:var(--blue)}
.badge-cat{background:var(--green-light);color:var(--green)}
.card-date{font-size:11px;color:var(--muted);margin-top:6px}
.card-actions{display:flex;gap:4px;margin-top:10px;flex-wrap:wrap}
/* ── Expand panel ───────────────────────────────── */
.expand{display:none;margin-top:12px;padding-top:12px;border-top:1px solid var(--border)}
.expand.open{display:block}
.expand h4{font-size:12px;font-weight:700;color:var(--muted);
text-transform:uppercase;margin-bottom:4px;margin-top:10px}
.expand h4:first-child{margin-top:0}
.expand p,.expand pre{font-size:13px;line-height:1.6}
.prompt-box{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;
padding:10px 12px;font-family:"SF Mono",Menlo,monospace;font-size:12px;
white-space:pre-wrap;word-break:break-word;color:#166534;max-height:200px;overflow-y:auto}
/* ── Completed section ──────────────────────────── */
.completed-section{padding:0 24px 40px;grid-column:1/-1}
.completed-toggle{display:flex;align-items:center;gap:8px;cursor:pointer;
font-size:14px;font-weight:600;color:var(--muted);margin-bottom:12px;
user-select:none}
.completed-toggle .arrow{transition:transform .2s;font-size:12px}
.completed-toggle .arrow.open{transform:rotate(90deg)}
.completed-list{display:none}
.completed-list.open{display:block}
.completed-list .card{opacity:.7}
/* ── Modal ──────────────────────────────────────── */
.overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.4);
z-index:200;align-items:center;justify-content:center}
.overlay.open{display:flex}
.modal{background:var(--card);border-radius:16px;width:90%;max-width:480px;
padding:24px;box-shadow:0 20px 60px rgba(0,0,0,.15)}
.modal h2{font-size:18px;font-weight:700;margin-bottom:16px}
.field{margin-bottom:14px}
.field label{display:block;font-size:13px;font-weight:600;margin-bottom:4px}
.field input,.field select,.field textarea{width:100%;padding:8px 12px;
border:1px solid var(--border);border-radius:8px;font-size:14px;
font-family:inherit;resize:vertical}
.field textarea{min-height:80px}
.modal-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:16px}
/* ── Empty state ────────────────────────────────── */
.empty{text-align:center;padding:32px;color:var(--muted)}
.empty-icon{font-size:32px;margin-bottom:8px}
.empty p{font-size:14px}
/* ── Full-width bottom ──────────────────────────── */
.full-width{padding:0 24px 40px}
</style>
</head>
<body>

<!-- Header -->
<div class="header">
  <div class="header-left">
    <div class="pulse"></div>
    <h1>Second Brain Task Hub</h1>
    <span class="clock" id="clock"></span>
  </div>
  <button class="btn btn-primary" onclick="openModal()">+ New Task</button>
</div>

<!-- Stats -->
<div class="stats">
  <div class="pill"><span class="num" id="stat-pending">0</span> Pending</div>
  <div class="pill"><span class="num" id="stat-handoffs">0</span> Handoffs</div>
  <div class="pill"><span class="num" id="stat-done">0</span> Done this week</div>
</div>

<!-- Grid -->
<div class="grid">
  <div class="col">
    <h2>Pending Tasks</h2>
    <div id="pending-list"></div>
  </div>
  <div class="col">
    <h2>Handoffs</h2>
    <div id="handoff-list"></div>
  </div>
</div>

<!-- Completed -->
<div class="full-width">
  <div class="completed-toggle" onclick="toggleCompleted()">
    <span class="arrow" id="comp-arrow">&#9654;</span>
    Completed this week
  </div>
  <div class="completed-list" id="completed-list"></div>
</div>

<!-- New Task Modal -->
<div class="overlay" id="modal-overlay" onclick="closeModalBg(event)">
  <div class="modal">
    <h2>New Task</h2>
    <div class="field">
      <label>Title</label>
      <input type="text" id="f-title" placeholder="What needs to be done?">
    </div>
    <div class="field">
      <label>Priority</label>
      <select id="f-priority">
        <option value="high">High</option>
        <option value="medium" selected>Medium</option>
        <option value="low">Low</option>
      </select>
    </div>
    <div class="field">
      <label>Category</label>
      <select id="f-category">
        <option value="work">Work</option>
        <option value="learning">Learning</option>
        <option value="content">Content</option>
        <option value="personal">Personal</option>
      </select>
    </div>
    <div class="field">
      <label>Details</label>
      <textarea id="f-details" placeholder="Context and background..."></textarea>
    </div>
    <div class="field">
      <label>Prompt</label>
      <textarea id="f-prompt" placeholder="Self-contained instruction for a fresh Claude session..."></textarea>
    </div>
    <div class="modal-actions">
      <button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
      <button class="btn btn-primary" onclick="createTask()">Create</button>
    </div>
  </div>
</div>

<script>
const API = 'http://localhost:5555';
let data = { tasks: [], handoffs: [] };

// ── Clock ───────────────────────────────────────────────────────────────────
function tickClock() {
  const d = new Date();
  document.getElementById('clock').textContent =
    d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) +
    '  ' + d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
}
tickClock();
setInterval(tickClock, 1000);

// ── Fetch & Render ──────────────────────────────────────────────────────────
async function load() {
  try {
    const r = await fetch(API + '/api/tasks');
    data = await r.json();
  } catch (e) { console.warn('fetch failed', e); }
  render();
}

function render() {
  const pending = data.tasks.filter(t => t.status === 'pending');
  const now = new Date();
  const weekAgo = new Date(now - 7 * 864e5);
  const done = data.tasks.filter(t => t.status === 'done' && new Date(t.completed) >= weekAgo);
  const handoffs = (data.handoffs || []).filter(h => h.status !== 'done');

  document.getElementById('stat-pending').textContent = pending.length;
  document.getElementById('stat-handoffs').textContent = handoffs.length;
  document.getElementById('stat-done').textContent = done.length;

  document.getElementById('pending-list').innerHTML = pending.length
    ? pending.map(taskCard).join('')
    : '<div class="empty"><div class="empty-icon">&#9745;</div><p>No pending tasks</p></div>';

  document.getElementById('handoff-list').innerHTML = handoffs.length
    ? handoffs.map(handoffCard).join('')
    : '<div class="empty"><div class="empty-icon">&#128230;</div><p>No active handoffs</p></div>';

  document.getElementById('completed-list').innerHTML = done.length
    ? done.map(doneCard).join('')
    : '<div class="empty"><p>Nothing completed this week</p></div>';
}

function priorityBadge(p) {
  const cls = { high: 'badge-high', medium: 'badge-medium', low: 'badge-low' }[p] || 'badge-medium';
  return '<span class="badge ' + cls + '">' + (p || 'medium').toUpperCase() + '</span>';
}

function fmtDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

function esc(s) {
  if (!s) return '';
  const el = document.createElement('span');
  el.textContent = s;
  return el.innerHTML;
}

function taskCard(t) {
  return '<div class="card" id="card-' + t.id + '">' +
    '<div class="card-top"><div class="card-title">' + esc(t.title) + '</div></div>' +
    (t.details ? '<div class="card-detail">' + esc(t.details) + '</div>' : '') +
    '<div class="badges">' + priorityBadge(t.priority) +
    '<span class="badge badge-cat">' + esc(t.category || 'work') + '</span></div>' +
    '<div class="card-date">' + fmtDate(t.created) + '</div>' +
    '<div class="card-actions">' +
    '<button class="btn btn-sm btn-ghost" onclick="toggleExpand(\'' + t.id + '\')">Details</button>' +
    (t.prompt ? '<button class="btn btn-sm btn-ghost" onclick="copyPrompt(\'' + t.id + '\')">Copy Prompt</button>' : '') +
    '<button class="btn btn-sm btn-ghost" onclick="deleteTask(\'' + t.id + '\')" title="Delete">&#10005;</button>' +
    '<button class="btn btn-sm btn-primary" onclick="markDone(\'' + t.id + '\')" title="Done">&#10003;</button>' +
    '</div>' +
    '<div class="expand" id="exp-' + t.id + '">' +
    '<h4>Details</h4><p>' + esc(t.details || 'No details') + '</p>' +
    '<h4>Prompt</h4><div class="prompt-box">' + esc(t.prompt || 'No prompt') + '</div>' +
    (t.output ? '<h4>Output</h4><p>' + esc(t.output) + '</p>' : '') +
    '</div></div>';
}

function handoffCard(h) {
  return '<div class="card" id="card-' + h.id + '">' +
    '<div class="card-top"><div class="card-title">' + esc(h.title || h.file || 'Handoff') + '</div></div>' +
    '<div class="card-date">' + fmtDate(h.date || h.created) + '</div>' +
    (h.summary ? '<div class="card-detail">' + esc(h.summary) + '</div>' : '') +
    '<div class="card-actions">' +
    '<button class="btn btn-sm btn-ghost" onclick="toggleExpand(\'' + h.id + '\')">Details</button>' +
    (h.prompt ? '<button class="btn btn-sm btn-ghost" onclick="copyPrompt(\'' + h.id + '\')">Copy Prompt</button>' : '') +
    '<button class="btn btn-sm btn-primary" onclick="markHandoffDone(\'' + h.id + '\')">Done</button>' +
    '</div>' +
    '<div class="expand" id="exp-' + h.id + '">' +
    '<h4>Summary</h4><p>' + esc(h.summary || 'No summary') + '</p>' +
    (h.remaining ? '<h4>Remaining</h4><p>' + esc(h.remaining) + '</p>' : '') +
    (h.prompt ? '<h4>Prompt</h4><div class="prompt-box">' + esc(h.prompt) + '</div>' : '') +
    '</div></div>';
}

function doneCard(t) {
  return '<div class="card">' +
    '<div class="card-top"><div class="card-title done">' + esc(t.title) + '</div></div>' +
    '<div class="card-date">Completed ' + fmtDate(t.completed) + '</div>' +
    '<div class="card-actions">' +
    '<button class="btn btn-sm btn-ghost" onclick="reopenTask(\'' + t.id + '\')">Reopen</button>' +
    '</div></div>';
}

// ── Actions ─────────────────────────────────────────────────────────────────
function toggleExpand(id) {
  const el = document.getElementById('exp-' + id);
  if (el) el.classList.toggle('open');
}

function copyPrompt(id) {
  const item = data.tasks.find(t => t.id === id) ||
               (data.handoffs || []).find(h => h.id === id);
  if (item && item.prompt) {
    navigator.clipboard.writeText(item.prompt).then(() => {
      const btn = event.target;
      btn.textContent = 'Copied!';
      setTimeout(() => { btn.textContent = 'Copy Prompt'; }, 1500);
    });
  }
}

async function markDone(id) {
  const card = document.getElementById('card-' + id);
  if (card) card.classList.add('removing');
  await fetch(API + '/api/tasks/' + id + '/done', { method: 'POST' });
  setTimeout(load, 300);
}

async function reopenTask(id) {
  await fetch(API + '/api/tasks/' + id + '/reopen', { method: 'POST' });
  load();
}

async function deleteTask(id) {
  const card = document.getElementById('card-' + id);
  if (card) card.classList.add('removing');
  await fetch(API + '/api/tasks/' + id + '/delete', { method: 'POST' });
  setTimeout(load, 300);
}

async function markHandoffDone(id) {
  const card = document.getElementById('card-' + id);
  if (card) card.classList.add('removing');
  await fetch(API + '/api/handoffs/' + id + '/done', { method: 'POST' });
  setTimeout(load, 300);
}

function toggleCompleted() {
  document.getElementById('completed-list').classList.toggle('open');
  document.getElementById('comp-arrow').classList.toggle('open');
}

// ── Modal ───────────────────────────────────────────────────────────────────
function openModal() {
  document.getElementById('modal-overlay').classList.add('open');
  document.getElementById('f-title').focus();
}

function closeModal() {
  document.getElementById('modal-overlay').classList.remove('open');
  document.getElementById('f-title').value = '';
  document.getElementById('f-details').value = '';
  document.getElementById('f-prompt').value = '';
}

function closeModalBg(e) {
  if (e.target === document.getElementById('modal-overlay')) closeModal();
}

async function createTask() {
  const title = document.getElementById('f-title').value.trim();
  if (!title) { document.getElementById('f-title').focus(); return; }
  await fetch(API + '/api/tasks', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      title: title,
      priority: document.getElementById('f-priority').value,
      category: document.getElementById('f-category').value,
      details: document.getElementById('f-details').value.trim(),
      prompt: document.getElementById('f-prompt').value.trim()
    })
  });
  closeModal();
  load();
}

// ── Keyboard shortcuts ──────────────────────────────────────────────────────
document.addEventListener('keydown', function(e) {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
  if (e.key === 'n' || e.key === 'N') { e.preventDefault(); openModal(); }
  if (e.key === 'Escape') closeModal();
});

// ── Init ────────────────────────────────────────────────────────────────────
load();
setInterval(load, 10000);
</script>
</body>
</html>
HTMLEOF
fi

# ── 4. task-hub.json (empty seed) ────────────────────────────────────────────
if [ -f "$TASK_DIR/task-hub.json" ]; then
  echo "task-hub.json already exists — skipping"
else
  echo "Creating task-hub.json..."
  cat > "$TASK_DIR/task-hub.json" << 'JSONEOF'
{
  "tasks": [
    {
      "id": "t-20260101-001",
      "title": "Organize vault notes into PARA folders",
      "status": "pending",
      "priority": "high",
      "category": "work",
      "created": "2026-01-01T09:00:00",
      "completed": null,
      "source": "session",
      "details": "Move uncategorized notes from root into proper PARA folders (1_AI and IT, 2_Project, etc.)",
      "prompt": "Help me organize my vault notes. Read the root folder, identify notes that belong in PARA folders, and move them with proper YAML frontmatter.",
      "output": ""
    },
    {
      "id": "t-20260101-002",
      "title": "Learn how to use Claude Code skills",
      "status": "pending",
      "priority": "medium",
      "category": "learning",
      "created": "2026-01-01T10:00:00",
      "completed": null,
      "source": "session",
      "details": "Explore available skills and practice using 2-3 of them in real tasks",
      "prompt": "Show me a list of available Claude Code skills and help me practice using the most useful ones for my vault management workflow.",
      "output": ""
    },
    {
      "id": "t-20260101-003",
      "title": "Write first AI Diary entry",
      "status": "done",
      "priority": "low",
      "category": "content",
      "created": "2026-01-01T08:00:00",
      "completed": "2026-01-01T11:30:00",
      "source": "dashboard",
      "details": "Write a short reflection about setting up my Second Brain",
      "prompt": "",
      "output": ""
    }
  ],
  "handoffs": [
    {
      "id": "h-20260101-001",
      "title": "Vault Setup Continuation",
      "file": "handoff/2026-01-01_vault-setup-handoff.md",
      "status": "pending",
      "created": "2026-01-01",
      "completed": null,
      "summary": "Initial vault structure created. Next: add YAML frontmatter to remaining notes, set up MOC files, and configure daily workflow."
    }
  ]
}
JSONEOF
fi

# ── 5. Claude rule: task-hub.md ──────────────────────────────────────────────
if [ -f "$RULE_DIR/task-hub.md" ]; then
  echo "task-hub.md rule already exists — skipping"
else
  echo "Installing .claude/rules/task-hub.md..."
  cat > "$RULE_DIR/task-hub.md" << 'RULEEOF'
# Task Hub Rules

## Data File
`_Others/Personal Tasks/task-hub.json`

## Capture Triggers

When user says any of these, immediately write to task-hub.json:
- Thai: "จดไว้", "ทำทีหลัง", "เดี๋ยวทำ", "ยังไม่ต้องทำตอนนี้", "ไว้ทำ"
- English: "do later", "remind me", "add task", "note this", "park this", "save for later"

### How to capture:
1. Read `_Others/Personal Tasks/task-hub.json`
2. Add new task with schema: id (t-YYYYMMDD-NNN), title, status "pending", priority, category, created (ISO), completed null, source "session", details, prompt (self-contained instruction), output ""
3. Write back the updated JSON
4. Confirm with task title

### Prompt field is critical:
The prompt field must contain a self-contained instruction that a fresh Claude session can paste and immediately understand what to do.

## Completion Trigger
When a task matching a pending item is completed:
1. Set status to "done" and completed to ISO timestamp
2. Confirm completion

## Session Start
Read task-hub.json and report pending task count.
RULEEOF
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Task Hub Setup Complete ==="
echo ""
echo "  task-server.py  →  $TASK_DIR/task-server.py"
echo "  dashboard.html  →  $TASK_DIR/dashboard.html"
echo "  task-hub.json   →  $TASK_DIR/task-hub.json"
echo "  task-hub.md     →  $RULE_DIR/task-hub.md"
echo ""
echo "Start the server:"
echo "  cd \"$TASK_DIR\" && python3 task-server.py"
echo ""
echo "Then open http://localhost:5555"
