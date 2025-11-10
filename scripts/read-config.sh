#!/usr/bin/env bash
# SPDX-FileCopyrightText: Alex Turbov <zaufi@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

declare -r config="${1:-.github/sync-with-template-repo.yaml}"

if [[ ! -f $config ]]; then
    echo "::error file=${config}::Config file not found" >&2
    exit 1
fi

# shellcheck disable=SC2155
declare -r repository="$(yq -r '.repository // ""' "$config")"
# shellcheck disable=SC2155
declare -r branch="$(yq -r '.branch // ""' "$config")"

{
    echo "repository=$repository"
    echo "branch=$branch"
    echo "template_repo_path=$(echo "$repository" | md5sum | cut -f1 -d' ')"
} >> "$GITHUB_OUTPUT"
