#!/bin/bash

# This script is used to keep the original repositories while sending the commits to the forked repositories
# If you want to send the commits to the original repositories, run this script with the 'git' argument
# If you want to send the commits to the forked repositories, run this script with the 'backup' argument
# More info about commiting to the original repositories: https://osm.etsi.org/docs/developer-guide/04-merge-conflicts.html

SUPER_REPO_PATH="$(pwd)"  # Set to current directory or manually define

if [[ "$#" -ne 1 ]]; then
    echo "❌ Usage: $0 [git|backup]"
    exit 1
fi

MODE="$1"

for dir in "$SUPER_REPO_PATH"/*/; do
    if [[ "$MODE" == "git" ]]; then
        if [[ -d "$dir/.git_backup" ]]; then
            echo "🔄 Restoring .git in $dir"
            mv "$dir/.git_backup" "$dir/.git"
        fi
    elif [[ "$MODE" == "backup" ]]; then
        if [[ -d "$dir/.git" ]]; then
            echo "🔄 Backing up .git in $dir"
            mv "$dir/.git" "$dir/.git_backup"
        fi
    else
        echo "❌ Invalid argument: $MODE. Use 'git' or 'backup'."
        exit 1
    fi
done
