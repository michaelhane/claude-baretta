"""Measure how orchestrators work, from their transcripts. Read only, numbers only.

Meant for a weekly measurement: run it, and put the output in a measurement log of your choice.

Usage:
  python orchestrator_log.py [--days 7] [--json] <transcript folder> [...]
  Transcript folder = <home>/.claude/projects/<project-folder>/.
  --days 0 = no filter on modification date.

No text from a transcript ever appears in the output: transcripts can contain amounts and
personal data.

Expires when: Claude Code itself shows per-session statistics on messages from other
sessions, outgoing tasks and the tools used after a report.
"""
import argparse
import json
import os
import re
import sys
import time

TITLE_ORCH = re.compile(r"^(OLD )?orchestrator", re.I)
CORRECTION = re.compile(r"\b(no|wrong|not right|don't|why|stop|that's not what i meant)\b", re.I)
YES = re.compile(r"\byes\b", re.I)
GREEN = re.compile(r"\b(green|done)\b", re.I)
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
OUTGOING = {"SendMessage", "mcp__ccd_session_mgmt__send_message"}
GRAPH = re.compile(r"\bgraphify\s+(query|explain|path|update)\b")
GRAPH_READ = ("query", "explain", "path")
APPROVAL_MARK = "approved"  # a merge/push without this word in the command counts as a rule break (core § 3, Checking)
MAP = re.compile(r"^\s*Map:", re.M)
CLEANUP = "cleanup_list.py"


def text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""


def is_tool_result(content):
    return isinstance(content, list) and any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content)


def graph_calls(lines):
    """Counts graphify calls in the Bash commands of one transcript."""
    n = dict.fromkeys(("query", "explain", "path", "update"), 0)
    for o in lines:
        if o.get("type") != "assistant":
            continue
        for c in (o.get("message") or {}).get("content") or []:
            if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") in ("Bash", "PowerShell"):
                for w in GRAPH.findall((c.get("input") or {}).get("command", "")):
                    n[w] += 1
    return n


def read(path):
    titles, lines = [], []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if o.get("type") == "custom-title":
                titles.append(o.get("customTitle", ""))
            lines.append(o)
    return titles, lines


