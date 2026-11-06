"""Cleanup list for an orchestrator: what may go without asking (classes A-E), what goes to the user.

Core § 3 "Clean up" calls this script.
Read only: the script runs only git read commands (status without optional locks)
and never carries anything out. It prints the commands; the orchestrator runs them.

Usage:
  python -I cleanup_list.py <main checkout> [--sessions <list_sessions.json>] [--count] [--limit 100]
  --sessions  output of list_sessions (a list or {"sessions": [...]}); without this file
              A, C and D stay empty and worktrees go to the list (live session unknown).
  --count     only the counts (for a weekly measurement).
  --now       ISO timestamp instead of now (for the test).
  --active    sessionId of the active orchestrator (never a candidate).

Classes (the user's standing yes, core § 3):
  A  OLD orchestrator, not running, every child detached or itself class A
  B  worktree older than a day, in the default branch, clean after restoring sessions.log,
     settings.local.json and CRLF-only differences, without an unarchived session with that cwd
  C  title with DONE, not running, > 2 days idle, no own worktree with work outside the default branch
  D  title starts with Trial/Test, started by an orchestrator, not running, > 1 day idle, no worktree
  E  local branch without a worktree that is in the default branch (git branch -d, never -D)

Expires when: the desktop app itself cleans up finished sessions and merged worktrees, with
a configurable rule per project.
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys

RESTORE = (".claude/summaries/sessions.log", ".claude/settings.local.json")
PREFIX = "archive!"
ORCH = re.compile(r"^(OLD )?orchestrator", re.I)
FREE = re.compile(r"\bfree\b", re.I)


def git(folder, *args):
    r = subprocess.run(["git", "--no-optional-locks", "-C", folder, *args], capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout


def norm(p):
    p = (p or "").replace("\\", "/").rstrip("/")
    m = re.match(r"^/([a-zA-Z])/(.*)", p)
    if m:
        p = f"{m.group(1)}:/{m.group(2)}"
    return p.lower()


def default_branch(main):
    _, remotes = git(main, "remote")
    if "origin" in remotes.split():
        rc, out = git(main, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
        if rc == 0 and out.strip():
            return out.strip()
        for b in ("origin/main", "origin/master"):
            if git(main, "rev-parse", "--verify", "-q", b)[0] == 0:
                return b
    for b in ("main", "master"):
        if git(main, "rev-parse", "--verify", "-q", b)[0] == 0:
            return b
    return None


def worktrees(main):
    _, out = git(main, "worktree", "list", "--porcelain")
    res, cur = [], None
    for line in out.splitlines() + [""]:
        if not line:
            if cur:
                res.append(cur)
            cur = None
            continue
        key, _, value = line.partition(" ")
        if key == "worktree":
            cur = {"path": value}
        elif cur is not None:
            cur[key] = value or True
    return res[1:]  # the first one is the main checkout


def check_worktree(wt, default, merged):
    """Returns (merged, restore, dirty_reason). dirty_reason None = clean after restoring."""
    path = wt["path"]
    br = wt.get("branch", "")
    br = br[len("refs/heads/"):] if br.startswith("refs/heads/") else ""
    if br:
        in_default = br in merged
    else:
        in_default = git(path, "merge-base", "--is-ancestor", "HEAD", default)[0] == 0
    rc, out = git(path, "status", "--porcelain")
    if rc != 0:
        return in_default, [], "git status fails"
    restore, dirty = [], []
    for line in out.splitlines():
        code, name = line[:2], line[3:].strip().strip('"')
        if code == "??" or "R" in code or "D" in code or "A" in code or "U" in code:
            dirty.append(name)
        elif name in RESTORE:
            restore.append(name)
        elif git(path, "diff", "--quiet", "--ignore-cr-at-eol", "HEAD", "--", name)[0] == 0:
            restore.append(name)  # line endings only
        else:
            dirty.append(name)
    reason = None
    if dirty:
        reason = f"not clean: {', '.join(dirty[:3])}{' …' if len(dirty) > 3 else ''}"
    return in_default, restore, reason


def when(s):
    try:
        return dt.datetime.fromisoformat((s or "").replace("Z", "+00:00"))
    except ValueError:
        return None


def never(t):
    k = t.lower()
    return (bool(FREE.search(t)) or "waiting for user" in k or "clear failed" in k or k.startswith("secretary")
            or "merge role" in k or k.startswith("room ") or bool(re.match(r"^orchestrator .*\(active\)", k)))


def role_title(t):
    """Title of a live role: never rename it to 'archive!' (free, Orchestrator, Secretary,
    Worker without 'waiting for user' or 'DONE')."""
    k = t.lower()
    return (bool(FREE.search(t)) or k.startswith("orchestrator") or k.startswith("secretary")
            or (k.startswith("worker") and "waiting for user" not in k and "DONE" not in t))


def make_list(main, sessions, now, limit, active_id=None):
    main_n = norm(main)
    default = default_branch(main)
    if not default:
        raise SystemExit(f"no default branch found in {main}")
    _, out = git(main, "branch", "--merged", default, "--format=%(refname:short)")
    merged = set(out.split())
    wts = worktrees(main)
    wt_path = {norm(w["path"]): w for w in wts}
    for s in sessions:  # "archive! <title>" = fallback from a previous round: classify on the title behind it
        t = s.get("title") or ""
        if t.lower().startswith(PREFIX) and "origTitle" not in s:
            s["origTitle"], s["title"] = t, t[len(PREFIX):].lstrip()
    by_id = {s.get("sessionId"): s for s in sessions}
    live = [s for s in sessions if not s.get("isArchived")]
    own = [s for s in live if norm(s.get("cwd")).startswith(main_n) or norm(s.get("cwd")) in wt_path]
    children = {}
    for s in live:
        if s.get("startedBy"):
            children.setdefault(s["startedBy"], []).append(s)
    full = sessions and len(sessions) >= limit
    out_ = {k: [] for k in "ABCDE"}
    rows = []

    def days(s):
        t = when(s.get("lastActivityAt"))
        return (now - t).total_seconds() / 86400 if t else 0

    def row(s, reason):
        rows.append((s.get("title", ""), (s.get("lastActivityAt") or "?")[:16], reason))

    # worktree checks, once
    wt_info = {}
    for w in wts:
        if w.get("prunable") or w.get("locked") or w.get("bare"):
            wt_info[norm(w["path"])] = (False, [], "prunable" if w.get("prunable") else "locked")
            continue
        wt_info[norm(w["path"])] = check_worktree(w, default, merged)

    def wt_work(s):
        """Reason if the cwd of s is a worktree with work outside the default branch, else None."""
        c = norm(s.get("cwd"))
        if c not in wt_info:
            return None
        ind, _, dirty = wt_info[c]
        return dirty or (None if ind else f"worktree with own commit outside {default}")

    # A: OLD orchestrators, with a fixed-point computation for children that are class A themselves
    old = {s["sessionId"] for s in own if s.get("title", "").upper().startswith("OLD") and not s.get("isRunning")}
    changed = True
    while changed:
        changed = False
        for sid in list(old):
            stuck = [k for k in children.get(sid, []) if not k.get("detached") and k["sessionId"] not in old]
            if stuck:
                old.discard(sid)
                changed = True
    archived = set(old)  # everything archived this round may go along as a child
    for s in own:
        t = s.get("title", "")
        if t.upper().startswith("OLD"):
            if s.get("isRunning"):
                row(s, "OLD but busy (isRunning)")
            elif full:
                row(s, f"OLD, but the session list is full ({limit}): children uncertain, raise the limit")
            elif s["sessionId"] in old:
                out_["A"].append(s)
            else:
                stuck = [k.get("title", "?") for k in children.get(s["sessionId"], [])
                         if not k.get("detached") and k["sessionId"] not in old]
                row(s, f"OLD with a child still attached: {'; '.join(stuck[:3])} (child: detach_session self)")
    # C and D
    for s in own:
        t, sid = s.get("title", ""), s["sessionId"]
        if t.upper().startswith("OLD") or sid == active_id:
            continue
        if "waiting for user" in t.lower():
            if days(s) > 2:
                row(s, f"waiting for user, {days(s):.0f} days")
            continue
        if never(t) or s.get("isRunning"):
            continue
        cls, reason = None, None
        if "DONE" in t:
            if days(s) <= 2:
                continue
            reason = wt_work(s)
            cls = None if reason else "C"
        elif re.match(r"^(trial|test)\b", t, re.I):
            starter = by_id.get(s.get("startedBy") or "")
            if days(s) <= 1:
                continue
            if not starter:
                reason = "Trial/Test, but the starter is not in the session list"
            elif not ORCH.match(starter.get("title", "")):
                if days(s) <= 7:
                    continue
                reason = f"Trial/Test from a non-orchestrator, {days(s):.0f} days idle"
            elif norm(s.get("cwd")) != main_n:
                reason = "Trial/Test with own worktree"
            else:
                cls = "D"
        elif days(s) > 7:
            reason = f"no turn in {days(s):.0f} days"
        if cls:
            stuck = [k.get("title", "?") for k in children.get(sid, []) if not k.get("detached")]
            if full:
                row(s, f"class {cls}, but the session list is full ({limit}): children uncertain")
            elif stuck:
                row(s, f"class {cls}, but child still attached: {'; '.join(stuck[:3])}")
            else:
                out_[cls].append(s)
                archived.add(sid)
        elif reason:
            row(s, reason)
    # B: worktrees
    for w in wts:
        n = norm(w["path"])
        ind, restore, dirty = wt_info[n]
        br = (w.get("branch") or "")[len("refs/heads/"):] or "(detached)"
        sess = [s for s in live if norm(s.get("cwd")) == n and s["sessionId"] not in archived]
        if dirty in ("prunable", "locked"):
            reason = f"worktree {dirty}"
        elif not ind:
            _, cnt = git(main, "rev-list", "--count", f"{default}..{w.get('HEAD', 'HEAD')}")
            reason = f"own commit outside {default} ({cnt.strip()}), branch {br}"
        elif dirty:
            reason = dirty
        elif now.timestamp() - os.path.getmtime(os.path.join(w["path"], ".git")) < 86400:
            reason = "fresh worktree (< 1 day): may belong to a bg worker without its own session"
        elif not sessions:
            reason = "merged and clean, but sessions unknown (pass --sessions)"
        elif sess:
            reason = f"merged and clean, but live session: {sess[0].get('title', '?')}"
        else:
            out_["B"].append((w["path"], restore, br))
            continue
        rows.append((w["path"], "-", reason))
    # E: branches without a worktree that are in the default branch
    with_wt = {(w.get("branch") or "")[len("refs/heads/"):] for w in wts}
    _, main_br = git(main, "branch", "--show-current")
    with_wt.add(main_br.strip())
    local_default = default.split("/", 1)[-1]
    for b in sorted(merged):
        if b and b not in with_wt and b != local_default and not b.startswith("("):
            out_["E"].append(b)
    return default, wts, wt_info, own, out_, rows


def render(main, default, out_, rows):
    r = [f"# Cleanup list {main} (default branch {default})", "",
         "Classes A-E: the user's standing yes (core § 3). Run the commands per row, in order.", ""]

    def session_block(k, heading, unpin_too):
        r.append(f"## {k}. {heading}: {len(out_[k])}")
        for s in out_[k]:
            sid = s["sessionId"]
            title = s.get("origTitle") or s.get("title", "")
            r.append(f"- {title} ({sid}), last turn {(s.get('lastActivityAt') or '?')[:16]}")
            step = 1
            if s.get("pinned") or unpin_too:
                r.append(f"  {step}. set_pinned session_id={sid} pinned=false")
                step += 1
            r.append(f"  {step}. archive_session session_id={sid}")
            r.append(f"  {step + 1}. list_sessions include_archived=true: a row with startedBy={sid} and isArchived "
                     f"that is not on this list → unarchive_session")
            if role_title(s.get("title", "")):
                r.append("  fallback: role title, never rename; if archive_session refuses, it goes on the list")
            elif s.get("origTitle"):
                r.append("  fallback: already renamed; if archive_session refuses again, leave it (the user archives)")
            else:
                r.append(f"  fallback (archive_session refuses or is missing): set_session_title session_id={sid} "
                         f"title=\"archive! {title}\"; if that refuses too, it goes on the list")
        r.append("")

    session_block("A", "OLD orchestrators", True)
    r.append(f"## B. Merged, clean worktrees: {len(out_['B'])}")
    for path, restore, br in out_["B"]:
        r.append(f"- {path} (branch {br})")
        step = 1
        if restore:
            r.append(f"  {step}. git -C \"{path}\" checkout -- {' '.join(restore)}")
            step += 1
        r.append(f"  {step}. git -C \"{main}\" worktree remove \"{path}\"   (never --force)")
    r.append("")
    session_block("C", "DONE sessions, > 2 days idle", False)
    session_block("D", "Trial/Test from an orchestrator, > 1 day idle", False)
    r.append(f"## E. Merged branches without a worktree: {len(out_['E'])}")
    for b in out_["E"]:
        r.append(f"- git -C \"{main}\" branch -d {b}   (never -D)")
    r.append("")
    r.append(f"## List (the user chooses: archive / merge / leave): {len(rows)}")
    for name, at, reason in rows:
        r.append(f"- {name} | {at} | {reason}")
    return "\n".join(r)


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # python -I on Windows: cp1252 and lone surrogates
    ap = argparse.ArgumentParser()
    ap.add_argument("main_checkout")
    ap.add_argument("--sessions")
    ap.add_argument("--count", action="store_true")
    ap.add_argument("--limit", type=int, default=100)
    ap.add_argument("--now")
    ap.add_argument("--active", help="sessionId of the active orchestrator (never a candidate)")
    a = ap.parse_args()
    now = when(a.now) if a.now else dt.datetime.now(dt.timezone.utc)
    sessions = []
    if a.sessions:
        with open(a.sessions, encoding="utf-8-sig") as f:
            d = json.load(f)
        sessions = d.get("sessions", []) if isinstance(d, dict) else d
    default, wts, wt_info, own, out_, rows = make_list(a.main_checkout, sessions, now, a.limit, a.active)
    if a.count:
        mer = sum(1 for v in wt_info.values() if v[0])
        clean = sum(1 for v in wt_info.values() if v[0] and not v[2])
        old = sum(1 for s in own if s.get("title", "").upper().startswith("OLD"))
        waiting = sum(1 for s in own if "waiting for user" in s.get("title", "").lower())
        print(f"sessions {len(own) if sessions else '?'}, OLD {old}, waiting {waiting}; "
              f"worktrees {len(wts)} (merged {mer}, clean {clean}); "
              + ", ".join(f"{k} {len(v)}" for k, v in out_.items()) + f", list {len(rows)}")
        return
    print(render(a.main_checkout, default, out_, rows))


if __name__ == "__main__":
    main()
