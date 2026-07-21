#!/usr/bin/env bash
#
# Fetch a single error from the Bugsnag Data Access API given a dashboard link.
#
# Usage:
#   ./fetch-bugsnag-error.sh <bugsnag-error-url> [--latest-event] [--sample N]
#
#   --latest-event   also fetch the newest event (stacktrace, breadcrumbs)
#   --sample N       fetch up to N events (default 50) and print a frequency table of
#                    templatized exception messages (numbers/ids masked) plus release
#                    stages. Use this for custom-grouped errors: their per-event
#                    messages embed variable data and differ event-to-event, so a
#                    single event is NOT representative of the group.
#
# The URL is a normal Bugsnag dashboard error link, e.g.
#   https://app.bugsnag.com/<org-slug>/<project-slug>/errors/<error_id>?event_id=<event_id>
# Works for self-hosted instances too (the API host is derived from the dashboard host).
#
# Requires: curl, jq. The personal auth token is taken from, in order:
#   1. $BUGSNAG_AUTH_TOKEN
#   2. .env in this script's own directory (KEY=VALUE line, gitignored)
# (.env is the reliable route: tool shells are non-interactive and do NOT source
#  ~/.bashrc, so a token exported there is invisible here.)
#
# Exit codes:
#   0  success
#   2  missing/invalid input (bad URL, missing token) -> caller should report & ask the user
#   3  API/resolution error (401, org/project not found, etc.)

set -euo pipefail

fail_input() { echo "INPUT_ERROR: $*" >&2; exit 2; }
fail_api()   { echo "API_ERROR: $*"   >&2; exit 3; }

URL=""
WANT_EVENT="false"
SAMPLE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --latest-event) WANT_EVENT="true"; shift ;;
    --sample|--events)
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then SAMPLE="$2"; shift 2; else SAMPLE=50; shift; fi ;;
    --sample=*|--events=*) SAMPLE="${1#*=}"; shift ;;
    --) shift ;;
    -*) fail_input "unknown flag: $1" ;;
    *) [ -z "$URL" ] && URL="$1"; shift ;;
  esac
done
[[ "$SAMPLE" =~ ^[0-9]+$ ]] || fail_input "--sample expects a number, got '$SAMPLE'."

[ -n "$URL" ] || fail_input "no URL given. Pass a Bugsnag error link as the first argument."
command -v jq >/dev/null 2>&1 || fail_input "jq is required but not installed."

# Resolve the auth token: env var, then .env in the skill directory. Tool shells
# are non-interactive and do NOT source ~/.bashrc, so an env var exported there is
# invisible here — .env is the reliable route.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${BUGSNAG_AUTH_TOKEN:-}" ] && [ -f "$SCRIPT_DIR/.env" ]; then
  BUGSNAG_AUTH_TOKEN="$(grep -m1 -E '^[[:space:]]*BUGSNAG_AUTH_TOKEN=' "$SCRIPT_DIR/.env" \
    | sed -E 's/^[[:space:]]*BUGSNAG_AUTH_TOKEN=[[:space:]]*//; s/^["'\'']//; s/["'\'']$//' \
    | tr -d '[:space:]')"
fi

if [ -z "${BUGSNAG_AUTH_TOKEN:-}" ]; then
  fail_input "no Bugsnag auth token found. Copy .env.example to .env in the skill directory ($SCRIPT_DIR) and set your token in it, or export \$BUGSNAG_AUTH_TOKEN in the environment Claude Code was launched from. NOTE: exporting it in ~/.bashrc does NOT work here — tool shells are non-interactive and don't source it."
fi
export BUGSNAG_AUTH_TOKEN

# --- Parse the link ---------------------------------------------------------
# Strip scheme, then split host and path. Drop any query string / fragment.
no_scheme="${URL#*://}"
host="${no_scheme%%/*}"
path="${no_scheme#*/}"
path="${path%%\?*}"
path="${path%%#*}"

[ "$host" != "$no_scheme" ] || fail_input "URL has no path segments: '$URL'"

IFS='/' read -r org_slug project_slug errors_kw error_id _rest <<<"$path"

if [ -z "${org_slug:-}" ] || [ -z "${project_slug:-}" ] || [ "${errors_kw:-}" != "errors" ] || [ -z "${error_id:-}" ]; then
  fail_input "this is not a Bugsnag *error* link. Expected .../<org>/<project>/errors/<error_id>, got path '/$path'. Ask the user for the full error link (open the error in Bugsnag and copy the address-bar URL)."
fi

# --- Derive the API host ----------------------------------------------------
# SaaS: app.bugsnag.com -> api.bugsnag.com
# Self-hosted: <dashboard-host> -> api.<dashboard-host> (strip a leading app./dashboard. first)
if [ -n "${BUGSNAG_API_BASE:-}" ]; then
  api_base="${BUGSNAG_API_BASE%/}"
else
  case "$host" in
    app.*)       api_base="https://api.${host#app.}" ;;
    dashboard.*) api_base="https://api.${host#dashboard.}" ;;
    *)           api_base="https://api.${host}" ;;
  esac
fi

hdr=(-H "Authorization: token $BUGSNAG_AUTH_TOKEN" -H "X-Version: 2" -H "Accept: application/json")

