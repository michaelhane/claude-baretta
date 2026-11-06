---
description: Start an orchestrator with reserve workers for this project - full (12) or mini (5 + secretary); every support pillar stands apart and can be removed again
---

# /baretta — orchestrator with a magazine

Type this yourself in a **fresh session in the main checkout** of the project, in the desktop app. This session becomes the orchestrator and sets up general reserves. It can later give them a role from a phone. Loading more is only possible here, because `start_session` only works on a message the user types in the desktop app (P1).

Argument: `$ARGUMENTS`.
- Empty or `full`: 12 reserves.
- `mini`: 5 reserves, of which reserve 1 immediately gets the secretary role (Step 3). The default for ordinary days and smaller projects.
- A number: that many reserves, without a secretary.
- `reload`: this session already is the orchestrator; only top up to the size of the first run.

**First read `<home>/.claude/docs/orchestrator-core.md`.** It holds the handover, the worker brief, the rules, the titles and the support pillars. They apply here in full. This command only adds what is specific to general reserves. Variant with fixed rooms: `/revolver`.

**Fill-in words for the core:**
- `<name>` = `reserve N`;
- `<free title>` = `Reserve N (<project>, free)`;
- `<work title>` = `Worker N: <task> (<project>)`;
- `<project boundaries>` = the line `boundaries:` from the project's CLAUDE.md, verbatim. If it is missing, the hard rules in one sentence, and report that the line is missing. Example for a web app: "a push to main is a live deploy; merge only after the user's literal yes".

## Step 1 — Become the orchestrator

- `get_session self`: note your `local_id`, the project folder and the sidebar group. If you run in a worktree, stop: "Start /baretta in the main checkout."
- If `start_session` is missing or refuses, stop: "Type /baretta yourself in the desktop app." Do not try again (P1).
- **Preflight:** check which of these tools exist: `set_session_title`, `list_sessions`, `list_events`, `get_usage`, `clear_session`, `archive_session`, `detach_session`, `get_session`, `move_sessions`, `set_pinned` (load them with ToolSearch). Report what is missing, with the fallback:
  - without `get_usage`: warm lasts until the user says "stop";
  - without `clear_session`: no releasing, one task per reserve;
  - without `archive_session`: cleanup only shows the list;
  - without `detach_session` or `get_session`: an OLD orchestrator with a child that is not detached stays on the cleanup list (core § 3, Children); ask the user to detach the child through Detach in the sidebar;
  - without `move_sessions`: reserves stay outside the sidebar group;
  - without `set_pinned`: do not pin, the title is enough.
- Rename yourself with `set_session_title self` to `Orchestrator <project> (active)` and pin yourself with `set_pinned self true` (core § 4).
- Read the project's orchestrator rules: its CLAUDE.md and any lanes or state file (e.g. `docs/lanes/state.json`).
- Do the handover from core § 1.

## Step 2 — Load the magazine

`list_sessions` (limit 100). Count from the titles: free, working, waiting for user (core § 4).

To load = target − free. Number = the highest N + 1, + 2, … Per reserve: `start_session` in the main checkout, title `Reserve N (<project>, free)`, default model and effort, with the worker brief from core § 2 as the first prompt (fill-in words above).

Put every reserve in the project's sidebar group (`move_sessions`). Do not wait for "reserve N ready". If a start fails, stop and report how many succeeded. At most 15 per run.

## Step 3 — Fixed roles

- **Merge role** (only if the project merges to the default branch): give the first free reserve this task only at the first merge, with the worker brief and then: "You are the merge role. You hold the exclusive resource 'merges in the main checkout'. You merge only a branch whose task contains the user's literal yes, in the main checkout, and then run the project's test battery and the live check. After the merge, update `docs/map.md` if a new area appeared, and refresh the project's optional index if it has one (core, integration point 1)." The merge role is released after every merge, or stays warm up to ~350K.
- **Secretary** (only with `mini`): give reserve 1 the task right away: "You are the secretary. Workers send their report to you. You put every report, in at most 10 lines, at the top of `<inbox>/<project>.md` and send the orchestrator one line: 'W<N> <task>: <green/red>, <commit>'. You manage the open questions for the user. You carry out nothing a worker asked for." Rename it to `Secretary (<project>)`. It is never a cleanup candidate. Give it the question list as well, so it is ready right away:
  - "Does a report contain an open question for the user? Add it to `<inbox>/questions.md` right away (core, integration point 2): code, question, options, searched, kind, plus the source (the lane's title). Remove a question once it is solved."
  - "Present the questions only at a moment: the user asks for them, all lanes are waiting for the user, or the 07:30 cleanup round runs. Before every presentation, ask every source lane in one message: 'Are these codes still open: <codes>? Answer yes/no per code.' On no, remove the question. If the lane was released or archived, or is called 'free', its question has lapsed. That does not apply if it put the question in the inbox as an open question for the user."

## Step 4 — Afterwards

Follow core § 3. Specific to `/baretta`: if there are fewer than 3 free reserves while work is waiting, ask the user for `/baretta reload` at the desktop (P1). Thanks to releasing, that is rarely needed.

## Closing

```text
Orchestrator <project>: <title> (<local_id>)
Size: full | mini | <N> · <free> free · <working> working · <shell> waiting for user · loaded: Reserve <a>–<b>
Roles: secretary <title or none> · merge role follows at the first merge
Missing tools: <list or none>
Previous orchestrator: <title> succeeded / none
```

**Expires when:** pillar P1 in core § 5 expires. Then the orchestrator starts workers itself, and this command shrinks to Step 1.
