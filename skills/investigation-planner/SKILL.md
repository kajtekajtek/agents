---
name: investigation-planner
description: Turns a Jira issue key or free-form bug/spike/discovery description into a single markdown investigation file (problem, investigation findings, evidence-backed hypotheses, open questions and information to gather, and a fix proposal only once enough is known). Use when the task is a bug, spike, or technical discovery where the root cause or feasibility is unknown and must be investigated before implementation. For features or refactors where the work is mostly understood, use feature-planner instead.
---

# Investigation planner

## When to use

- The task is a **bug**, **spike**, or **technical discovery** — the root cause, feasibility, or correct approach is **not yet known** and must be investigated before any implementation can be planned.
- User provides a **Jira key** (e.g. `PLAT-440`) or describes a bug/unknown without a ticket.
- User asks to **investigate**, **find the root cause**, **scope an unknown**, or plan work that can't be sensibly planned until the problem is understood.

For **features or refactors** where the desired behavior is known and the main question is *how to build it*, use **feature-planner** instead.

## Core principle

**Investigate first, plan implementation last.** Do not jump to a fix or implementation plan while the problem is still poorly understood — that is the failure mode this skill exists to prevent. Exhaust what *you* can determine from the code and available evidence, form hypotheses, and only write an implementation plan once you are genuinely confident you understand the cause/approach. Until then, the deliverable is the investigation itself plus a clear list of what still needs to be learned.

## Workflow

1. **Clarify input**
   - If only a ticket key is given, treat summary, description, and any attached logs/repro steps from Jira as the starting evidence.
   - If the user describes the problem in chat, use that text.
   - **Ask up front only what blocks you from starting at all** (e.g. which repo, which of two systems they mean). Everything else you *think* you need — repro steps, environments, log access — is often answerable from the code, and what genuinely isn't will be obvious only after you've looked. Collect those in **Open Questions & Information to Gather** and put them to the user once, at the end. **Don't speculate, and don't ask for what you can find in the code.**

2. **Jira (optional)**
   - If a ticket key is provided **and** the Atlassian MCP server is available: read that MCP server's tool descriptors first, then fetch the issue and use its fields for **Problem Description** and any reported symptoms, logs, or repro steps.
   - If MCP is missing or auth fails, proceed from the user's pasted ticket text or ask them to paste the ticket body.

3. **Delegate the heavy exploration** — this is the biggest token cost in this skill, and none of it needs to live in your context once it has produced a conclusion.

   Split the investigation into independent questions (one per code path, one for "what changed", one for the monitoring sample, one per candidate subsystem) and dispatch each to a subagent — `Explore` for locating code, `general-purpose` when it must run commands or read deeply. Run independent ones concurrently in a single message. Investigate directly only when the question is a one-shot lookup you already know the file for.

   Give each subagent the problem statement, its one question, and this required return shape (final message only, nothing else):

   ```
   {
     "findings": ["<fact> — evidence: <path/File.kt:120 | commit sha | event id>"],
     "ruled_out": ["<what was considered> — <why it's eliminated>"],
     "still_unknown": ["<what it could not determine from the repo>"]
   }
   ```

   Keep the conclusions and evidence anchors; let the file dumps, diffs, and raw JSON stay in the subagent.

4. **Investigation moves** — the ones that pay off most, roughly in order:
   - Read `README.md` or project docs if unfamiliar with the repo.
   - **Ask "what changed?" first.** For anything that used to work, this is usually the whole answer: compare first-seen timestamp against deploys/releases, then `git log`/`git blame` the suspect paths. Cheap, and it either hands you the cause or eliminates a regression outright.
   - **Trace the relevant code paths** end to end: entry points, the functions/modules involved, error handling, edge cases.
   - **Prefer an executable check over reasoning.** A failing test, a throwaway script, or a query settles in one run what a paragraph of inference only makes plausible. Record the command and its output as evidence. "Reason about reproduction" is the fallback when nothing is runnable — not the default.
   - **When the primary evidence is a monitoring aggregate** (a Bugsnag/Sentry error, a log pattern, a metric spike): a single occurrence is not the whole story. Sample many occurrences, characterize the distribution, and explicitly test whether it's one bug or several before committing to a root cause — see `references/monitoring-evidence.md`.
   - For spikes/discoveries: assess feasibility, prototype with throwaway checks, identify constraints and unknowns.
   - For a bug that reproduces but resists explanation, **superpowers:systematic-debugging** is the sharper tool — use it, then bring its result back here.

5. **Form hypotheses only when the evidence supports them.** Don't list speculative guesses to look thorough — a hypothesis belongs here only if you're confident enough that it's plausible and can point to evidence for it. If nothing rises to that bar yet, say so and lean on **Open Questions & Information to Gather** instead. For each hypothesis you keep, name the **cheapest observation that would discriminate it from the others**, and make that your next investigation step — a ranked list is an investigation order, not a summary. Note what you ruled out and why.

