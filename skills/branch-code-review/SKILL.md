---
name: branch-code-review
description: Reviews code changes on a git branch by combining Jira ticket context, git diff, and optional PR details, reporting findings via ReportFindings. Use when the user asks for a code review, wants to review a branch, mentions a Jira key with branch changes, or asks to review a PR or diff. Validates unresolved bot review threads on the PR, resolving false positives. Supports --fix (apply findings to the working tree) and --comment (post findings as inline PR comments).
---

# Branch Code Review

## When to use

- User provides a **Jira key** (e.g. `PLAT-605`) or link to the ticket, and a **branch name** (or the current branch is the feature branch).
- User asks to **review changes**, **review a branch**, or **review a PR**.

## Flags

Parse these from the user's invocation (e.g. `PLAT-605 --fix --comment`):

- `--fix` — apply Blocking/Should-fix findings to the working tree (step 8). Nits are left alone unless asked.
- `--comment` — post each finding as an inline PR review comment (step 9). Requires an open PR.

Both can be combined. With neither, the skill reports findings and — if a PR exists — still validates bot review threads (step 6).

## Workflow

### 1. Gather inputs

- **Jira ticket key** (required) — e.g. `PLAT-605`
- **Branch name** — default to current branch (`git rev-parse --abbrev-ref HEAD`)
- **Linked tickets** — note any spike/parent keys the user mentions

### 2. Fetch Jira context

Fetch the primary ticket (and linked spike/parent, if mentioned) via Atlassian MCP. If the tool takes a fields filter, request only `summary`, `description`, `acceptance criteria`, and `linked issues` — skip changelog/attachments/watchers payloads you won't use. If MCP is unavailable, ask the user to paste the ticket description.

### 3. Fetch PR info (if a PR exists)

```bash
gh pr view --json number,title,url
gh repo view --json owner,name -q '.owner.login + "/" + .name'
```

Only pull `reviews,comments` as well if `--comment` is set (needed to avoid posting duplicate comments in step 9). If no PR exists, skip silently — and skip bot-thread validation (step 6) too.

### 4. Delegate the diff review to a subagent

The diff itself is the biggest token cost in this skill and has no reason to live in your main context for the rest of the conversation. Dispatch it instead of reading it directly:

