---
description: Start an orchestrator with fixed rooms for this project (template - Build, Investigate, Review, Docs, Release); one cylinder rule for all rooms
---

# /revolver — orchestrator with fixed rooms (template)

This is a template. Adapt the room table and the cylinder rule to your own project before you use it.

Type this yourself in a **fresh session in the main checkout** of the project, in the desktop app. This session becomes the orchestrator and sets up fixed rooms: sessions with their own trade, their own domain map, their own check and their own prohibitions. Starting rooms is only possible here, because `start_session` only works on a message the user types in the desktop app (P1).

Argument: `$ARGUMENTS`.
- Empty: load the first rooms, Build and Investigate.
- One or more room names (`build`, `investigate`, `review`, `docs`, `release`): load only those. Load Release only for a release round.
- `reload`: this session already is the orchestrator; only load rooms that are gone or had a failed clear.

**First read `<home>/.claude/docs/orchestrator-core.md`.** It holds the handover, the worker brief, the rules, the cleanup rule, the titles and the support pillars. They apply here in full. This command only adds what is specific to the rooms. Variant with general reserves: `/baretta`.

**Fill-in words for the core:**
- `<name>` = `room <trade>`, e.g. `room docs`;
- `<free title>` = `Room <trade> (<project>, free)`;
- `<work title>` = `Room <trade>: <task> (<project>)`;
- `<project boundaries>` = the cylinder rule below, verbatim, as one block;
- inbox = `<inbox>/<project>.md`.

## Cylinder rule (before the worker brief in every task, for every room)

Example; replace it with your project's hard limits.

```text
1. Never push or merge to the default branch. Only the Release room does that, with the user's literal yes.
2. Do not mutate production data and do not restart services.
3. Do not enter passwords, tokens, account numbers or other secrets in a field or a file.
4. No personal data in URLs, query strings, titles or messages to other sessions.
5. Mail and messages only as drafts; the user sends them.
6. An external system with one login (the exclusive resource) is used by only one room at a time.
7. Before every question to the user: search the project's decisions. A hit is "for your information", not a question.
```

## Rooms

| Room | Task | Domain map | Temp. | Done when | Never does |
|---|---|---|---|---|---|
| **Build** | fixes and features, test first, review before the commit | `CLAUDE.md` + `docs/map.md` | lukewarm | the project's test battery exits 0 on its own branch | merging; pushing; mutating production data |
| **Investigate** | reproduce bugs, read logs and issues, answer a question with a source | `docs/map.md` + the issue | lukewarm | the answer is in a file with a source per line; open point closed or turned into a question for the user | changing code; assuming anything without a source |
| **Review** | check a branch for bugs and silent failures | the diff + the task's PRD | cold | review file with findings (or "none") and file:line per finding | fixing things itself; merging |
| **Docs** | update the README, guides and changelog | `docs/` + `CHANGELOG.md` | cold | the project's doc lint or link check exits 0 | changing code |
| **Release** | merges after the user's yes, tags, the live check | `CLAUDE.md` + release process | warm | the live check exits 0 after the merge | merging without a literal yes; two releases at once |

Temperature follows core § 3. Release is warm because the release process is expensive to read in again; it does not release after a task until ~350K.

Every task for a room starts with the cylinder rule and the worker brief (core § 2). Then follow the domain map and the check from its row, the one file that matters, and the task. The "Done when" from the table is the default; a task may make it stricter, not looser.

## Step 1 — Become the orchestrator

- `get_session self`: note your `local_id` and the sidebar group. If you run in a worktree, stop: "Start /revolver in the main checkout."
- If `start_session` is missing or refuses, stop: "Type /revolver yourself in the desktop app." Do not try again (P1).
- **Preflight:** as in `/baretta` Step 1 (`set_session_title`, `list_sessions`, `list_events`, `get_usage`, `clear_session`, `archive_session`, `detach_session`, `get_session`, `move_sessions`, `set_pinned`), with the same fallbacks.
- Rename yourself with `set_session_title self` to `Orchestrator <project> (active)` and pin yourself with `set_pinned self true` (core § 4).
- Read the project's CLAUDE.md. The project's recurring checks stay with you; a room does not start a loop of its own.
- Do the handover from core § 1.

## Step 2 — Load the rooms

`list_sessions` (limit 100). A room already exists if there is a title `Room <trade> (<project>…` that is not `clear failed`. Load only what the argument asks for and does not exist yet.

Per room: `start_session` in the main checkout, title `Room <trade> (<project>, free)`, default model and effort, with the cylinder rule and the worker brief as the first prompt (fill-in words above). Put every room in the sidebar group (`move_sessions`). Do not wait for "room <trade> ready". If a start fails, stop and report which ones succeeded.

An empty room only takes work from its own trade. Work that fits no room: a subagent (light job, core § 3) or a `/baretta` reserve.

## Step 3 — Afterwards

Follow core § 3. Specific to `/revolver`:
- **The exclusive resource** (cylinder rule 6) gets only one room at a time, and that room puts `[holds <resource>]` in its title while it uses it. Give a second task on that resource only after the marker is gone (R1).
- **Questions to the user** are asked only by you; rooms deliver their questions to you. Search the decisions before you ask (cylinder rule 7).
- **Cleanup:** the rooms are fixed rooms and never a candidate (core § 3).
- **Leak check** before you report a status to the user: grep your handoff cards, the questions file and your own messages for secrets and personal data (your project's patterns). Target 0; remove a hit and report it.

## Support pillars (on top of core § 5)

- **R1 — One room per exclusive resource.** The external system refuses two sessions at once. Expires when it offers an API or allows several sessions.
- **R2 — Warm Release room.** The fixed load plus the release process is large. Expires when skills and memory load lazily and a fresh session starts small.

## Closing

```text
Orchestrator <project>: <title> (<local_id>)
Rooms: <trade> free · <trade> working · <trade> waiting for user · not loaded: <list>
Exclusive resource: free | [holds <resource>] at Room <trade>
Missing tools: <list or none>
Previous orchestrator: <title> succeeded / none
```

**Expires when:** the fixed rooms stay empty for a month (room occupancy in the weekly measurement). Then go back to `/baretta` with the cylinder rule as boundaries. If pillar P1 in core § 5 expires, the orchestrator starts rooms itself and this command shrinks to Step 1 and the room table.
