#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEST="${1:-/tmp/ghost-e2e-closure}"

echo "======================================================================="
echo "⚡ Hydrating Ghost E2E Production Closure on Host"
echo "Target Directory: ${DEST}"
echo "======================================================================="

cd "$REPO_ROOT"

# Ensure destination directory is clean
rm -rf "$DEST"
mkdir -p "$DEST"

# 1. Verify that Admin and Public Apps are built
if [[ ! -d "ghost/core/core/built/admin" ]]; then
    echo "❌ Error: ghost/core/core/built/admin not found. Please build admin first." >&2
    exit 1
fi

for app in portal comments-ui sodo-search signup-form announcement-bar; do
    if [[ ! -d "apps/${app}/umd" ]]; then
        echo "❌ Error: apps/${app}/umd not found. Please build public apps first." >&2
        exit 1
    fi
done

echo "1/6. Building Ghost production workspace dependencies and assets..."
pnpm --filter-prod "ghost^..." -r run build
pnpm --filter ghost run build:tsc
pnpm --filter ghost run build:assets

echo "2/6. Deploying production closure to ${DEST}..."
pnpm --filter=ghost --config.inject-workspace-packages=true deploy --prod "$DEST"

echo "3/6. Pruning unused development files from closure..."
node ghost/core/scripts/prune.mts "$DEST" --profile=image

echo "4/6. Injecting Admin production build..."
mkdir -p "$DEST/core/built"
cp -a ghost/core/core/built/admin "$DEST/core/built/admin"

echo "5/6. Injecting Public App UMD bundles..."
mkdir -p "$DEST/content/files"
cp -a apps/portal/umd "$DEST/content/files/portal"
cp -a apps/comments-ui/umd "$DEST/content/files/comments-ui"
cp -a apps/sodo-search/umd "$DEST/content/files/sodo-search"
cp -a apps/signup-form/umd "$DEST/content/files/signup-form"
cp -a apps/announcement-bar/umd "$DEST/content/files/announcement-bar"

# Setup default content and themes
mkdir -p "$DEST/default" "$DEST/log"
cp -a "$DEST/content" "$DEST/base_content"
cp -a "$DEST/content/themes/casper" "$DEST/default/casper"
if [[ -d "$DEST/content/themes/source" ]]; then
    cp -a "$DEST/content/themes/source" "$DEST/default/source"
fi

echo "6/6. Verifying native modules..."
(
    cd "$DEST"
    node -e "require('better-sqlite3'); console.log('✅ better-sqlite3 native module verified OK')"
)

echo "======================================================================="
echo "✅ Ghost E2E Closure Hydration Complete at ${DEST}"
echo "======================================================================="