6. **Know when to stop.** Stop investigating and write the file when either:
   - the remaining unknowns can only be resolved by the user or the environment (production logs, access, an external system's behavior, a product decision); or
   - two consecutive investigation steps produce nothing that changes the hypothesis ranking.

   Stopping is not failure — a well-evidenced "here are the two candidates and the one log line that separates them" is a complete deliverable. Do not keep digging to avoid writing an incomplete-looking file.

7. **Separate what you found from what's still missing**
   - Capture concrete findings (facts from the repo/evidence).
   - List the **information still needed** and any **open questions** — and be explicit about who can resolve them. Things only the user/environment can provide (production logs, exact repro steps, stack traces, access, metrics, behavior of an external system) and decisions/unknowns that block a confident plan both go in **Open Questions & Information to Gather**.

8. **Write the file**
   - **Path / name**
     - With issue key: `{KEY}.md` (e.g. `PLAT-440.md`).
     - Without ticket: derive a short **kebab-case slug** for the filename (e.g. `ecosio-timeout-investigation.md`); avoid generic names like `plan.md`.
   - **Location**: repository root unless the user specifies another directory. If the repo has a gitignored scratch directory (e.g. `./tmp/`), prefer it — an investigation file shouldn't land in someone's next commit.

9. **Fix proposal — only when confident**
   - Include the **Fix Proposal** section with real steps **only if** the investigation has reached a confident understanding of the cause/approach.
   - If you are **not** confident yet, say so explicitly: leave the section as *blocked pending investigation* and point to the **Open Questions & Information to Gather** that must be resolved first. Do not invent a fix to fill the section.

10. **Resuming an investigation** — when the user comes back with answers, logs, or a repro, the file is the working document, not a one-shot report:
    - Re-read the existing `{KEY}.md` first and **update it in place**. Never start a second file for the same problem.
    - Fold new evidence into **Investigation So Far**, re-rank or eliminate **Hypotheses** (moving dead ones to *Ruled out* with the reason), and strike answered items from **Open Questions & Information to Gather**.
    - Re-check step 9: newly-resolved questions are usually what unblocks the **Fix Proposal**.

## Output template

Use this structure for section headings (adjust the title line; keep the **Fix Proposal** section conditional as described above):

```markdown
# [ticket number / problem name]

**Status**: Investigating | Root cause identified | Blocked on [what]
**TL;DR**: [one line — where this stands, so nobody has to read the file to find out]

## Problem Description

[Symptoms or the open question. For bugs: expected vs. actual behavior, when/where it occurs.]

**Impact & scope**: how often, who/what is affected, and since when (first-seen vs. release/deploy). Write "unknown" rather than guessing.

## Investigation So Far

- **What was checked**: code paths traced, files/modules involved, git history, tests, data examined.
- **Findings**: concrete facts, each anchored to its evidence — `path/File.kt:120`, a commit sha, an event id, or the command run and its output.
- **Ruled out**: what was considered and eliminated, with the reason.

## Hypotheses

> Include only hypotheses you're confident enough to back with evidence. If none qualify yet, write "None yet — see Open Questions & Information to Gather" rather than speculating.

- [Ranked most→least likely.] Each with **evidence for** / **evidence against**, and what would confirm or refute it.

## Open Questions & Information to Gather

- Things that can't be determined from the code and must be collected by the user or from the environment:
  - Logs / stack traces / metrics (specify which, from where).
  - Exact reproduction steps or a failing case.
  - Environment, version, or config details.
  - Behavior of external systems / access needed.
- Decisions or unknowns that block forming a confident plan.

## Fix Proposal

> Include real steps ONLY when the cause/approach is confidently understood.
> Otherwise: **Blocked pending investigation** — resolve the items in *Open Questions & Information to Gather* first.

- (When ready) High-level steps and components to touch (change vs new) — no line-by-line design.
- **Blast radius**: what else the change can affect.
- **How it's verified**: the check that fails now and passes after the fix.
- If the fix is big enough to need a plan of its own, stop here and hand off to **feature-planner** or plan mode.

## References

- Docs for libraries/frameworks/tools that matter.
- If Atlassian MCP works: link or cite relevant **Confluence** pages when found.
- If GitHub MCP works: repos, commits, or examples that show similar patterns or the offending change.
```

## Quality checks

- [ ] Filename matches issue key or a clear problem slug, and the file opens with a **Status** line and TL;DR.
- [ ] **Impact & scope** is filled in or explicitly marked unknown — not guessed.
- [ ] Heavy exploration was delegated to subagents — raw file dumps and diffs aren't sitting in the main conversation.
- [ ] **Investigation So Far** reflects real work in the repo (paths/names, findings, what was ruled out) — not a restatement of the problem.
- [ ] Every finding is anchored to concrete evidence (path/line, commit, event id, or command output).
- [ ] **Hypotheses** are evidence-backed and ranked — none listed speculatively.
- [ ] If findings rest on a **monitoring aggregate**, they reflect a **sampled distribution** of occurrences (message/value patterns, entities, release, time) and explicitly address whether it's one bug or several — not a single representative event.
- [ ] **Open Questions & Information to Gather** lists only things the agent genuinely cannot determine itself.
- [ ] **Fix Proposal** is present only when the cause/approach is confidently understood; otherwise clearly marked blocked. When present, it stays high level and says how the fix is verified.
- [ ] **References** lists real links or search leads, not placeholders.
- [ ] Resuming an existing investigation updated the same file rather than creating a new one.