api_get() { # $1 = path (leading slash); prints body, fails on non-2xx
  local body code
  body="$(curl -sS -w $'\n%{http_code}' "${hdr[@]}" "$api_base$1")" || fail_api "curl failed for $1"
  code="${body##*$'\n'}"
  body="${body%$'\n'*}"
  case "$code" in
    2*) printf '%s' "$body" ;;
    401|403) fail_api "auth rejected ($code) for $1. Check BUGSNAG_AUTH_TOKEN is a valid personal auth token with access." ;;
    404) fail_api "not found ($code) for $1." ;;
    *) fail_api "HTTP $code for $1: $body" ;;
  esac
}

# Fetch up to $1 events, following the Link: rel="next" header. Prints a JSON array.
fetch_events_json() {
  local max="$1" per=30
  local url="$api_base/projects/$project_id/errors/$error_id/events?per_page=$per"
  local acc="[]" hfile body code next n
  while [ -n "$url" ]; do
    hfile="$(mktemp)"
    body="$(curl -sS -D "$hfile" -w $'\n%{http_code}' "${hdr[@]}" "$url")" || { rm -f "$hfile"; fail_api "curl failed fetching events"; }
    code="${body##*$'\n'}"; body="${body%$'\n'*}"
    case "$code" in 2*) : ;; *) rm -f "$hfile"; fail_api "HTTP $code fetching events: $body" ;; esac
    acc="$(jq -c --argjson a "$acc" '$a + .' <<<"$body")"
    n="$(jq 'length' <<<"$acc")"
    next="$(grep -i '^link:' "$hfile" | tr -d '\r' | sed -nE 's/.*<([^>]+)>;[[:space:]]*rel="next".*/\1/p' | head -n1 || true)"
    rm -f "$hfile"
    [ "$n" -ge "$max" ] && break
    [ -z "$next" ] && break
    url="$next"
  done
  jq -c ".[0:$max]" <<<"$acc"
}

# Read a JSON array of events on stdin; print a distribution report. Messages are
# templatized (long ids -> <id>, numbers -> <n>) so value-patterns collapse and the
# true variety of the group is visible.
analyze_events() {
  jq -r '
    # mask mixed letter+digit tokens (ids) first, then any number run -> <n>
    def templ:
      gsub("(?=[A-Za-z0-9._:-]*[A-Za-z])(?=[A-Za-z0-9._:-]*[0-9])[A-Za-z0-9._:-]{2,}"; "<id>")
      | gsub("[0-9]+([.][0-9]+)?"; "<n>");
    (length) as $total
    | [ .[] | (.exceptions[0].message // .error_class // .context // "?") ] as $msgs
    | ($msgs | map(templ)) as $pats
    | "sampled events: \($total)",
      "distinct message patterns: \(($pats | unique | length))",
      "",
      "count\tmessage pattern (numbers/ids masked)",
      ( $pats | group_by(.) | map({p: .[0], c: length}) | sort_by(-.c)[] | "\(.c)\t\(.p)" ),
      "",
      "release stages:",
      ( [ .[] | (.app.releaseStage // "unknown") ] | group_by(.) | map({s: .[0], c: length}) | sort_by(-.c)[] | "  \(.c)\t\(.s)" )
  '
}

# --- Resolve org slug -> org id --------------------------------------------
org_id="$(api_get "/user/organizations" | jq -r --arg s "$org_slug" '.[] | select(.slug==$s) | .id' | head -n1)"
[ -n "$org_id" ] || fail_api "no organization matching slug '$org_slug' is visible to this token."

# --- Resolve project slug -> project id ------------------------------------
project_id="$(api_get "/organizations/$org_id/projects?per_page=100" \
  | jq -r --arg s "$project_slug" '.[] | select(.slug==$s) | .id' | head -n1)"
[ -n "$project_id" ] || fail_api "no project matching slug '$project_slug' in org '$org_slug'."

# --- Fetch the error (viewErrorOnProject) ----------------------------------
echo "# Error $error_id (project $project_slug / org $org_slug)" >&2
error_json="$(api_get "/projects/$project_id/errors/$error_id")"
printf '%s\n' "$error_json"
echo >&2

# --- Warn when grouping is custom: messages in the group can diverge --------
grouping_reason="$(jq -r '.grouping_reason // empty' <<<"$error_json")"
if [ "$grouping_reason" = "user_defined" ] || [ "$grouping_reason" = "custom" ]; then
  echo "# WARNING: grouping_reason=$grouping_reason — this error groups events by a custom rule, so per-event messages can embed variable data and differ across events. Do NOT characterize it from one event; run with --sample N and report the distribution." >&2
  [ "$SAMPLE" -eq 0 ] && echo "#          (no --sample given; only the aggregate was fetched.)" >&2
fi

# --- Optional: latest event for stacktrace/context ------------------------
if [ "$WANT_EVENT" = "true" ]; then
  echo "# Latest event" >&2
  api_get "/projects/$project_id/errors/$error_id/latest_event"
  echo >&2
fi

# --- Optional: sample many events and show the message distribution --------
if [ "$SAMPLE" -gt 0 ]; then
  echo "# Event sample (up to $SAMPLE events)" >&2
  fetch_events_json "$SAMPLE" | analyze_events
fi