def measure(path, titles=None, lines=None):
    if lines is None:
        titles, lines = read(path)
    if not any(TITLE_ORCH.match(t or "") for t in titles):
        return None
    m = dict(file=os.path.basename(path), title=next((t for t in titles if TITLE_ORCH.match(t)), ""),
             old=bool(titles) and titles[-1].upper().startswith("OLD"),
             start=None, end=None, context_max=0,
             worker_messages=0, worker_chars=0, worker_chars_max=0,
             outgoing=0, outgoing_done_when=0, outgoing_brief=0, outgoing_inbox=0,
             reports_green=0, reports_checked=0,
             user_turns=0, user_corrections=0,
             archive=0, archive_without_yes=0, merge_push_without_approval=0, worktree_force=0,
             outgoing_map=0, cleanup_rounds=0, graph=graph_calls(lines))
    open_report = False   # is a green report still waiting for the orchestrator's own check?
    checked = False
    last_human = ""
    list_in_turn = False  # did cleanup_list.py run since the last message? Then archiving is the standing yes
    for o in lines:
        ts = o.get("timestamp")
        if ts:
            m["start"] = m["start"] or ts
            m["end"] = ts
        t = o.get("type")
        msg = o.get("message") or {}
        if t == "user":
            c = msg.get("content")
            if is_tool_result(c):
                continue
            list_in_turn = False
            txt = text(c)
            if "<cross-session-message" in txt or o.get("turnOrigin") == "peer":
                core = REMINDER.sub("", txt)
                m["worker_messages"] += 1
                m["worker_chars"] += len(core)
                m["worker_chars_max"] = max(m["worker_chars_max"], len(core))
                if GREEN.search(core):
                    if open_report and checked:
                        m["reports_checked"] += 1
                    m["reports_green"] += 1
                    open_report, checked = True, False
            elif o.get("turnOrigin") == "human":
                core = REMINDER.sub("", txt).strip()
                if core:
                    m["user_turns"] += 1
                    last_human = core
                    if CORRECTION.search(core):
                        m["user_corrections"] += 1
        elif t == "assistant":
            u = msg.get("usage") or {}
            ctx = sum(u.get(k, 0) or 0 for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
            m["context_max"] = max(m["context_max"], ctx)
            for c in msg.get("content") or []:
                if not isinstance(c, dict) or c.get("type") != "tool_use":
                    continue
                name, inp = c.get("name", ""), c.get("input") or {}
                if name in ("Bash", "PowerShell") and CLEANUP in inp.get("command", ""):
                    m["cleanup_rounds"] += 1
                    list_in_turn = True
                if name == "Bash":
                    cmd = inp.get("command", "")
                    if open_report:
                        checked = True
                    if re.search(r"git (merge|push)(?![-\w])", cmd) and re.search(r"\b(master|main)\b|git merge(?![-\w])", cmd) and APPROVAL_MARK not in cmd:
                        m["merge_push_without_approval"] += 1
                    if "git worktree remove" in cmd and "--force" in cmd:
                        m["worktree_force"] += 1
                elif name in OUTGOING:
                    if open_report:
                        if checked:
                            m["reports_checked"] += 1
                        open_report = False
                    body = inp.get("message") or inp.get("text") or ""
                    if isinstance(body, dict):
                        body = json.dumps(body)
                    m["outgoing"] += 1
                    m["outgoing_done_when"] += "Done when" in body
                    m["outgoing_brief"] += "On a task:" in body
                    m["outgoing_inbox"] += ".claude/inbox/" in body
                    m["outgoing_map"] += bool(MAP.search(body))
                elif name.rsplit("__", 1)[-1] == "archive_session":
                    m["archive"] += 1
                    if not YES.search(last_human) and not list_in_turn:
                        m["archive_without_yes"] += 1
    if open_report and checked:
        m["reports_checked"] += 1
    return m


def block(res, graph=None):
    r = []
    if graph:
        r.append(f"- **graph:** {graph['with_read']} of {graph['sessions']} sessions read the graph; "
                 f"query {graph['query']}, explain {graph['explain']}, path {graph['path']}, update {graph['update']}")
    if not res:
        r.append("No orchestrator transcripts in this period.")
        return "\n".join(r)
    for o in res:
        avg = o["worker_chars"] // o["worker_messages"] if o["worker_messages"] else 0
        r.append(f"- **{o['title']}**{' (OLD)' if o['old'] else ''}, {o['start'][:16] if o['start'] else '?'} – {o['end'][:16] if o['end'] else '?'}, context max {o['context_max']//1000}K")
        r.append(f"  - worker messages {o['worker_messages']}, average {avg} chars, max {o['worker_chars_max']}")
        r.append(f"  - tasks {o['outgoing']}: Done when {o['outgoing_done_when']}, brief {o['outgoing_brief']}, inbox {o['outgoing_inbox']}, Map {o['outgoing_map']}")
        g = o["graph"]
        r.append(f"  - graph itself: query {g['query']}, explain {g['explain']}, path {g['path']}, update {g['update']}")
        r.append(f"  - own check after green: {o['reports_checked']} of {o['reports_green']}")
        r.append(f"  - user corrections: {o['user_corrections']} of {o['user_turns']} turns")
        r.append(f"  - cleanup rounds {o['cleanup_rounds']}")
        r.append(f"  - rule breaks: archive without yes {o['archive_without_yes']} (of {o['archive']}), merge/push without approval {o['merge_push_without_approval']}, worktree --force {o['worktree_force']}")
    return "\n".join(r)


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # cp1252 console, and lone surrogates from truncated emoji in titles
    ap = argparse.ArgumentParser()
    ap.add_argument("folders", nargs="+")
    ap.add_argument("--days", type=float, default=7)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    limit = time.time() - a.days * 86400 if a.days else 0
    res = []
    graph = dict(sessions=0, with_read=0, query=0, explain=0, path=0, update=0)
    for d in a.folders:
        if not os.path.isdir(d):
            print(f"folder missing: {d}", file=sys.stderr)
            continue
        for n in sorted(os.listdir(d)):
            p = os.path.join(d, n)
            if n.endswith(".jsonl") and os.path.isfile(p) and os.path.getmtime(p) >= limit:
                titles, lines = read(p)
                g = graph_calls(lines)
                graph["sessions"] += 1
                graph["with_read"] += any(g[k] for k in GRAPH_READ)
                for k, v in g.items():
                    graph[k] += v
                m = measure(p, titles, lines)
                if m:
                    res.append(m)
    print(json.dumps({"orchestrators": res, "graph": graph}, indent=1) if a.json else block(res, graph))


if __name__ == "__main__":
    main()
