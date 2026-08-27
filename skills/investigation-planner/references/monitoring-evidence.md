# Investigating from a monitoring aggregate

Applies when the primary evidence is a Bugsnag/Sentry error, a log pattern, or a
metric spike rather than a reproducible case.

## Why one event isn't enough

A dashboard error is a **group**, not an occurrence. The event you happen to open
is one sample from a distribution that may not be uniform — and with custom
grouping rules, unrelated failures can share a group, so any single event can be
actively unrepresentative. Forming a root-cause hypothesis from it is guessing
with extra steps.

## Sample, then characterize

Pull many occurrences before forming any hypothesis, and describe the
distribution along each axis:

| Axis | What to look for |
|---|---|
| Message / value patterns | Distinct message families, recurring vs. varied ids, null vs. malformed vs. out-of-range |
| Affected entities | One tenant/user/account/region, or spread across all |
| Release / version | First-seen release, and whether it stops at a later one |
| Time | Continuous, bursty, or aligned to a deploy, a job schedule, or a traffic peak |

## One bug or several?

Test this explicitly before committing to a single cause. Strong signals that the
group holds more than one bug:

- Two or more distinct message families under one group.
- Value patterns that can't share a cause (e.g. some events with a null id, others
  with a well-formed id that simply doesn't exist).
- A subset confined to one release or one entity while the rest is spread evenly.

If the group splits, say so in the investigation file and treat each split as its
own hypothesis — a fix aimed at the dominant family will leave the others live.

## Bugsnag specifics

Use the **fetching-bugsnag-errors** skill; its `--sample N` mode is what produces
the distribution above. Note the error's `first_seen` / `last_seen` and release
stage — `first_seen` compared against deploy history is the cheapest available
answer to "what changed?".

Delegate the sampling to a subagent: the raw event JSON is large and only the
characterized distribution needs to come back.
