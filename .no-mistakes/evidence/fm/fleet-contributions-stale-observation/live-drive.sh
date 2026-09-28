#!/usr/bin/env bash
# Live drive of bin/fm-contributions.sh poll against real GitHub in a disposable lab home.
# Usage: live-drive.sh <repo-root>
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
URL=https://github.com/kunchenguid/firstmate/pull/6016
printf '# Backlog\n\n## Queued\n- [ ] livepr - Contribution %s (repo: firstmate) (kind: ship)\n' "$URL" > "$LAB/data/backlog.md"
clean() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
poll() { # label [bad-token]
  local out rc
  if [ "${2:-}" = bad ]; then
    out=$(clean env GH_TOKEN=invalid-token-for-live-test "$ROOT/bin/fm-contributions.sh" poll 2>&1); rc=$?
  else
    out=$(clean "$ROOT/bin/fm-contributions.sh" poll 2>&1); rc=$?
  fi
  printf -- '--- poll %-38s rc=%s stdout=[%s]\n' "$1" "$rc" "$out"
  jq -c '.records[] | {url,checked_at,error,failure_streak,state:.observation.state,head:(.observation.head // "" | .[0:10])}' "$LAB/data/livepr/contributions.json" 2>/dev/null
  sleep 1
}
section() { printf '\n=== %s ===\n' "$1"; }

section 'S1 healthy real read'
poll 'healthy (real gh)'
section 'S2 transient failure then recovery'
poll 'transient failure (bad token)' bad
poll 'recovery (real gh)'
section 'S3 persistent failure escalates once'
poll 'failure #1' bad
poll 'failure #2' bad
poll 'failure #3' bad
poll 'failure #4' bad
section 'S4 recovery ends episode; new episode deferred again'
poll 'recovery' 
poll 'new failure #1' bad
poll 'new failure #2' bad
section 'S5 legacy error record (no failure_streak) stays quiet'
poll 'recovery'
jq '.records[0].error = "forge observation unavailable or changed during read" | del(.records[0].failure_streak)' "$LAB/data/livepr/contributions.json" > "$LAB/x.json" && mv "$LAB/x.json" "$LAB/data/livepr/contributions.json"
chmod 600 "$LAB/data/livepr/contributions.json"
jq -c '.records[] | {note:"seeded legacy record",error,failure_streak}' "$LAB/data/livepr/contributions.json"
poll 'failure on legacy error' bad
section 'S6 shared URL, late owner joining an episode'
poll 'recovery'
poll 'shared failure #1 (one owner)' bad
printf -- '- [ ] liveduo - Duplicate owner %s (repo: firstmate) (kind: ship)\n' "$URL" >> "$LAB/data/backlog.md"
poll 'shared failure #2 (late owner added)' bad
jq -c '{task, rec:(.records[] | {error,failure_streak})}' "$LAB/data/liveduo/contributions.json"
poll 'shared failure #3' bad
section 'S7 adversarial: tampered failure_streak rejected'
poll 'recovery'
jq '.records[0].failure_streak = 7 | .records[0].error = "x"' "$LAB/data/livepr/contributions.json" > "$LAB/x.json" && mv "$LAB/x.json" "$LAB/data/livepr/contributions.json"
chmod 600 "$LAB/data/livepr/contributions.json"
poll 'poll with tampered streak=7'
