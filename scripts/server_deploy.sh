#!/usr/bin/env bash
set -euo pipefail
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DEPLOY_TMP="$HOME/chhama_deploy_tmp_$TIMESTAMP"
LIVE_ROOT="/home/$USER/public_html"
BACKUP_DIR="$HOME/chhama_backups_$TIMESTAMP"

echo "Deploy tmp: $DEPLOY_TMP"
mkdir -p "$DEPLOY_TMP"
mkdir -p "$BACKUP_DIR"
echo "Backing up current live site to $BACKUP_DIR"
rsync -a --delete "$LIVE_ROOT/" "$BACKUP_DIR/"

echo "Moving new files into place..."
rsync -a --delete "$DEPLOY_TMP/" "$LIVE_ROOT/"

if [ -x "$LIVE_ROOT/scripts/webdoctor-server.sh" ]; then
  echo "Running server-side webdoctor..."
  bash "$LIVE_ROOT/scripts/webdoctor-server.sh" || echo "webdoctor exited non-zero"
fi

echo "Deploy done at $TIMESTAMP"
