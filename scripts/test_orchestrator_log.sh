#!/usr/bin/env bash
# Test for scripts/orchestrator_log.py.
# Builds a fixture with real line shapes from a desktop transcript and checks the counts.
REPO=$(cd "$(dirname "$0")/.." && pwd)  # the checkout of this script, also in a worktree
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 -I - "$TMP" <<'EOF'
import json, sys, os
d = sys.argv[1]
def a(ctx, tools=(), text=""):
    content = ([{"type": "text", "text": text}] if text else []) + [
        {"type": "tool_use", "id": f"t{i}{n}", "name": n, "input": inp} for i, (n, inp) in enumerate(tools)]
    return {"type": "assistant", "timestamp": "2026-11-03T10:00:00Z",
            "message": {"role": "assistant", "content": content,
                        "usage": {"input_tokens": 2, "cache_read_input_tokens": ctx, "cache_creation_input_tokens": 0, "output_tokens": 5}}}
def u(text, origin):
    return {"type": "user", "turnOrigin": origin, "promptSource": "sdk", "timestamp": "2026-11-03T10:00:00Z",
            "message": {"role": "user", "content": text}}
def r():
    return {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "x", "content": "ok"}]}}
cross = lambda t: '<system-reminder>\nLinked sessions now</system-reminder>\n<cross-session-message from="local_1" from-name="Worker 1 (test)">\n' + t + '\n</cross-session-message>'
orch = [
 {"type": "custom-title", "customTitle": "Orchestrator test (active)", "sessionId": "s1"},
 u("build the button", "human"),
 a(99000, [("Bash", {"command": "cd /c/x && graphify query \"buttonClick setButton\""}), ("Bash", {"command": "cd /c/x && graphify explain \"buttonClick\" | head"})]), r(),
 a(100000, [("SendMessage", {"to": "local_1", "message": "You are reserve 1 ...\nOn a task:\n1. ...\nMap: web/button.js (graphify explain \"buttonClick\")\nDone when `npm test` exit 0. Report in ~/.claude/inbox/test.md"})]), r(),
 u(cross("W1 button: green, abc123, report in inbox"), "peer"),
 a(110000, [("Bash", {"command": "npm test"})]), r(),
 a(111000, [("SendMessage", {"to": "local_1", "message": "good, wait for the user"})]), r(),
 u(cross("W2 text: green, def456. " + "x" * 3000), "peer"),
 a(130000, [("SendMessage", {"to": "local_2", "message": "release"})]), r(),
 u("no, that is wrong, the button belongs on the left", "human"),
 a(131000, text="Understood."),
 u("clean up", "human"),
 a(132000, [("mcp__ccd_session_mgmt__archive_session", {"session_id": "local_9"})]), r(),
 u("yes, archive it", "human"),
 a(133000, [("mcp__ccd_session_mgmt__archive_session", {"session_id": "local_8"})]), r(),
 a(134000, [("Bash", {"command": "git merge claude/x -m 'merge: x' && git push origin master"})]), r(),
 a(135000, [("Bash", {"command": "git merge claude/y -m 'merge: y (approved by user: yes)' && git push origin master"})]), r(),
 a(136000, [("Bash", {"command": "git worktree remove --force .claude/worktrees/z"})]), r(),
 a(136000, [("Bash", {"command": "git merge-base --is-ancestor claude/z master"})]), r(),
 a(136000, [("mcp__ccd_session_mgmt__unarchive_session", {"session_id": "local_9"})]), r(),
 u("time for the round", "human"),
 a(137000, [("Bash", {"command": "python3 -I ~/.claude/scripts/cleanup_list.py /c/x --sessions s.json"})]), r(),
 a(137000, [("mcp__ccd_session_mgmt__archive_session", {"session_id": "local_7"})]), r(),
 u(cross("W3 something: red"), "peer"),
 a(138000, [("mcp__ccd_session_mgmt__archive_session", {"session_id": "local_6"})]), r(),
 {"type": "custom-title", "customTitle": "OLD orchestrator test (do not use)", "sessionId": "s1"},
]
worker = [{"type": "custom-title", "customTitle": "Worker 3: something (test)", "sessionId": "s2"}, u("no", "human"),
          a(50000, [("mcp__ccd_session_mgmt__archive_session", {"session_id": "q"})]),
          a(51000, [("Bash", {"command": "cd /c/x && graphify path \"buttonClick\" \"setButton\""})]), r(),
          a(52000, [("Bash", {"command": "graphify update . && git status"})]), r()]
