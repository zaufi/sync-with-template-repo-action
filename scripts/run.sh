#!/usr/bin/env bash
# SPDX-FileCopyrightText: Alex Turbov <zaufi@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# BEGIN Helper functions
function error()
{
    local -r message="$1"
    local -r file="${2:-}"

    if [[ -z ${CI:-''} ]]; then
        echo "❌ $message${file:+ ($file)}" >&2
    else
        echo "::error ${file:+file=${file}::}$message"
    fi
}

function notice()
{
    local -r title="$1"
    local -r message="$2"
    local -r file="${3:-}"

    if [[ -z ${CI:-''} ]]; then
        echo "ℹ️ ${title:+$title: }$message${file:+ ($file)}"
    else
        echo "::notice ${file:+file=$file,}${title:+title=$title::}$message"
    fi
}

function die()
{
    error "$@"
    exit 1
}

function report_conflicts()
{
    local -rn dict_var="$1"
    for file in "${!dict_var[@]}"; do
        echo -e "::group Conflict in \`$file\`\n${dict_var[$file]}\n::endgroup"
    done
}
# END Helper functions

# BEGIN Handle arguments
function usage()
{
    cat >&2 <<USAGE
Usage: ${0##*/} [-c <CONFIG-FILE>] [-p] <TEMPLATE-REPO-PATH>

Sync changes from a template repository into the current repository and open a PR.
USAGE
}

declare CONFIG=.github/sync-with-template-repo.yaml
declare -i make_pr=0

while getopts ':c:ph' opt; do
  case "$opt" in
    c)
        CONFIG="$OPTARG"
        ;;
    \?)
        die "Invalid option: -$OPTARG"
        ;;
    h)
        usage
        exit 0
        ;;
    p)
        make_pr=1
        ;;
    :)
        die "Option -$OPTARG requires an argument"
        ;;
  esac
done

# Remove the options from the positional parameters
shift $(( OPTIND - 1 ))

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

# Set input parameters
declare -r template_repo_path="$1"
# END Handle arguments

# BEGIN Check prerequisites
function check_required_command()
{
    if ! command -v "$1" >/dev/null 2>&1; then
        die "Required command \`$1\` is not installed or not in PATH"
    fi
}

for bin in git yq gh patch envsubst grep sed comm mktemp; do
    check_required_command "$bin"
done

# Check configuration file
if [[ ! -f $CONFIG ]]; then
    die "Config file not found" "${CONFIG}"
fi

# Check given directory presence
if [[ ! -d $template_repo_path ]]; then
    die "Path not found or not a directory" "${template_repo_path}"
fi
# END Check prerequisites

declare -r TEMP_SAVE_COMMIT_MESSAGE='chore(🤖): temporarily save successfully applied changes'
# shellcheck disable=SC2016
declare -rx DEFAULT_COMMIT_TITLE='chore(🤖): sync with template repo ${repository}'
# shellcheck disable=SC2016
declare -rx DEFAULT_PR_BODY='# Changes in this PR

Receive changes from the parent template repository [happened since the last sync].

[happened since the last sync]: https://github.com/${repository}/compare/${since}...${last}
'

function yq_get()
{
    local -r expression="$1"
    # shellcheck disable=SC2016
    yq -r "$expression" "$CONFIG" | envsubst '$repository $since $last'
}

# Get configuration parameters
declare -r exclude_pattern="($(yq_get '(.exclude | select(tag=="!!seq") | join("|")) // "^$"'))"
declare -rx since="$(yq_get '.last-sync // "HEAD"')"

if [[ -z $since || $since == 'HEAD' ]]; then
    die "Set the \`last-sync\` to hash of the last sync'ed commit" "${CONFIG}"
fi

# Check if last sync is actually a HEAD
if [[
    $(git -C "$template_repo_path" rev-parse --short HEAD) == "$since"
  || $(git -C "$template_repo_path" rev-parse HEAD) == "$since"
  ]]; then
    notice 'No changes since last check' "$since is actually the HEAD"
    exit 0
fi

# Find common files among two repos excluding unneeded
# but include that come from a template repo...
declare -a common_files
mapfile -t common_files < <( \
    comm -2 \
    <(git -C "$template_repo_path" ls-files | grep -Ev "$exclude_pattern" | sort) \
    <(git ls-files | grep -Ev "$exclude_pattern" | sort) \
  | sed 's,^\s*,,' \
  )

