# baretta — an orchestrator pattern for Claude Code

**Status: experimental.** This is one person's working setup, shared so others can think along. It runs every day, but it leans on app behaviour that may change with any release. Expect rough edges.

## What it is

A set of Markdown instructions and two small Python scripts that turn one Claude Code session (in the desktop app) into an **orchestrator**. The orchestrator hands tasks to a pool of pre-started **reserve** sessions, checks their work, and cleans up after them. The user stays the architect: they approve merges and answer questions; the orchestrator does the bookkeeping.

## The problem

Running several Claude Code sessions in parallel works, until it doesn't:

- Sessions lose track of who they report to, especially after the coordinating session is replaced.
- A worker's full report lands in the coordinator's context and fills it up.
- Workers check their own work ("tests pass") and nobody verifies.
- Finished sessions, worktrees and branches pile up; cleaning up by hand archives the wrong ones.
- Starting a new session only works from a message typed in the desktop app, so a coordinator reached from a phone cannot start workers.

## Architecture

- **Orchestrator.** One session per project, titled `Orchestrator <project> (active)` and pinned in the sidebar. It gives tasks, runs the check itself after each "green" report, and asks the user before every merge. When its context fills up (~600K tokens) it hands over to a free reserve and renames itself `OLD orchestrator <project> (do not use)`.
- **Reserves.** Sessions started in advance (`/baretta` loads 12, or 5 with `mini`) that wait idle with a short brief. A reserve that gets a task renames itself to a work title, works in its own git worktree, commits on its own branch, and never merges. When released, it clears itself and is free again.
- **Worker brief.** One fixed first prompt for every reserve (core § 2): rename, own worktree, read only the files named in the task, confirm, work until the task's `Done when <command> <result>` check is green, write the report to an inbox file outside the repo, send one line, wait.
- **The core as the single source.** `core/orchestrator-core.md` holds everything both commands share: handover, the worker brief, the rules, titles and support pillars. The commands only add what is specific to them and refer to the core instead of copying it. `scripts/test_consistency.sh` fails if a command copies the brief.
- **Support pillars with "Expires when".** Every rule that only exists to work around an app limitation carries a code (P1–P7) and an *"Expires when"* line naming the feature that would make it unnecessary. Example: P1, starting sessions in advance, expires when sessions can be started from Remote Control. Review the pillars on each release and delete the ones that have expired. Good scaffolding should be easy to take down.
- **Cleanup classes A–E.** `scripts/cleanup_list.py` reads `list_sessions` output plus git state, and prints the commands per row. It never runs them itself. Classes A–E are removed without asking, under a standing yes the user gave once:
  - A: old orchestrators that are idle and have no attached children;
  - B: merged, clean worktrees older than a day (never `--force`);
  - C: `DONE` sessions idle for more than 2 days;
  - D: `Trial`/`Test` sessions started by an orchestrator;
  - E: merged local branches without a worktree (`git branch -d`, never `-D`).

  Everything else goes on a list for the user to decide. Roles such as free reserves, the secretary and sessions waiting for the user are never candidates.
- **Pinning.** Only the active orchestrator is pinned in the sidebar. It unpins itself in the same step in which it renames itself `OLD`, so the sidebar always shows exactly one entry point, also from a phone.
- **Measuring.** `scripts/orchestrator_log.py` reads orchestrator transcripts and prints only numbers: report sizes, how many green reports the orchestrator checked itself, rule breaks such as a merge without `approved` or `worktree remove --force`. It never prints transcript text.

## Integrations

The core names no tool of its own. It connects to your setup at three points, each with a default that works without installing anything. Replace a default with your own tool if you like; the instructions only lean on the default.

| Integration point | Default (no installation) | Optional example |
|---|---|---|
| Finding the file | `git grep -l <word>` plus a hand-kept `docs/map.md` (path, what lives there, neighbours) | a code knowledge graph such as [graphify](https://github.com/safishamsi/graphify), only if the repo already has a `graphify-out/` folder |
| Questions for the user | one file `<inbox>/questions.md`; per question: code, question, options, searched, kind | your own answer page that stores the answers |
| Keeping knowledge | a handoff card `.claude/handoff/<date>-<id>.md`: state, open, next step | your own wrap command or hook that writes the card |

A task names the file it found in one line: `Map: <file + neighbours> (<how you found it>)`.

## The names

- **`/baretta`**: a magazine of general-purpose reserves; any reserve can take any task.
- **`/revolver`**: a cylinder of fixed *rooms*, each with its own domain map, check and prohibitions, plus one *cylinder rule* that goes before every task. The version here is a template with generic rooms (Build, Investigate, Review, Docs, Release); adapt it to your project.

## Layout

```
core/orchestrator-core.md   the shared core (single source)
commands/baretta.md         slash command: orchestrator with general reserves
commands/revolver.md        slash command template: orchestrator with fixed rooms
scripts/cleanup_list.py     cleanup list, read-only (classes A–E)
scripts/orchestrator_log.py weekly measurement from transcripts, numbers only
scripts/test_*.sh           tests; exit 0 = green
```

## Installation

Copy the files into your Claude Code config directory:

```bash
mkdir -p ~/.claude/docs ~/.claude/commands ~/.claude/scripts ~/.claude/inbox
cp core/orchestrator-core.md ~/.claude/docs/
cp commands/baretta.md commands/revolver.md ~/.claude/commands/
cp scripts/cleanup_list.py scripts/orchestrator_log.py ~/.claude/scripts/
```

The texts use fill-in words: `<home>` is your home directory, `<inbox>` a folder outside every repo (default `<home>/.claude/inbox`), `<project>` the project name. Then type `/baretta mini` in a fresh session in the main checkout of a project, in the Claude Code desktop app. It relies on the desktop app's session tools (`start_session`, `list_sessions`, `set_session_title`, `clear_session`, `archive_session`, `set_pinned`, …). The command's preflight reports which are missing and what it falls back to.

Run the tests (Git Bash on Windows, or any bash with Python 3):

```bash
bash scripts/test_consistency.sh
bash scripts/test_cleanup_list.sh
bash scripts/test_orchestrator_log.sh
```

## Contributing

Issues and pull requests are welcome, as **proposals**: the maintainer adopts what fits this setup and may rework or decline the rest. A proposal that removes a support pillar because a new Claude Code feature made it unnecessary is the most welcome kind.

## License

MIT; see [LICENSE](LICENSE).
