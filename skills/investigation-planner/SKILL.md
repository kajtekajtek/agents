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
   - **Ask targeted questions** only for things you genuinely cannot determine yourself (e.g. exact repro steps, which environment, when it started). **Don't speculate, and don't ask for what you can find in the code.**

2. **Jira (optional)**
   - If a ticket key is provided **and** the Atlassian MCP server is available: read that MCP server's tool descriptors first, then fetch the issue and use its fields for **Problem Description** and any reported symptoms, logs, or repro steps.
   - If MCP is missing or auth fails, proceed from the user's pasted ticket text or ask them to paste the ticket body.

3. **Investigate as far as you can yourself** — this is the heart of the skill:
   - Read `README.md` or project docs if unfamiliar with the repo.
   - **Trace the relevant code paths** end to end: entry points, the functions/modules involved, error handling, edge cases, recent changes (git history/blame) that could explain the behavior.
   - **Reproduce or reason about reproduction** where possible from the code, tests, or sample data.
   - **When the primary evidence is a monitoring aggregate** (a Bugsnag/Sentry error, a log pattern, a metric spike): a single occurrence is not the whole story. **Sample many occurrences before forming hypotheses** and characterize the distribution — across message/value patterns, affected entities, release/version, and time. Then **explicitly test whether it's one bug or several** (distinct message families or value patterns often mean distinct causes) before committing to a single root cause. For Bugsnag specifically, use the **fetching-bugsnag-errors** skill's `--sample N` mode; watch for custom grouping, which makes any one event unrepresentative.
   - For spikes/discoveries: assess feasibility, prototype mentally or with throwaway checks, identify constraints and unknowns.
   - **Form hypotheses only when the evidence supports them.** Don't list speculative guesses to look thorough — a hypothesis belongs here only if you're confident enough that it's plausible and can point to evidence for it. If nothing rises to that bar yet, say so and lean on **Open Questions & Information to Gather** instead. For each hypothesis you do keep, look for evidence that confirms or rules it out, and note what you ruled out and why.

4. **Separate what you found from what's still missing**
   - Capture concrete findings (facts from the repo/evidence).
   - List the **information still needed** and any **open questions** — and be explicit about who can resolve them. Things only the user/environment can provide (production logs, exact repro steps, stack traces, access, metrics, behavior of an external system) and decisions/unknowns that block a confident plan both go in **Open Questions & Information to Gather**.

5. **Write the file**
   - **Path / name**
     - With issue key: `{KEY}.md` (e.g. `PLAT-440.md`).
     - Without ticket: derive a short **kebab-case slug** for the filename (e.g. `ecosio-timeout-investigation.md`); avoid generic names like `plan.md`.
   - **Location**: repository root unless the user specifies another directory.

6. **Fix proposal — only when confident**
   - Include the **Fix Proposal** section with real steps **only if** the investigation has reached a confident understanding of the cause/approach.
   - If you are **not** confident yet, say so explicitly: leave the section as *blocked pending investigation* and point to the **Open Questions & Information to Gather** that must be resolved first. Do not invent a fix to fill the section.

## Output template

Use this structure for section headings (adjust the title line; keep the Implementation Plan section conditional as described above):

```markdown
# [ticket number / problem name]

## Problem Description

[Symptoms or the open question. For bugs: expected vs. actual behavior, when/where it occurs, impact.]

## Investigation So Far

- **What was checked**: code paths traced, files/modules involved, git history, tests, data examined.
- **Findings**: concrete facts established from the repo and available evidence.
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

- (When ready) High-level steps, components to touch (change vs new), and what to test.

## References

- Docs for libraries/frameworks/tools that matter.
- If Atlassian MCP works: link or cite relevant **Confluence** pages when found.
- If GitHub MCP works: repos, commits, or examples that show similar patterns or the offending change.
```

## Quality checks

- [ ] Filename matches issue key or a clear problem slug.
- [ ] **Investigation So Far** reflects real work in the repo (paths/names, findings, what was ruled out) — not a restatement of the problem.
- [ ] **Hypotheses** are evidence-backed and ranked — none listed speculatively.
- [ ] If findings rest on a **monitoring aggregate**, they reflect a **sampled distribution** of occurrences (message/value patterns, entities, release, time) and explicitly address whether it's one bug or several — not a single representative event.
- [ ] **Open Questions & Information to Gather** lists only things the agent genuinely cannot determine itself.
- [ ] **Fix Proposal** is present only when the cause/approach is confidently understood; otherwise clearly marked blocked.
- [ ] **References** lists real links or search leads, not placeholders.
