#!/usr/bin/env bash
################################################################################
# migrate-to-main.sh
#
# Automated migration script to standardize on 'main' as the default branch
# for the CHOM project repository.
#
# This script:
# - Renames local 'master' branch to 'main' if it exists
# - Updates remote tracking to use 'main'
# - Updates git configuration for default branch
# - Does NOT delete remote branches (requires manual approval)
#
# Usage:
#   ./migrate-to-main.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be done without making changes
#
# Author: CHOM Team
# Version: 2.2.0
# Date: 2026-01-10
################################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

run_command() {
    local cmd="$*"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: ${BLUE}${cmd}${NC}"
        return 0
    else
        log_info "Executing: ${cmd}"
        eval "$cmd"
    fi
}

check_git_repo() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not a git repository. Please run this script from the repository root."
        exit 1
    fi
    log_success "Git repository detected"
}

get_current_branch() {
    git branch --show-current
}

branch_exists() {
    local branch="$1"
    git show-ref --verify --quiet "refs/heads/${branch}"
}

remote_branch_exists() {
    local remote="$1"
    local branch="$2"
    git ls-remote --heads "${remote}" "${branch}" | grep -q "${branch}"
}

check_uncommitted_changes() {
    if ! git diff-index --quiet HEAD --; then
        log_error "You have uncommitted changes. Please commit or stash them before proceeding."
        git status --short
        exit 1
    fi
    log_success "Working directory is clean"
}

migrate_local_branch() {
    log_info "Checking for local 'master' branch..."

    if ! branch_exists "master"; then
        log_warning "Local 'master' branch does not exist. Skipping local branch migration."
        return 0
    fi

    log_info "Local 'master' branch found. Proceeding with migration..."

    # Check if 'main' already exists
    if branch_exists "main"; then
        log_warning "Local 'main' branch already exists."
        log_info "Comparing 'master' and 'main' branches..."

        local master_commit=$(git rev-parse master)
        local main_commit=$(git rev-parse main)

        if [[ "$master_commit" == "$main_commit" ]]; then
            log_success "Branches 'master' and 'main' point to the same commit. Safe to delete 'master'."
            run_command "git branch -d master"
        else
            log_error "Branches 'master' and 'main' have diverged!"
            log_error "master: ${master_commit}"
            log_error "main: ${main_commit}"
            log_error "Please resolve manually before proceeding."
            exit 1
        fi
    else
        # Get current branch before renaming
        local current_branch=$(get_current_branch)

        # If currently on master, we need to switch after renaming
        if [[ "$current_branch" == "master" ]]; then
            log_info "Currently on 'master' branch. Will switch to 'main' after rename."
        fi

        # Rename master to main
        run_command "git branch -m master main"
        log_success "Renamed local branch 'master' to 'main'"
    fi
}

update_remote_tracking() {
    log_info "Updating remote tracking configuration..."

    # Get list of remotes
    local remotes=$(git remote)

    if [[ -z "$remotes" ]]; then
        log_warning "No remotes configured. Skipping remote tracking update."
        return 0
    fi

    for remote in $remotes; do
        log_info "Checking remote: ${remote}"

        # Check if remote has 'main' branch
        if remote_branch_exists "$remote" "main"; then
            log_info "Remote '${remote}' has 'main' branch. Updating tracking..."
            run_command "git branch --set-upstream-to=${remote}/main main"
            log_success "Updated tracking for '${remote}/main'"
        elif remote_branch_exists "$remote" "master"; then
            log_warning "Remote '${remote}' still uses 'master' branch."
            log_warning "You may need to rename the remote branch manually:"
            log_warning "  1. Push main branch: git push ${remote} main"
            log_warning "  2. Update default branch on remote (GitHub/GitLab/etc.)"
            log_warning "  3. Delete remote master: git push ${remote} --delete master"
        else
            log_warning "Remote '${remote}' has neither 'main' nor 'master' branch."
        fi
    done
}

update_git_config() {
    log_info "Updating git configuration..."

    # Set default branch name for new repositories
    run_command "git config --local init.defaultBranch main"
    log_success "Set default branch to 'main' for this repository"

    # Update symbolic ref if needed
    if [[ "$DRY_RUN" == "false" ]]; then
        if git symbolic-ref refs/remotes/origin/HEAD >/dev/null 2>&1; then
            local current_head=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || echo "")
            if [[ "$current_head" == "refs/remotes/origin/master" ]]; then
                run_command "git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main"
                log_success "Updated origin/HEAD to point to main"
            fi
        fi
    fi
}

show_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${GREEN}Migration Summary${NC}"
    echo "═══════════════════════════════════════════════════════════════"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}DRY-RUN MODE - No actual changes were made${NC}"
        echo ""
    fi

    echo "Current branch: $(get_current_branch)"
    echo ""
    echo "Local branches:"
    git branch -vv
    echo ""

    echo "Remote branches:"
    git branch -r
    echo ""

    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${GREEN}Next Steps${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "If you have push access to the remote repository:"
    echo "  1. Push the 'main' branch:"
    echo "     ${BLUE}git push -u origin main${NC}"
    echo ""
    echo "  2. Update the default branch on your Git hosting platform:"
    echo "     - GitHub: Repository Settings → Branches → Default branch"
    echo "     - GitLab: Repository Settings → Repository → Default Branch"
    echo "     - Bitbucket: Repository Settings → Branch Management"
    echo ""
    echo "  3. After confirming 'main' is the new default, delete 'master':"
    echo "     ${BLUE}git push origin --delete master${NC}"
    echo ""
    echo "For team members who have already cloned the repository:"
    echo "  1. Fetch the latest changes:"
    echo "     ${BLUE}git fetch origin${NC}"
    echo ""
    echo "  2. Switch to the new 'main' branch:"
    echo "     ${BLUE}git checkout main${NC}"
    echo ""
    echo "  3. Update tracking:"
    echo "     ${BLUE}git branch -u origin/main main${NC}"
    echo ""
    echo "  4. Delete local 'master' branch:"
    echo "     ${BLUE}git branch -d master${NC}"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Migrate repository from 'master' to 'main' branch.

OPTIONS:
    --dry-run       Show what would be done without making changes
    -h, --help      Show this help message

DESCRIPTION:
    This script automates the migration from 'master' to 'main' branch:

    1. Checks for uncommitted changes
    2. Renames local 'master' branch to 'main' (if exists)
    3. Updates remote tracking configuration
    4. Updates git configuration for default branch
    5. Provides instructions for remote repository updates

    The script does NOT:
    - Delete remote branches (requires manual approval)
    - Force push to remote repositories
    - Modify repository settings on hosting platforms

EXAMPLES:
    # Perform a dry-run to see what would happen
    $0 --dry-run

    # Perform the actual migration
    $0

EOF
}

################################################################################
# Main
################################################################################

main() {
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $arg"
                show_help
                exit 1
                ;;
        esac
    done

    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${BLUE}CHOM Branch Migration: master → main${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY-RUN mode - no changes will be made"
        echo ""
    fi

    # Pre-flight checks
    log_info "Running pre-flight checks..."
    check_git_repo
    check_uncommitted_changes
    echo ""

    # Perform migration steps
    log_info "Starting migration process..."
    echo ""

    migrate_local_branch
    echo ""

    update_remote_tracking
    echo ""

    update_git_config
    echo ""

    # Show summary
    show_summary

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "To perform the actual migration, run: $0"
    else
        log_success "Migration completed successfully!"
    fi
}

# Run main function
main "$@"