# Get the diff since the last check for all these files and try to apply
declare -i have_smth_2_sync=0
declare -A cant_apply=()
for file in "${common_files[@]}"; do
    # First of all, check if the files are ever different
    if [[ -f $file ]] && diff -q "$file" "$template_repo_path/$file" >/dev/null; then
        echo "File \`$file\` has no differences"
        continue
    fi

    # Are there any changes in the file since the last check?
    diff="$(git -C "$template_repo_path" --no-pager diff "$since"..HEAD -- "$file")"
    if [[ -z $diff ]]; then
        echo "File \`$file\` has no changes"
        continue
    fi

    echo "::group::Try to apply changes to \`$file\`"

    # Try to apply whatever can be applied and record rejects
    git apply --reject --recount --allow-empty <<<"$diff" || true

    # Check the file status
    declare file_status="$(git status --porcelain=1 "$file")"
    if [[ $file_status == \ M\ * ]]; then
        # Temporarily commit applied changes if existed file
        # has been modified
        git commit --no-verify -m "$TEMP_SAVE_COMMIT_MESSAGE" -- "$file"

    # Maybe it's a new file (untracked yet)?
    elif [[ $file_status == \?\?\ * ]]; then
        git add "$file"
    fi

    # TODO Make sure the reject file wasn't here before? ;-)
    # (i.e., in the repo %-)
    if [[ -f "$file".rej ]]; then
        # Huh, it seems there's a conflict...
        git apply --3way --recount --allow-empty <<<"$diff" || true
        # Record unsuccessful hunks
        declare conflict_diff="$(git --no-pager diff --minimal "$file")"
        if [[ -n $conflict_diff ]]; then
            cant_apply[$file]="$conflict_diff"
        fi
        # Restore the original file
        git restore --source HEAD --staged --worktree "$file"
        # Remove the rejects file
        rm -f -- "$file".rej
    fi

    # Restore applied changes if was modified at the first apply
    if [[ $file_status == \ M\ * ]]; then
        git reset HEAD^
    fi

    have_smth_2_sync=1
    echo '::endgroup::'
done

declare -rx repository="$(yq_get '.repository // ""')"

if (( have_smth_2_sync == 0 )); then
    notice 'Up to date' "This repository in sync with the \`${repository}\` template repository!"
    exit 0
fi

# No modified files in the repo means all of 'em was conflicts
if [[ -z "$(git status --porcelain=1 --untracked-files=no .)" ]]; then
    notice 'No PR' 'There are some pending changes. However, all of them require a manual merge!'
    report_conflicts cant_apply
    exit 0
fi

# Change the `last-sync` key in the config file
declare -rx last="$(git -C "$template_repo_path" rev-parse --short HEAD)"
sed -Ei "/^last-sync:/ s,$since,$last," "$CONFIG"

if (( make_pr == 0 )); then
    notice 'No PR' 'There are some pending changes. However, making PR is not enabled!'
    report_conflicts cant_apply
    exit 0
fi

echo '::group::Preparing a pull request'

# OK, there are some changes in this repo. Commit 'em into a new branch first.
git switch -c "sync-with-template-repo-$(date +"%Y%m%d%H%M%S")"

yq_get '.commit-message // env(DEFAULT_COMMIT_TITLE)' | git commit --no-verify -a -F -

git push -u origin HEAD

# Let's make a PR.
declare -r title="$(yq_get '.pr-title // (.commit-message | split("\n")[0]) // env(DEFAULT_COMMIT_TITLE)')"

yq_get '.pr-body // env(DEFAULT_PR_BODY)' | gh pr create --title "$title" --body-file -

declare -ir pr_id="$(gh pr view --json number -q .number)"

# Leave a comment if there are unmerged files
if [[ ${#cant_apply[@]} -ne 0 ]]; then
    {
        echo ':robot: However, the following file(s) require a manual merge:'
        for file in "${!cant_apply[@]}"; do
            echo "### \`${file}\`"
            echo '```diff'
            echo "${cant_apply[$file]}"
            echo '```'
        done
    } | gh pr comment "$pr_id" --body-file -
fi

echo '::endgroup::'
