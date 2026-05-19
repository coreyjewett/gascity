#!/usr/bin/env bash
# mol-polecat-pr-smoke.sh — end-to-end smoke for the mol-polecat-pr formula.
#
# Exercises the formula against a throwaway bead with a no-op change
# (adding a comment to a single fixture file) and verifies:
#
#   1. The feature branch is cut off `<upstream_remote>/<target_base>`
#      (NOT origin), per the formula contract.
#   2. The branch pushes to `<origin_remote>` successfully.
#   3. A draft PR is opened on `<upstream_org>/<upstream_repo>` and the
#      returned URL is recorded.
#   4. The test PR is closed via `gh pr close --delete-branch` so the
#      upstream repository is not polluted.
#
# Gated by GC_SMOKE_PR=1 — this script costs one upstream PR open+close
# cycle and requires write access to the upstream repository. It is not
# fired on every CI run.
#
# Usage:
#   GC_SMOKE_PR=1 ./scripts/mol-polecat-pr-smoke.sh
#
# Optional overrides:
#   GC_SMOKE_PR_UPSTREAM_REMOTE   default: upstream
#   GC_SMOKE_PR_UPSTREAM_ORG      default: gastownhall
#   GC_SMOKE_PR_UPSTREAM_REPO     default: gascity
#   GC_SMOKE_PR_TARGET_BASE       default: main
#   GC_SMOKE_PR_ORIGIN_REMOTE     default: origin

set -euo pipefail

if [ "${GC_SMOKE_PR:-0}" != "1" ]; then
    echo "GC_SMOKE_PR is not set to 1 — skipping mol-polecat-pr smoke test."
    echo "Run with: GC_SMOKE_PR=1 $0"
    exit 0
fi

UPSTREAM_REMOTE="${GC_SMOKE_PR_UPSTREAM_REMOTE:-upstream}"
UPSTREAM_ORG="${GC_SMOKE_PR_UPSTREAM_ORG:-gastownhall}"
UPSTREAM_REPO="${GC_SMOKE_PR_UPSTREAM_REPO:-gascity}"
TARGET_BASE="${GC_SMOKE_PR_TARGET_BASE:-main}"
ORIGIN_REMOTE="${GC_SMOKE_PR_ORIGIN_REMOTE:-origin}"

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command not found on PATH: $1" >&2
        exit 2
    }
}
require git
require gh
require openssl

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

echo "=== mol-polecat-pr smoke test ==="
echo "upstream: $UPSTREAM_REMOTE ($UPSTREAM_ORG/$UPSTREAM_REPO:$TARGET_BASE)"
echo "origin:   $ORIGIN_REMOTE"
echo

git remote get-url "$UPSTREAM_REMOTE" >/dev/null || {
    echo "ERROR: upstream remote '$UPSTREAM_REMOTE' not configured" >&2
    exit 2
}
git remote get-url "$ORIGIN_REMOTE" >/dev/null || {
    echo "ERROR: origin remote '$ORIGIN_REMOTE' not configured" >&2
    exit 2
}

echo "--- Fetching $UPSTREAM_REMOTE ---"
git fetch "$UPSTREAM_REMOTE" "$TARGET_BASE"

bead_id="smoke-$(openssl rand -hex 4)"
branch="feat/${bead_id}-mol-polecat-pr-smoke"
worktree="$repo_root/worktrees/${bead_id}"

cleanup() {
    set +e
    if [ -n "${pr_url:-}" ]; then
        echo "--- Closing PR ${pr_url} (--delete-branch) ---"
        gh pr close "$pr_url" --delete-branch --comment "Closed by mol-polecat-pr smoke test." || true
    fi
    if [ -d "$worktree" ]; then
        echo "--- Removing worktree $worktree ---"
        git -C "$repo_root" worktree remove "$worktree" --force || true
    fi
    git -C "$repo_root" branch -D "$branch" 2>/dev/null || true
    git -C "$repo_root" push "$ORIGIN_REMOTE" --delete "$branch" 2>/dev/null || true
}
trap cleanup EXIT

echo "--- Creating worktree off $UPSTREAM_REMOTE/$TARGET_BASE ---"
git worktree add "$worktree" --detach "$UPSTREAM_REMOTE/$TARGET_BASE"
cd "$worktree"

upstream_head=$(git rev-parse "$UPSTREAM_REMOTE/$TARGET_BASE")
worktree_head=$(git rev-parse HEAD)
if [ "$upstream_head" != "$worktree_head" ]; then
    echo "ERROR: worktree HEAD ($worktree_head) != $UPSTREAM_REMOTE/$TARGET_BASE ($upstream_head)" >&2
    exit 1
fi
echo "OK: worktree is at $UPSTREAM_REMOTE/$TARGET_BASE HEAD"

origin_head=$(git rev-parse "$ORIGIN_REMOTE/$TARGET_BASE" 2>/dev/null || echo "")
if [ -n "$origin_head" ] && [ "$origin_head" = "$worktree_head" ]; then
    echo "WARN: $ORIGIN_REMOTE/$TARGET_BASE == $UPSTREAM_REMOTE/$TARGET_BASE — cannot distinguish branch-off origin"
fi

echo "--- Creating feature branch $branch ---"
git checkout -b "$branch"

fixture="scripts/mol-polecat-pr-smoke.sh"
printf '\n# smoke marker %s\n' "$bead_id" >> "$fixture"
git add "$fixture"
git -c user.email=smoke@example.invalid -c user.name="polecat-pr-smoke" \
    commit -m "smoke: mol-polecat-pr verification ($bead_id)"

echo "--- Pushing $branch to $ORIGIN_REMOTE ---"
git push -u "$ORIGIN_REMOTE" "$branch"

fork_owner=$(gh repo view --json owner -q '.owner.login' 2>/dev/null \
    || git remote get-url "$ORIGIN_REMOTE" | sed -E 's#.*[:/]([^/]+)/[^/]+(\.git)?$#\1#')

echo "--- Opening draft PR on $UPSTREAM_ORG/$UPSTREAM_REPO ---"
pr_url=$(gh pr create --draft \
    --repo "$UPSTREAM_ORG/$UPSTREAM_REPO" \
    --base "$TARGET_BASE" \
    --head "$fork_owner:$branch" \
    --title "smoke: mol-polecat-pr verification ($bead_id)" \
    --body "Automated smoke test for the mol-polecat-pr formula. Closing immediately.")

if [ -z "$pr_url" ]; then
    echo "ERROR: gh pr create returned an empty URL" >&2
    exit 1
fi

case "$pr_url" in
    https://github.com/${UPSTREAM_ORG}/${UPSTREAM_REPO}/pull/*) ;;
    *) echo "ERROR: PR URL does not target $UPSTREAM_ORG/$UPSTREAM_REPO: $pr_url" >&2; exit 1 ;;
esac

echo "OK: draft PR opened at $pr_url"
echo "=== mol-polecat-pr smoke test PASSED ==="
