#!/usr/bin/env bash
# Test for scripts/cleanup_list.py.
# Builds a throwaway repo with worktrees and branches plus a sessions JSON with one fixture per class
# and per never-candidate, and checks in which block every row lands. Exit 0 = all green.
REPO=$(cd "$(dirname "$0")/.." && pwd)
mpad() { cygpath -m "$1" 2>/dev/null || echo "$1"; }  # Windows path under Git Bash, unchanged elsewhere
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
H=$TMP/main
g() { git -C "$@" >/dev/null 2>&1; }
git init -q -b main "$H"
g "$H" config core.autocrlf false; g "$H" config user.email t@t; g "$H" config user.name t
mkdir -p "$H/.claude/summaries"
printf 'a\nb\n' > "$H/text.txt"; echo log > "$H/.claude/summaries/sessions.log"
g "$H" add -A; g "$H" commit -m start
# B: merged, only sessions.log and a CRLF difference
g "$H" worktree add -b wt-clean "$TMP/wt-clean" main
printf 'a\r\nb\r\n' > "$TMP/wt-clean/text.txt"; echo extra >> "$TMP/wt-clean/.claude/summaries/sessions.log"
# list: own commit outside main
g "$H" worktree add -b wt-own "$TMP/wt-own" main
echo new > "$TMP/wt-own/new.txt"; g "$TMP/wt-own" add -A; g "$TMP/wt-own" commit -m own
# list: merged but a really changed file
g "$H" worktree add -b wt-dirty "$TMP/wt-dirty" main
printf 'a\nc\n' > "$TMP/wt-dirty/text.txt"
# list: merged and clean, but a live session
g "$H" worktree add -b wt-live "$TMP/wt-live" main
# E: merged branch without a worktree; an unmerged one stays
g "$H" branch done-branch main
g "$H" branch open-branch "$(git -C "$TMP/wt-own" rev-parse HEAD)"

python -I - "$TMP" "$H" <<'EOF'
import json, sys
tmp, h = sys.argv[1], sys.argv[2]
def s(i, title, days, cwd=h, **kw):
    d = {"sessionId": i, "title": title, "cwd": cwd, "isArchived": False, "isRunning": False,
         "lastActivityAt": f"2026-11-{10 - days:02d}T12:00:00.000Z"}
    d.update(kw); return d
S = [
 s("orch", "Orchestrator test (active)", 0, pinned=True),
 s("old1", "OLD orchestrator test (do not use)", 3, pinned=True),
 s("child1", "Secretary (test)", 0, startedBy="old1", detached=True),
 s("old2", "OLD orchestrator test (do not use)", 4),
 s("child2", "Reserve 3 (test, free)", 1, startedBy="old2"),
 s("old3", "OLD orchestrator test (do not use)", 5),
 s("old3b", "OLD orchestrator test (do not use)", 5, startedBy="old3"),
 s("done1", "app DONE job", 3),
 s("done2", "app DONE fresh", 1),
 s("done3", "app DONE with work", 3, cwd=tmp + "/wt-own"),
 s("trial1", "Trial P1 phone", 2, startedBy="orch"),
 s("trial2", "Test something", 2, startedBy="work"),
 s("trial3", "Trial with worktree", 2, startedBy="orch", cwd=tmp + "/wt-dirty"),
 s("work", "Worker 1: something (test)", 0, isRunning=True),
 s("live", "Worker 2: busy (test)", 0, cwd=tmp + "/wt-live"),
 s("free", "Reserve 4 (test, free)", 10),
 s("wait", "Worker 5: x (test) - waiting for user", 3),
 s("waitfresh", "Worker 6: y (test) - waiting for user", 1),
 s("clear", "Worker 7: z (test) - clear failed", 10),
 s("secr", "Secretary (test)", 10),
 s("room", "Room docs (test, free)", 10),
 s("merge", "Worker 8: merge role (test)", 10),
 s("donefree", "DONE Reserve 9 (test, free)", 10),
 s("oldbusy", "OLD orchestrator x (do not use)", 3, isRunning=True),
 s("idle", "Worker 10: old work (test)", 9),
 s("elsewhere", "OLD orchestrator other project", 9, cwd="C:/elsewhere"),
 s("already", "archive! app DONE already renamed", 4),
 s("trialw", "Trial worker title", 2, startedBy="orch"),
 s("wdone", "Worker 12: job (test) DONE", 3),
 s("odone", "Orchestrator old DONE", 3),
 s("alreadyfree", "archive! Reserve 11 (test, free)", 10),
]
json.dump(S, open(tmp + "/sessions.json", "w", encoding="utf-8"))
EOF

