# Orchestrator core — shared by /baretta and /revolver

One source for everything the orchestrator commands do the same way. `/baretta` (general reserves) and `/revolver` (fixed rooms) refer to this file. They do not copy its text. A change here applies to both. `scripts/test_consistency.sh` checks that no command contains a copy.

Rules that lean on a limitation of the app carry a pillar code (§ 5).

Fill-in words: `<home>` (the user's home directory), `<inbox>` (a folder outside every repo, default `<home>/.claude/inbox`), `<project>`, `<local_id>` (of the orchestrator), `<name>` (e.g. `reserve 4` or `room docs`), `<free title>` (e.g. `Reserve 4 (myapp, free)` or `Room docs (myapp, free)`) and `<work title>` (e.g. `Worker 4: <task> (myapp)` or `Room docs: <task> (myapp)`). The command decides which form.

## Integration points

The core names no tool of its own. Three points connect it to your setup; each has a default that works without installing anything. An optional tool may replace the default, but the rules below only lean on the default.

| Integration point | Default (no installation) | Optional |
|---|---|---|
| **1. Finding the file** | `git grep -l <word>` plus the project's `docs/map.md` (one line per area: path, what lives there, neighbours) | a code index of your choice, queried read-only in the main checkout |
| **2. Questions for the user** | one file `<inbox>/questions.md`; per question: code, question, options, searched (where you already looked), kind (decision, approval, only-the-user) | a page of your own that collects the answers |
| **3. Keeping knowledge** | a handoff card `.claude/handoff/<date>-<id>.md` in the main checkout: state, open, next step | a wrap command or hook of your own that writes the card |

A session that finds an optional tool missing falls back to the default, without asking.

## 1. Handover

Was there already an orchestrator (`list_sessions`: title `Orchestrator <project> (active)`, not `OLD`)? Send it one message: "You have been succeeded by <your title> (<local_id>). Rename yourself to 'OLD orchestrator <project> (do not use)' and unpin yourself in the same step with set_pinned (session_id self, pinned false). If you still get a message from the user, answer with one line with the link to me and forward it verbatim. Send me your open tasks, promises and the user's words that are not in git." Write your own id as orchestrator into the project's state file, if there is one. (P6)

After 15 minutes, check with `get_session` that the old one is called `OLD` and has `pinned` false. Note the time of your message on your handoff card (integration point 3) and check every round until it holds. Is it still pinned after 15 minutes? Then put "old one still pinned: <title>" on your card, tell the user in one line, and do not unpin it yourself; only the cleanup round does that later (§ 3, class A). Unpinning another session needs the user's permission, and the old one may still be busy. (P2)

Then send every running worker or lane that still reports to the old orchestrator (or to "the session that started you") one message: "Your report address is now <your title> (<local_id>); write your report to <inbox>/<project>.md and send me one line." Archive an OLD orchestrator only after this is done for all its lanes, otherwise their next report arrives nowhere.

Then detach yourself from the old orchestrator with `detach_session` (session_id self), and then the reserves and workers that still hang under it. `detach_session` only works on `self` or on a session you started yourself. A child of the old orchestrator therefore detaches itself: send it "Call detach_session with session_id self and answer with one line." Before each detach message, check `parentSessionId` and `detached` with `get_session`, and note its sidebar group. Is a session already detached ("already a top-level session")? Then send no detach. Do one session first and check with `get_session` that `detached` is true. `detach_session` can set the sidebar group to null: then move the session back yourself with `move_sessions` to the group you noted (that tool also works on sessions you did not start). If that fails, put `[move back]` at the front of its title (at the end it disappears in the truncated sidebar; a temporary marker the user removes) and tell the user in one line. Only then do the rest. This way no work hangs in the sidebar under a session called "do not use", and archiving it takes nothing along (§ 3, Children). (P2)

**Reread the core.** This core changes while you run. Each round, check whether this file is newer than your last read (`stat -c %y <home>/.claude/docs/orchestrator-core.md`). If so, reread it before you decide anything that leans on it (handover, cleanup, archiving, merging).

**Hand over before you fill up.** Each round, measure your own context with `get_usage` (session_id self). Above ~600K, hand over to a free reserve yourself (well below the limit at which the user wants a fresh session, so the handover itself still has room); do not wait for the user to notice. Do it between two rounds: finish the turn you are in, and hand over running work instead of stopping it. Pick a reserve that was never or just cleared (`list_events` nearly empty) and has `remoteControlActive: true`, because the user must be able to reach the orchestrator from a phone. Send it the worker brief and then: "You are the new orchestrator of <project>. Read <home>/.claude/docs/orchestrator-core.md and this project's command, and do step 1 and the fixed roles. Skip the loading." Then send it your open tasks, promises, the user's words that are not in git, and which workers are busy. Then rename yourself to OLD and unpin yourself (`set_pinned` self false, see above). Tell the user in one line, with the link to the new one. This also works from a phone, because no session is started. A signal to wrap up (from a hook or the user) is no reason for you to stop: write your handoff card (integration point 3) and hand over.

**After the handover:** do the cleanup round of § 3 right away and set your clock.

## 2. Worker brief

This is the first prompt of a new session. It also goes before every task given to a released session, because a clear erases the brief. The command fills in `<project boundaries>` with that project's hard limits. A web app: "a push to main is a live deploy". An administration: "no payments, trades or transfers, no personal data outside files".

```text
You are <name> of the orchestrator of <project> (<local_id>). Do nothing and read nothing until you get a task. Answer only "<name> ready" now.
Project boundaries, which override everything below: <project boundaries>
On a task:
1. Rename yourself with set_session_title (session_id self) to "<work title>". (P2)
2. Work in your own working folder: create a worktree from the default branch with git worktree add, or use the folder named in the task. The shell jumps back to the main checkout after every call: use the absolute path or git -C <folder> in every command. Never write in the main checkout unless the task says so. (P3)
3. Read the domain map from the task first, if there is one. Otherwise read only the files the task names; do not search the repo. If you must find something, use integration point 1 in the main checkout (first line of git worktree list): git grep -l <word> and docs/map.md, with function or variable names, not a sentence. If the project has an optional index, you may query it there, read only. Never build or update an index.
4. Confirm to the orchestrator: role, folder, branch, check. That is your first report.
5. Work until the check from the task ("Done when ...") is green. Commit on your own branch. Never merge or push to the default branch. Only exception: you are the merge role and the task contains the user's literal yes.
6. Put your report at the top of the inbox file named in the task (<inbox>/<project>.md, outside the repo), under a heading "## <work title> - <date time>", and do not commit it. Then send one line to whoever the task names (the orchestrator, or the secretary if there is one): "<name> <task>: green/red, <commit>, report in inbox". The report is at most 10 lines: commit, checks with their result, what you deliberately did not do, open questions for the user. Name files, no sensitive values: no amounts, account numbers, customer names or other personal data. The result of a check (exit 0, a commit hash) is fine.
6b. If you hold an exclusive resource (see the task, for example an external system with one login, or merges in the main checkout), put "[holds <resource>]" after your title and remove it as soon as you are done.
7. Then rename yourself to "<work title> - waiting for user" and do nothing more. Do not take on a new, unrelated task. (P2)
8. If you get "release": put what is still needed later on your domain map or in your report, rename yourself to "<free title>" and call clear_session with session_id self. Say everything you still want to say before that call; afterwards you remember nothing.
```

## 3. Rules for the orchestrator

- **Task:** start with the worker brief (§ 2), then the domain map, the one file that matters, and the task. Put the file in a line `Map: <file + neighbours> (<how you found it>)`, for example `Map: src/render.py L120, mirror web/render.js (git grep -l render_frame)` or `Map: src/render.py (docs/map.md)`. If it comes from the domain map: `Map: domain map`. End with "Done when `<existing command>` `<result>`". No open question without a file. A task only counts as given after the first report.
- **Worker without `start_session` (P1):** if `start_session` refuses (Remote Control or an automatic turn), start the worker through Bash in the main checkout: `claude --bg --name <work-title-slug> "<worker brief + task>"`. It creates its worktree with `git worktree add` (§ 2, step 2), so its session runs in the main checkout. It does not appear in the sidebar but does appear in `ListAgents` (messages both ways), and you count it with `claude agents --json`. Clean up only after the merge or handover: first `claude stop <id>` (a SessionEnd hook then writes its line), then restore `.claude/summaries/sessions.log`, and only then `claude rm <id>`. Restoring in a worktree that is only its own: `git -C <worktree> checkout -- .claude/summaries/sessions.log`. In the main checkout never `git checkout` or `sed -i` (other sessions, CRLF): remove only the lines with its id. Not yet tried: a bg worker that follows the brief and really commits.
- **Finding a file:** integration point 1, in the main checkout: `docs/map.md` first, then `git grep -l <word>` with names, not a sentence. An optional index only where the project already has one, read only (never in repos with sensitive data). If a hit does not come from the files in the question, the map does not cover that part: read directly, say so, and add the line to `docs/map.md` afterwards.
- **Keep the map fresh:** in your first round of the day, check whether `docs/map.md` still names the files that changed since yesterday (`git log --since=yesterday --name-only`). A new area gets a line. If the project has an optional index, refresh it in the main checkout the way that tool documents, or let the merge role do it. Workers never build or update an index.
- **Checking:** after a report, run the check yourself. Red: send back "not done yet: <output>". Green: worker to `- waiting for user`, present it to the user. Merge only after their literal yes, with the word `approved` and that yes in the merge message. (P4)
- **Temperature:** cold = fresh session with only the brief, for one-off tasks. Lukewarm = brief plus domain map, the default for recurring work. Warm = the same worker continues on a series of tasks on the same files, up to ~350K tokens. Measure that with `get_usage` on the worker's session_id while it is busy (an idle session returns "unavailable"). If measuring fails, it continues until the user says "stop". The limit applies between tasks, never in the middle of one: a busy worker finishes its task and reports, even above 350K. It just gets no new task afterwards, but updates its domain map and is released.
- **Releasing:** merged, or closed without open questions: send "release". Count it as free only when `get_session` shows the free title and `list_events` is (nearly) empty. If the transcript is not empty, the clear failed: rename it to `<work title> - clear failed` and report it. A full session titled "free" is exactly the error this check catches.
- **Exclusive resource:** a resource that only one worker at a time can handle gets only one worker at a time. Examples: an external system that allows only one logged-in session, merges and pushes in the main checkout (the merge role). Before every task, check whether another title carries "[holds <resource>]". If so, the new task waits.
- **Light job** (< ~15 min, no commit): a subagent (Agent tool, a smaller model), not a session.
- **Reports through the inbox:** name the project's inbox file in every task: `<inbox>/<project>.md`. It lives outside every repo, so no git noise and no writing in the main checkout. Workers write their report there and send you one line. Read a report only when you need it for your check or for the user. With `mini`, the secretary manages the inbox. (P7)
- **Clean up, every day at 07:30 and right after every handover.** At your start, set one clock: `CronCreate` `30 7 * * *` with the prompt "Cleanup round <project>: `list_sessions` (limit 100, the project's group; without a group all rows) to `<inbox>/<project>-sessions.json`, then `python3 -I <home>/.claude/scripts/cleanup_list.py <main checkout> --sessions <that file> --active <local_id>`, and do what the output says." The clock dies with your session. A successor does the round as its first step after § 1 and sets its own clock. The round costs no reserve, no subagent and no reading test on transcripts. Check the map in the same round (Keep the map fresh).
  **Also when the user says "clean up": first the script, never archive directly.** An orchestrator that archived directly after "clean up" took along sessions that were not done.

  **Classes A–E go without asking:** the standing yes of whoever installed this core, given by installing it and recorded here (remove a class to withdraw it). The script prints the commands per row, in order.
  - A: OLD orchestrator, not `isRunning`, every child already detached or itself class A; the script lists a child that is still attached, and that child calls `detach_session` itself (session_id `self`). § 1 is done: its lanes have the new report address. Commands: `set_pinned` off (the standing yes covers that, also if it stayed pinned after § 1), `archive_session`, after-check; do not send it a wrap request: its conversation is large and its cache has expired.
  - B: worktree older than a day (a fresh one may belong to a `claude --bg` worker) whose branch is in the default branch and without an unarchived session with that cwd. It is clean after restoring `.claude/summaries/sessions.log`, `.claude/settings.local.json` and CRLF-only differences. Then `git worktree remove <path>` (never `--force`).
  - C: title with `DONE`, not `isRunning`, > 2 days idle, no own worktree with work outside the default branch → `archive_session`.
  - D: title starts with `Trial` or `Test`, started by an orchestrator, not `isRunning`, > 1 day idle, no worktree → `archive_session`.
  - E: local branch without a worktree that is in the default branch → `git branch -d` (never `-D`).

  Never a candidate: titles with `free`, the active orchestrator, the secretary, the merge role, fixed rooms, `- waiting for user`, `clear failed`; a shell `waiting for user` older than 2 days only goes on the list. They do nothing because they wait, not because they are done.

  **Children.** `archive_session` silently takes along the sessions this session started that share its worktree or are done. One OLD orchestrator once took the secretary, four workers and a reserve along this way. That is why the script lists a session with a child that is not detached (`startedBy` = its id, `detached` not true). After every `archive_session`, check with `list_sessions` (`include_archived` true) whether a child went along that was not on the list. Restore it with `unarchive_session`.

  **The rest goes, with a one-line reason, in the questions file** (integration point 2), not a file of its own. That is: shells `waiting for user` older than 2 days, sessions without a turn in 7 days, worktrees with their own commit outside the default branch, and OLD sessions with a child that is not detached. Per row: title or path, last turn, the reason from the script, and the choice archive / merge / leave. After the user's yes, carry it out. If they choose "archive", first send that session "Write your handoff card (integration point 3; no merge, push or deploy) and stop". Archive only after that. A branch merged with squash or rebase does not pass `--is-ancestor`: it goes on the list, with the merge commit as proof. Empty list = no question.

  **Leaving it is never the end point:** every list row gets a choice. An open question from that session goes on the page as a question of its own; a promise to another session you report to that session.

  **Fallback "archive!":** if `archive_session` refuses (classifier, "pinned or in use") or the tool is missing, rename the session with `set_session_title` to `archive! <title>` (the script prints the command per row in A, C and D; never a double prefix). The user archives it in the sidebar. In the next round it is again a candidate for `archive_session`. If it refuses again, leave it and do not count it again. Never rename a role title (free, Orchestrator, Secretary, a Worker without `waiting for user` or `DONE`); the script says so per row. If the rename refuses too, it goes on the list.

  **If `unarchive_session` refuses** (classifier), try once more on the user's next turn. If `unarchive_session` still refuses, do not try another way. Tell the user: "<title> is still in Archived; restore it through the Archived list in the desktop app's sidebar." If an open question later turns out to sit in an archived session, ask it anyway (`search_session_transcripts`).

  After every round, report one line: "Cleanup round: N archived, H renamed to archive!, M worktrees removed, K branches removed, L on the list; group <n> sessions, <m> worktrees." Archiving is reversible, removing a worktree is not: hence only class B, and never `--force`.

## 4. Titles

- Orchestrator: `Orchestrator <project> (active)`. Succeeded: `OLD orchestrator <project> (do not use)`.
- Pinned in the sidebar: only the active orchestrator. When you take on the role, rename yourself and call `set_pinned` (session_id self, pinned true). At the handover you unpin yourself (pinned false) in the same step as you call yourself `OLD` (§ 1). Workers, reserves, rooms and the secretary never pin; only a reserve that takes on the orchestrator role pins itself (§ 1, Hand over). Without `set_pinned`: do not pin, the title is enough. (P2)
- Free, working, done: `<free title>`, `<work title>`, `<work title> - waiting for user`.

Always count free sessions by their title, never from memory. A weekly measurement (`scripts/orchestrator_log.py`) finds projects by the orchestrator's title.

## 5. Support pillars (removable)

- **P1 — Starting sessions in advance.** `start_session` only works on a message the user types in the desktop app. Expires when it works from Remote Control or on automatic turns. Until then: `claude --bg` (§ 3, Worker without `start_session`).
- **P2 — Titles as status.** The sidebar shows no role. Expires when the app shows a per-session status the orchestrator can set.
- **P3 — Absolute paths.** The shell jumps back to the main checkout after every call. Expires when a session reliably stays in its working folder.
- **P4 — The orchestrator runs the check.** Whoever builds does not check their own work. Expires when a worker gets an independent check the orchestrator can read.
- **P5 — Expired.** Releasing with `clear_session self` turned out to work, also with Remote Control on. The `list_events` check under Releasing catches a failed clear.
- **P6 — Forwarding by the old orchestrator.** The app knows no successor. Expires when the app can designate a successor.
- **P7 — Inbox (and with mini a secretary).** Every message from a worker lands in full in the orchestrator's context; that is why the report goes to a file and the message is one line. Expires when messages from other sessions no longer land in full in the context.

Review these pillars on every Claude Code release. Remove a pillar only after the user's yes: here, plus every line with its code in the commands.
