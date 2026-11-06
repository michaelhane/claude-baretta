#!/usr/bin/env bash
# Coherence of the core and the commands in this repo. Exit 0 = all green.
# The core is the only source: the commands refer to it and do not copy it.
# CORE=<copy> tests a core change before you put it in place.
HERE=$(cd "$(dirname "$0")/.." && pwd)
CMD=$HERE/commands
CORE=${CORE:-$HERE/core/orchestrator-core.md}
RED=0

check() { # name, expected (0 = must succeed), command
  if eval "$3" >/dev/null 2>&1; then r=0; else r=1; fi
  if [ "$r" = "$2" ]; then echo "green  $1"; else echo "RED    $1"; RED=1; fi
}

check "core exists" 0 "[ -s $CORE ]"
check "core has pillars P1-P7" 0 "for p in P1 P2 P3 P4 P5 P6 P7; do grep -q \"\\*\\*\$p \" $CORE || exit 1; done"
for f in baretta revolver; do
  check "$f exists" 0 "[ -s $CMD/$f.md ]"
  check "$f refers to the core" 0 "grep -q 'orchestrator-core.md' $CMD/$f.md"
  check "$f does not copy the worker brief" 1 "grep -q 'On a task:' $CMD/$f.md"
  check "$f keeps an Expires when line" 0 "grep -qi 'expires when' $CMD/$f.md"
  check "$f preflight knows detach_session, get_session and set_pinned" 0 "grep -q 'detach_session., .get_session' $CMD/$f.md && grep -q 'move_sessions., .set_pinned' $CMD/$f.md"
  check "$f pins the orchestrator" 0 "grep 'Rename yourself with' $CMD/$f.md | grep -q 'set_pinned self true'"
done
check "no dollar digits in commands" 1 "grep -qE '[$][0-9]' $CMD/*.md"
check "baretta knows mini with secretary" 0 "grep -q '^- .mini.:' $CMD/baretta.md && grep -q 'Secretary (<project>)' $CMD/baretta.md"
check "baretta preflight fallback without set_pinned" 0 "grep -q 'without .set_pinned.: do not pin' $CMD/baretta.md"
check "core: the worker brief lives in the core" 0 "grep -q '^On a task:' $CORE"
check "core: cleanup every day at 07:30 with a clock" 0 "grep -q 'Clean up, every day at 07:30 and right after every handover' $CORE && grep -q 'CronCreate. .30 7 \* \* \*.' $CORE && grep -q 'never .--force.' $CORE"
check "core: the round runs cleanup_list.py and the script exists" 0 "grep -q 'scripts/cleanup_list.py <main checkout> --sessions' $CORE && [ -s $HERE/scripts/cleanup_list.py ]"
check "core: standing yes" 0 "[ \$(grep -c 'standing yes' $CORE) -ge 1 ]"
check "core: classes A to E" 0 "for k in 'A: OLD orchestrator' 'B: worktree' 'C: title with .DONE.' 'D: title starts with .Trial. or .Test.' 'E: local branch'; do grep -q \"^  - \$k\" $CORE || exit 1; done && grep -q 'git branch -d. (never .-D.)' $CORE"
check "core: clean up right after the handover" 0 "grep -q 'After the handover:.* do the cleanup round of § 3 right away and set your clock' $CORE"
check "core: clean up = first the list" 0 "grep -q 'never archive directly' $CORE"
check "core: never a candidate, also waiting for user and clear failed" 0 "grep -q 'Never a candidate: titles with .free.' $CORE && grep 'Never a candidate' $CORE | grep -q 'waiting for user' && grep 'Never a candidate' $CORE | grep -q 'clear failed'"
check "core: report through the inbox outside the repo" 0 "grep -q '<inbox>/<project>.md' $CORE && grep -q 'report in inbox' $CORE"
check "core: orchestrator hands over itself above ~600K" 0 "grep -q 'Hand over before you fill up' $CORE && grep -q 'get_usage. (session_id self)' $CORE"
check "core: leaving it is never the end point" 0 "grep -q 'Leaving it is never the end point' $CORE"
check "core: lanes get a new report address at handover" 0 "grep -q 'Your report address is now' $CORE"
check "core: a task has a Map: line" 0 "grep -q 'line .Map: <file + neighbours> (<how you found it>).' $CORE && grep -q 'Map: domain map' $CORE"
check "core: worker brief finds files through integration point 1" 0 "sed -n '/^On a task:/,/^\`\`\`/p' $CORE | grep -q 'use integration point 1 in the main checkout'"
check "core: worker never builds or updates an index" 0 "sed -n '/^On a task:/,/^\`\`\`/p' $CORE | grep -q 'Never build or update an index'"
check "core: optional index never in repos with sensitive data" 0 "grep -q 'never in repos with sensitive data' $CORE"
check "core: three integration points with their defaults" 0 "grep -q '^## Integration points' $CORE && grep -q '1. Finding the file.*git grep -l <word>.*docs/map.md' $CORE && grep '2. Questions for the user' $CORE | grep -q '<inbox>/questions.md.*code, question, options, searched.*kind' && grep -q '3. Keeping knowledge.*.claude/handoff/<date>-<id>.md.*state, open, next step' $CORE"
check "README has the Integrations section with the three points" 0 "grep -q '^## Integrations' $HERE/README.md && grep -q '^| Finding the file' $HERE/README.md && grep -q '^| Questions for the user' $HERE/README.md && grep -q '^| Keeping knowledge' $HERE/README.md"
check "core: attached child via startedBy goes on the list" 0 "grep 'Children\.\*\*' $CORE | grep -q 'startedBy. = its id'"
check "core: after-check for children taken along by archiving" 0 "grep -q 'whether a child went along that was not on the list' $CORE"
check "core: fallback archive!, role titles never" 0 "grep -q 'Fallback \"archive!\":' $CORE && grep 'Fallback \"archive!\"' $CORE | grep -q 'Never rename a role title'"
check "core: pinned OLD follows class A (set_pinned off before archive_session)" 0 "grep '^  - A: OLD' $CORE | grep -q 'set_pinned. off.*archive_session'"
check "core: workers and reserves never pin" 0 "grep '^- Pinned in the sidebar' $CORE | grep -q 'Workers, reserves, rooms and the secretary never pin'"
check "core: worker brief does not mention set_pinned" 1 "sed -n '/^On a task:/,/^\`\`\`/p' $CORE | grep -q 'set_pinned'"
check "core: P1 fallback claude --bg" 0 "grep '^- \*\*P1 ' $CORE | grep -q 'claude --bg'"
check "core and script share the title pattern 'waiting for user'" 0 "grep -q 'waiting for user' $CORE && grep -q '\"waiting for user\"' $HERE/scripts/cleanup_list.py"
check "core and script share the flags --sessions and --active" 0 "grep -q -- '--sessions <that file> --active <local_id>' $CORE && grep -q '\"--sessions\"' $HERE/scripts/cleanup_list.py && grep -q '\"--active\"' $HERE/scripts/cleanup_list.py"
check "core and log script share 'Done when' and 'On a task:'" 0 "grep -q 'Done when' $CORE && grep -q '\"Done when\"' $HERE/scripts/orchestrator_log.py && grep -q '\"On a task:\"' $HERE/scripts/orchestrator_log.py"

exit $RED