Spawn `Agent` (subagent_type `general-purpose`, foreground — you need its result before continuing) with a prompt that includes:
- The ticket summary, description, and acceptance criteria from step 2
- The branch/commit range to diff: `origin/main...HEAD` (or `origin/main...<branch-name>` if reviewing a branch other than the current one)
- Instructions to: run `git diff --stat` first to gauge size, then the full diff excluding generated/lockfiles (e.g. `git diff origin/main...HEAD -- . ':!*.lock' ':!package-lock.json' ':!*.min.js' ':!pnpm-lock.yaml' ':!yarn.lock'`)
- Instructions to run SonarQube static analysis as a second opinion (see [SonarQube CLI](#sonarqube-cli) below), passing the PR number from step 3 if there is one
- If a PR exists: instructions to fetch and validate unresolved bot review threads (see [Bot review threads](#bot-review-threads) below), passing `owner/repo` and the PR number
- The review checklist: correctness/logic, edge cases and error handling, style/consistency, test coverage, security/performance, adherence to the acceptance criteria
- The severity model: Blocking (correctness/security/build issues that must be fixed before merge), Should-fix (strong improvement, address in this PR), Nit (minor, optional)
- The exact return shape needed (see below) — ask it to return this as its final answer, nothing else

Required return shape (plain text/JSON in the subagent's final message):
```
{
  "implementation_overview": "<files/modules touched, key decisions, grounded in the ticket>",
  "sonar": "<quality gate verdict and failing conditions, or 'skipped: <reason>'>",
  "bot_threads": [
    {
      "thread_id": "PRRT_...", "author": "copilot-pull-request-reviewer",
      "file": "...", "line": 42,
      "verdict": "valid | false_positive",
      "reason": "<one or two sentences, grounded in the code>"
    }
  ],
  "findings": [
    {
      "file": "...", "line": 42,
      "summary": "Blocking: ...",
      "failure_scenario": "...",
      "short_summary": "...",
      "category": "correctness"
    }
  ]
}
```

#### SonarQube CLI

`sonar` (SonarQube CLI, already authenticated against SonarQube Cloud) catches rule-based bugs, code smells, and security hotspots the manual review can miss. The subagent should run it, not the main context:

```bash
sonar auth status                                                    # skip Sonar entirely if not installed or not connected
sonar analyze --base origin/main --format json --force               # local analysis of the branch change set
sonar analyze secrets <changed files>                                # hardcoded secrets in touched files
# Only if a PR exists (server-side results from CI):
sonar list issues --pull-request <PR_NUMBER> --format json
sonar quality-gate status --pull-request <PR_NUMBER> --format json
```

Add `-p <project-key>` if the project isn't auto-detected (no `.sonar-config.json`); if the key can't be found, run only `analyze` and `analyze secrets`.

Sonar output is input to verify, not findings to copy blindly: keep issues on lines the diff touches, drop ones the reviewer judges to be false positives, merge duplicates with manual findings, and map severity (BLOCKER/HIGH/CRITICAL → Blocking, MEDIUM/MAJOR → Should-fix, LOW/MINOR/INFO → Nit). Prefix each Sonar-sourced `failure_scenario` with the rule key, e.g. `[java:S2259] ...`.

#### Bot review threads

Automated reviewers (Copilot, CodeRabbit, Sonar, etc.) leave inline threads that are often noise. The subagent fetches the unresolved ones whose opening comment is from a bot:

```bash
gh api graphql -F owner=<OWNER> -F repo=<REPO> -F pr=<PR_NUMBER> -f query='
query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){
  reviewThreads(first:100){nodes{id isResolved isOutdated path line
    comments(first:20){nodes{author{__typename login} body}}}}}}}' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved|not)
        | select(.comments.nodes[0].author.__typename=="Bot" or (.comments.nodes[0].author.login|endswith("[bot]")))'
```

For each thread, read the comment and the code it points at (current HEAD, not just the diff hunk) and decide:

- `false_positive` — the claim is wrong for this code: the case can't occur, it's already handled, it misreads the logic, or it contradicts project conventions. Only use this when the code clearly refutes the comment.
- `valid` — the issue is real, or you can't confidently refute it. When in doubt, it's `valid`.

Skip threads where a human has already replied (a human is engaged — leave it to them). Add each `valid` thread's issue to `findings` as well (merged with any duplicate manual finding), with `failure_scenario` prefixed `[bot:<login>] ...`, so it's reported, fixed by `--fix`, and recognised as already-commented by `--comment`.

### 5. Report findings

Take the subagent's `findings` array and call `ReportFindings` once, ordered most-severe first (Blocking → Should-fix → Nit):

- `file`, `line` — exact location
- `summary` — leads with the severity label, e.g. `"Blocking: <defect>"` — this is the only place severity lives; steps 8–9 parse it back out
- `failure_scenario` — concrete triggering input/state, or the concrete downside for style/test-coverage findings
- `short_summary` — compressed claim, ≤60 chars, no severity prefix
- `category` — defect type (`correctness`, `security`, `performance`, `style`, `test-coverage`, ...)

Pass `findings: []` if the subagent found nothing — don't skip the call.

### 6. Resolve false-positive bot threads (PR only)

For each `bot_threads` entry with `verdict: "false_positive"`, reply with the reason, then resolve the thread:

```bash
gh api graphql -F id=<thread_id> -f body="Resolving as a false positive: <reason>" -f query='
mutation($id:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){comment{id}}}'
gh api graphql -F id=<thread_id> -f query='
mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'
```

Leave `valid` threads untouched — no reply, no resolve. If a mutation fails (e.g. missing permission), report it and carry on.

### 7. Narrative output

In chat (or the optional file), give what the tool call doesn't carry:
- Ticket summary (one paragraph)
- Implementation overview (from the subagent's `implementation_overview`)
- SonarQube quality gate result (from the subagent's `sonar`)
- Bot review threads: which were resolved as false positives (with reason) and which were left open as valid
- One-paragraph overall merge-readiness assessment

If the user asked for a file, write those sections to `./tmp/<TICKET-KEY>-code-review.md` (create `./tmp/` if needed) — findings stay in the `ReportFindings` call, not the file.

### 8. Apply fixes (`--fix` only)

For each finding whose `summary` starts with `Blocking:` or `Should-fix:`, Read the target file and use Edit to apply the fix. Skip `Nit:` findings unless asked. Re-call `ReportFindings` with the same findings, each annotated with `outcome`: `fixed`, `skipped`, or `no_change_needed`.

### 9. Post inline PR comments (`--comment` only)

Requires an open PR (step 3).

```bash
PR_NUMBER=$(gh pr view --json number -q .number)
COMMIT_SHA=$(git rev-parse HEAD)
```

For each finding with a `line`:

```bash
gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments \
  -f body="**<summary>**

<failure_scenario>" \
  -f commit_id="$COMMIT_SHA" \
  -f path="<file>" \
  -F line=<line>
```

Skip findings that match an existing comment/review already fetched in step 3, and findings sourced from a bot thread (`[bot:...]` prefix) — that thread already carries the comment. Findings without a `line`, or rejected because the line isn't part of the diff, fall back to one consolidated `gh pr comment`.

## Quality checks

- [ ] Diff review was delegated to a subagent — raw diff isn't sitting in the main conversation.
- [ ] SonarQube was run (or its skip reason reported), and its issues were verified against the diff before being reported.
- [ ] If a PR exists, unresolved bot threads were validated; only clear false positives were replied to and resolved, valid ones left untouched and included in findings.
- [ ] `ReportFindings` was called even with zero findings.
- [ ] Every finding has an exact file (and line, when possible) and a concrete `failure_scenario`.
- [ ] Every `summary` leads with its severity label; `category` separately records defect type.
- [ ] `--fix` only touches Blocking/Should-fix findings, and outcomes are re-reported.
- [ ] `--comment` only runs when a PR exists, skips duplicates, and falls back gracefully for findings with no line.
