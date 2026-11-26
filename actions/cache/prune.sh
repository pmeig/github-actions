#!/usr/bin/env bash
# Keeps one cache of a thing per branch: deletes the entries of the current ref (GITHUB_REF) whose key is CACHE_PREFIX
# followed by another hash than the one of CACHE_KEY. CACHE_PREFIX ends with the delimiter `|`, so the workspace `web`
# never matches `web-admin`. Needs gh, GH_TOKEN, GH_REPO and the permission `actions: write`; never fails the job.
set -u

warn() { echo "::warning::cache prune: $1"; }

if [ -z "${CACHE_PREFIX:-}" ] || [ -z "${CACHE_KEY:-}" ] || [ -z "${GITHUB_REF:-}" ]
then
  warn "CACHE_PREFIX, CACHE_KEY or GITHUB_REF is empty, nothing deleted"
  exit 0
fi
if ! command -v gh > /dev/null 2>&1
then
  warn "gh is not installed, older entries are kept"
  exit 0
fi
if ! entries=$(gh cache list --ref "$GITHUB_REF" --key "$CACHE_PREFIX" --limit 100 --json id,key --jq '.[] | "\(.id)\t\(.key)"')
then
  warn "gh cache list failed, older entries are kept"
  exit 0
fi

while IFS=$'\t' read -r id key
do
  key=${key%$'\r'}
  if [ -z "$id" ] || [ "$key" = "$CACHE_KEY" ] || [[ "$key" != "$CACHE_PREFIX"* ]] || [[ "${key#"$CACHE_PREFIX"}" == *'|'* ]]
  then
    continue
  fi
  if gh cache delete "$id" < /dev/null
  then
    echo "cache prune: deleted $key"
  else
    warn "could not delete $key (the job needs the permission actions: write)"
  fi
done <<< "$entries"
exit 0
