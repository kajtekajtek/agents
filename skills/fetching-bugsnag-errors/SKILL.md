---
name: fetching-bugsnag-errors
description: Use when you have a Bugsnag error or event link (app.bugsnag.com/... or a self-hosted Bugsnag dashboard URL) and need to retrieve that error's details via the Bugsnag Data Access API. Also use when asked to look up, fetch, or investigate a Bugsnag error/crash from a dashboard link.
---

# Fetching Bugsnag Errors

## Overview

A Bugsnag dashboard error link is **slug-based**, but the Data Access API is **ID-based**. You cannot call the error endpoint directly from the link — you must parse the link, resolve the org and project *slugs* to *IDs*, then fetch the error. This skill's `fetch-bugsnag-error.sh` does all of that in one call; use it rather than hand-writing curl commands.

## When to use

- The user gives a Bugsnag error/event link and wants the error details.
- The user asks to investigate, look up, or pull a Bugsnag error/crash.

## Prerequisites

The script needs a Bugsnag personal auth token (Bugsnag → Settings → My account → Personal auth tokens). Set it up once by copying `.env.example` to `.env` in this skill's directory and filling in the token:

```bash
cp <skill-dir>/.env.example <skill-dir>/.env && chmod 600 <skill-dir>/.env
# then edit <skill-dir>/.env → BUGSNAG_AUTH_TOKEN=<personal-auth-token>
```

`.env` is gitignored — never commit it. The script reads the token from `$BUGSNAG_AUTH_TOKEN` first, then `.env` in the skill directory.

**The non-interactive-shell trap:** your shell commands run in a fresh *non-interactive* shell that does **not** source `~/.bashrc`. So a token `export`ed in `~/.bashrc` is invisible here, and a bare `echo $BUGSNAG_AUTH_TOKEN` printing empty does **not** mean the user failed to configure it. Do not declare the token missing from such a check, and do not read it out of a shell profile — just run the script (it resolves the token from `.env` / the files above) and act on what it reports.

If the script reports no token, tell the user to create `.env` from `.env.example` as above. Never inline the token into a command or commit it to the repo.

## Workflow

### 1. Run the helper script

The script is `fetch-bugsnag-error.sh` in **this skill's directory** (the base directory printed when the skill loads). Invoke it by that full path — do **not** assume your working directory is the skill directory:

```bash
"<skill-dir>/fetch-bugsnag-error.sh" '<bugsnag-error-url>'                 # error (aggregate) details
"<skill-dir>/fetch-bugsnag-error.sh" '<bugsnag-error-url>' --latest-event  # also fetch newest event (stacktrace, breadcrumbs)
"<skill-dir>/fetch-bugsnag-error.sh" '<bugsnag-error-url>' --sample 100     # sample many events; frequency table of message patterns
```

Quote the URL — it contains `?` and `&`. The error object is aggregate metadata (class, message, counts, status, first/last seen); add `--latest-event` when the user needs the stacktrace or request/device context.

### 2. Sample before characterizing custom-grouped errors

**Never characterize a custom-grouped error from a single event.** A Bugsnag error is a *group* of events. When `grouping_reason` is `user_defined`/`custom` (the script prints a WARNING when it is), the grouping is by a custom rule and per-event messages embed **variable data** (amounts, ids) that differs event-to-event — so the aggregate message and any one `--latest-event` are **not representative** of the group.

When you see that warning (or grouping is otherwise custom), re-run with `--sample N` and report the **distribution**, not one message. The frequency table masks numbers/ids (`<n>`, `<id>`) so distinct value-patterns collapse; use it to judge **whether the group is one underlying bug or several** (e.g. distinct message families = likely distinct causes).

### 3. Handle what the script reports

The script exits non-zero with a diagnostic prefix. **Do not silently retry or guess** — act on the specific message:

| Prefix / exit | Meaning | What to do |
|---|---|---|
| `INPUT_ERROR` (2), no token | No token in env or `.env` | Have the user create `.env` from `.env.example` (see Prerequisites) — do **not** blame `~/.bashrc` or ask the user to `export` there |
| `INPUT_ERROR` (2), not an error link | The link isn't a `.../errors/<id>` link | Ask the user for the full error link (open the error in Bugsnag, copy the address-bar URL) |
| `API_ERROR` (3), `401`/`403` | Token invalid or lacks access | Tell the user the token was rejected; ask them to check/regenerate it |
| `API_ERROR` (3), org/project not found | Slug not visible to this token | Report which slug failed; the token's user may not be a member of that org/project |

### 4. Present the result

Summarize the returned JSON for the user (error class, message, status, event count, first/last seen, release stages). Don't dump raw JSON unless asked. If you sampled, report the **message-pattern distribution** and call out whether it looks like one bug or several — do not present a single event's message as the whole story.

## The API, if you must call it directly

Only bypass the script if it can't run (no bash/jq). The mechanics it encodes:

- **Base URL** — SaaS: `https://api.bugsnag.com`. Self-hosted: `api.` + the dashboard host (e.g. dashboard `bugsnag.acme.com` → API `https://api.bugsnag.acme.com`). If a self-hosted host is rejected, ask the user for the correct API host.
- **Every request needs these headers:** `Authorization: token $BUGSNAG_AUTH_TOKEN` (the scheme word is `token`, **not** `Bearer`), `X-Version: 2` (required — pins the API version), `Accept: application/json`.
- **Resolve IDs, then fetch:**
  1. `GET /user/organizations` → match `.slug` → `organization_id`
  2. `GET /organizations/{organization_id}/projects?per_page=100` → match `.slug` → `project_id`
  3. `GET /projects/{project_id}/errors/{error_id}` → the error (this is `viewErrorOnProject`)
  4. (optional) `GET /projects/{project_id}/errors/{error_id}/latest_event` → stacktrace/context
  5. (sampling) `GET /projects/{project_id}/errors/{error_id}/events?per_page=30` → paginate via the `Link: rel="next"` header, then tally `exceptions[0].message` across events

Link shape: `https://<host>/<org-slug>/<project-slug>/errors/<error_id>?event_id=<event_id>`. The `errors/<error_id>` path segment IS a real API error id; the slugs are NOT ids.

## Common mistakes

- **Using the slug as the project id** — `GET /projects/web-frontend/errors/...` 404s. `project_id` must be resolved via the org/projects lookup.
- **`Authorization: Bearer ...`** — Bugsnag uses `token`, not `Bearer`; wrong scheme → 401.
- **Omitting `X-Version: 2`** — the request may silently behave as an older version.
- **Calling `app.bugsnag.com`** — that's the dashboard; the API host is `api.bugsnag.com`.
- **Declaring the token missing after a bare non-interactive shell check, or reading it out of `~/.bashrc`** — the shell doesn't source `.bashrc`; let the script resolve the token (env or token file) and act on its report.
- **Inventing a token location** — the token comes from `$BUGSNAG_AUTH_TOKEN` or `.env` in the skill dir — nothing else.
- **Committing `.env`** — it holds the real token and is gitignored; only `.env.example` (a placeholder) is committed.
- **Characterizing a custom-grouped error from one event** — with `grouping_reason: user_defined`/`custom`, messages diverge across events; sample with `--sample N` and report the distribution, never a single message.

## Reference

- Data Access API overview: https://developer.smartbear.com/bugsnag/docs/data-access
- Authentication: https://developer.smartbear.com/bugsnag/docs/data-access-authentication
- viewErrorOnProject: https://developer.smartbear.com/bugsnag/docs/bugsnag-data-access-api#/Errors/viewErrorOnProject