OUT=$(python -I "$REPO/scripts/cleanup_list.py" "$H" --sessions "$TMP/sessions.json" --now 2026-11-10T12:00:00Z --active orch)
RC=$?
CNT=$(python -I "$REPO/scripts/cleanup_list.py" "$H" --sessions "$TMP/sessions.json" --now 2026-11-10T12:00:00Z --active orch --count)
BARE=$(python -I "$REPO/scripts/cleanup_list.py" "$H" --now 2026-11-10T12:00:00Z --count)
RED=0
block() { echo "$OUT" | awk -v k="$1" '/^## /{f=(index($0, "## " k)==1)} f'; }
check() { if eval "$2" >/dev/null 2>&1; then echo "green  $1"; else echo "RED    $1"; RED=1; fi; }
check "script exits 0" "[ $RC = 0 ]"
check "A: OLD with detached child, unpin first" "block A. | grep -q '(old1)' && block A. | grep -q 'set_pinned session_id=old1 pinned=false'"
check "A: OLD with OLD child, both" "block A. | grep -q '(old3)' && block A. | grep -q '(old3b)'"
check "A: order set_pinned, archive, after-check" "block A. | grep -A3 '(old1)' | tr '\n' ' ' | grep -qE 'set_pinned.*archive_session.*include_archived.*unarchive_session'"
check "list: OLD with attached child" "block List | grep -q 'OLD with a child still attached: Reserve 3'"
check "list: OLD that is busy" "block List | grep -q 'OLD but busy'"
check "A: other project does not count" "! echo \"\$OUT\" | grep -q '(elsewhere)'"
check "B: merged + sessions.log + CRLF" "block B. | grep -q 'wt-clean' && block B. | grep -q 'checkout -- .claude/summaries/sessions.log text.txt' && block B. | grep -q 'worktree remove .*wt-clean'"
check "B: never --force as a command" "! block B. | grep -E 'remove' | grep -v 'never --force' | grep -q -- '--force'"
check "list: worktree with own commit" "block List | grep 'wt-own' | grep -q 'own commit outside main (1)'"
check "list: worktree with a real difference" "block List | grep 'wt-dirty' | grep -q 'not clean: text.txt'"
check "list: worktree with a live session" "block List | grep 'wt-live' | grep -q 'live session: Worker 2'"
check "C: DONE > 2 days" "block C. | grep -q '(done1)'"
check "C: DONE of 1 day nowhere" "! echo \"\$OUT\" | grep -q 'DONE fresh'"
check "list: DONE with own worktree work" "block List | grep 'DONE with work' | grep -q 'own commit'"
check "D: Trial from orchestrator > 1 day" "block D. | grep -q '(trial1)'"
check "D: Test from a worker not" "! block D. | grep -q '(trial2)'"
check "D: Trial with worktree on the list" "! block D. | grep -q '(trial3)' && block List | grep -q 'Trial with worktree | .* | Trial/Test with own worktree'"
check "E: merged branch without worktree" "block E. | grep -q 'branch -d done-branch'"
check "E: unmerged and worktree branches not" "! block E. | grep -qE 'open-branch|wt-|branch -d main'"
check "E: never -D as a command" "! block E. | grep -q 'branch -D'"
check "list: waiting for user > 2 days" "block List | grep -q 'Worker 5: x (test) - waiting for user'"
check "waiting for user < 2 days nowhere" "! echo \"\$OUT\" | grep -q 'Worker 6'"
check "list: no turn in 7 days" "block List | grep 'Worker 10' | grep -q 'no turn in 9 days'"
for n in "Reserve 4" "clear failed" "Secretary (test) " "Room docs" "merge role" "DONE Reserve 9" "Orchestrator test (active)" "Worker 1: something"; do
  check "never a candidate: $n" "! echo \"\$OUT\" | grep -F -- '$n' | grep -qv 'Secretary (test) (child1)'"