searcher = [u("find the button", "human"), a(40000, [("Bash", {"command": "grep -rn button web/"})]), r(),
            a(41000, text="graphify query appears here only as text, not in a command")]
for name, lines in (("orch.jsonl", orch), ("worker.jsonl", worker), ("searcher.jsonl", searcher)):
    with open(os.path.join(d, name), "w", encoding="utf-8") as f:
        for x in lines: f.write(json.dumps(x) + "\n")
EOF
OUT=$(python3 -I "$REPO/scripts/orchestrator_log.py" --days 0 --json "$TMP")
RED=0
check() { # name, python expression on variable o (the json of the only orchestrator)
  if python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); o=d['orchestrators'][0]; sys.exit(0 if ($2) else 1)" "$OUT"; then echo "green  $1"; else echo "RED    $1"; RED=1; fi
}
check "only the orchestrator counts" "len(d['orchestrators'])==1"
check "ends as OLD" "o['old'] is True"
check "highest context" "o['context_max']==138002"
check "three worker messages" "o['worker_messages']==3"
check "length of worker messages measured" "o['worker_chars_max']>3000"
check "three outgoing messages" "o['outgoing']==3"
check "one with Done when, brief and inbox" "o['outgoing_done_when']==1 and o['outgoing_brief']==1 and o['outgoing_inbox']==1"
check "one of two green reports checked" "o['reports_green']==2 and o['reports_checked']==1"
check "one correction in five human turns" "o['user_turns']==5 and o['user_corrections']==1"
check "archive without yes: not after cleanup_list in the same turn, yes in a later turn" "o['archive']==4 and o['archive_without_yes']==2"
check "one cleanup round" "o['cleanup_rounds']==1"
check "merge without approval = 1 break" "o['merge_push_without_approval']==1"
check "worktree --force = 1 break" "o['worktree_force']==1"
check "one task with a Map: line" "o['outgoing_map']==1"
check "graph of the orchestrator: 1 query, 1 explain" "o['graph']=={'query': 1, 'explain': 1, 'path': 0, 'update': 0}"
check "graph over all sessions: 2 of 3 read" "d['graph']['sessions']==3 and d['graph']['with_read']==2"
check "graph totals: path and update separate, text does not count" "d['graph']=={'sessions': 3, 'with_read': 2, 'query': 1, 'explain': 1, 'path': 1, 'update': 1}"
check "no text from the transcript in the output" "'belongs on the left' not in json.dumps(d)"
python3 -I "$REPO/scripts/orchestrator_log.py" --days 0 "$TMP" | grep -q "Orchestrator test" && python3 -I "$REPO/scripts/orchestrator_log.py" --days 0 "$TMP" | grep -q "2 of 3 sessions read the graph" && echo "green  markdown block names the orchestrator" || { echo "RED    markdown block"; RED=1; }
python3 -I "$REPO/scripts/orchestrator_log.py" --days 0 "$TMP" | grep -q "cleanup rounds 1" && echo "green  markdown block names cleanup rounds" || { echo "RED    cleanup rounds in block"; RED=1; }
printf '%s\n' '{"type":"custom-title","customTitle":"Orchestrator \ud83d emoji 🧠"}' > "$TMP/emoji.jsonl"
python3 -I "$REPO/scripts/orchestrator_log.py" --days 0 "$TMP" >/dev/null 2>&1 && echo "green  lone surrogate in a title does not crash under -I" || { echo "RED    lone surrogate crashes"; RED=1; }
exit $RED