done
for k in "A.:old1" "C.:done1" "D.:trial1"; do
  check "fallback rename in ${k%%:*} for ${k#*:}" "block ${k%%:*} | grep -q 'set_session_title session_id=${k#*:} title=\"archive! '"
done
check "fallback keeps the title" "block C. | grep -q 'title=\"archive! app DONE job\"'"
check "already renamed: candidate again, no double prefix" "block C. | grep -q '(already)' && ! echo \"\$OUT\" | grep -q 'archive! archive!' && ! echo \"\$OUT\" | grep -q 'session_id=already title='"
check "already renamed with role title free: never a candidate" "! echo \"\$OUT\" | grep -q 'Reserve 11'"
check "Worker with DONE does get renamed" "block C. | grep -q 'session_id=wdone title=\"archive! Worker 12'"
check "role title never renamed (script)" "python -I -c \"import sys; sys.path.insert(0, r'$(mpad "$REPO")/scripts'); import cleanup_list as o; sys.exit(0 if all(map(o.role_title, ['Worker 3: x (myapp)', 'Reserve 4 (b, free)', 'Orchestrator b (active)', 'Secretary (b)'])) and not any(map(o.role_title, ['Worker 3: x - waiting for user', 'Worker 3: x DONE', 'OLD orchestrator b'])) else 1)\""
check "role title in C: archive yes, rename no (render)" "block C. | grep -A5 '(odone)' | grep -q 'role title, never rename' && ! echo \"\$OUT\" | grep -q 'session_id=odone title='"
check "already renamed: fallback says leave it" "block C. | grep -A5 '(already)' | grep -q 'already renamed; if archive_session refuses again, leave it'"
check "no fallback in B, E or the list" "! block B. | grep -q set_session_title && ! block E. | grep -q set_session_title && ! block List | grep -q set_session_title"
check "--count counts per class" "echo \"\$CNT\" | grep -q 'A 3, B 1, C 4, D 2, E 1' && echo \"\$CNT\" | grep -q 'worktrees 4 (merged 3, clean 2)'"
check "without sessions: B to the list" "echo \"\$BARE\" | grep -q 'sessions ?' && echo \"\$BARE\" | grep -q 'B 0'"
FRESH=$(python -I "$REPO/scripts/cleanup_list.py" "$H" --sessions "$TMP/sessions.json" --active orch)
check "list: fresh worktree (< 1 day, maybe a bg worker) not in B" "echo \"\$FRESH\" | grep 'wt-clean' | grep -q 'fresh worktree' && ! echo \"\$FRESH\" | awk '/^## B/{f=1} /^## C/{f=0} f' | grep -q 'wt-clean'"
check "read only: worktrees still exist" "[ \$(git -C '$H' worktree list | wc -l) = 5 ] && git -C '$H' rev-parse -q --verify done-branch"
printf '%s\n' '[{"sessionId":"x","title":"OLD orchestrator \ud83d broken","cwd":"'"$(mpad "$H")"'","lastActivityAt":"2026-11-01T00:00:00Z"}]' > "$TMP/emoji.json"
check "lone surrogate in a title does not crash under -I" "python -I '$REPO/scripts/cleanup_list.py' '$H' --sessions '$TMP/emoji.json' --now 2026-11-10T12:00:00Z | grep -q 'broken'"
exit $RED
