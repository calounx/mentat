#!/bin/bash
#===============================================================================
# Progress Indicator Library
# Provides progress bars and spinners for long-running operations
#
# Usage:
#   source ./lib/progress.sh
#   show_spinner "Downloading..." &
#   SPINNER_PID=$!
#   # ... long operation ...
#   kill $SPINNER_PID 2>/dev/null
#===============================================================================

# Progress bar characters
PROGRESS_BAR_CHAR="="
PROGRESS_BAR_WIDTH=50

# Spinner frames
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

#===============================================================================
# SPINNER
#===============================================================================

# Show a spinner with a message
# Usage: show_spinner "Message" &
#        SPINNER_PID=$!
#        ... do work ...
#        kill $SPINNER_PID 2>/dev/null
show_spinner() {
    local message="$1"
    local delay=0.1
    local frame=0

    # Hide cursor
    tput civis 2>/dev/null || true

    while true; do
        printf "\r\033[K%s %s" "${SPINNER_FRAMES[$frame]}" "$message"
        frame=$(( (frame + 1) % ${#SPINNER_FRAMES[@]} ))
        sleep $delay
    done
}

# Stop spinner and show completion message
# Usage: stop_spinner $SPINNER_PID "Completed message"
stop_spinner() {
    local pid=$1
    local message="${2:-Done}"

    if kill "$pid" 2>/dev/null; then
        wait "$pid" 2>/dev/null || true
    fi

    # Clear line and show message
    printf "\r\033[K%s\n" "$message"

    # Show cursor
    tput cnorm 2>/dev/null || true
}

#===============================================================================
# PROGRESS BAR
#===============================================================================

# Show a progress bar
# Usage: show_progress 50 100 "Installing"
#        (shows 50% progress with message)
show_progress() {
    local current=$1
    local total=$2
    local message="${3:-Progress}"

    local percent=$((current * 100 / total))
    local filled=$((current * PROGRESS_BAR_WIDTH / total))
    local empty=$((PROGRESS_BAR_WIDTH - filled))

    # Build progress bar
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="${PROGRESS_BAR_CHAR}"
    done
    for ((i=0; i<empty; i++)); do
        bar+=" "
    done

    # Print progress bar (overwrites previous line)
    printf "\r[%s] %3d%% %s" "$bar" "$percent" "$message"

    # Print newline on completion
    if [[ $current -eq $total ]]; then
        printf "\n"
    fi
}

#===============================================================================
# TIMED OPERATIONS
#===============================================================================

# Run command and show elapsed time
# Usage: with_timer "Description" command arg1 arg2
with_timer() {
    local description="$1"
    shift

    local start_time
    start_time=$(date +%s)

    echo -ne "\033[0;34m[....]\033[0m $description ... "

    # Run command
    if "$@" >/dev/null 2>&1; then
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - start_time))

        echo "\r\033[0;32m[ OK ]\033[0m $description (${elapsed}s)"
        return 0
    else
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - start_time))

        echo "\r\033[0;31m[FAIL]\033[0m $description (${elapsed}s)"
        return 1
    fi
}

#===============================================================================
# STEP COUNTER
#===============================================================================

# Global step counter variables
CURRENT_STEP=0
TOTAL_STEPS=0

# Initialize step counter
# Usage: init_steps 10  # 10 total steps
init_steps() {
    TOTAL_STEPS=$1
    CURRENT_STEP=0
}

# Show step progress
# Usage: step "Installing Prometheus"
step() {
    local message="$1"
    ((CURRENT_STEP++))

    echo ""
    echo "\033[1;36m[Step $CURRENT_STEP/$TOTAL_STEPS]\033[0m $message"
    echo ""
}

#===============================================================================
# DOWNLOAD PROGRESS
#===============================================================================

# Download with progress bar
# Usage: download_with_progress "URL" "output_file" "Description"
download_with_progress() {
    local url="$1"
    local output="$2"
    local description="${3:-Downloading}"

    echo "$description ..."

    # Use wget with progress bar
    if command -v wget &>/dev/null; then
        wget --progress=bar:force:noscroll \
             --show-progress \
             --no-verbose \
             -O "$output" \
             "$url" 2>&1 | \
            grep --line-buffered -oP '\d+%' | \
            while read -r percent; do
                printf "\r  Progress: %s" "$percent"
            done
        printf "\n"
        return ${PIPESTATUS[0]}
    fi

    # Fallback to curl with progress
    if command -v curl &>/dev/null; then
        curl -# -L -o "$output" "$url"
        return $?
    fi

    echo "Error: Neither wget nor curl is available"
    return 1
}

#===============================================================================
# WAITING ANIMATION
#===============================================================================

# Show waiting animation while condition is true
# Usage: wait_for "Service is starting" "test_function" 30
#        (waits up to 30 seconds)
wait_for() {
    local message="$1"
    local test_cmd="$2"
    local timeout="${3:-60}"
    local delay=0.5

    local elapsed=0
    local frame=0

    # Hide cursor
    tput civis 2>/dev/null || true

    while [[ $elapsed -lt $timeout ]]; do
        if eval "$test_cmd" 2>/dev/null; then
            printf "\r\033[K\033[0;32m✓\033[0m %s\n" "$message"
            tput cnorm 2>/dev/null || true
            return 0
        fi

        printf "\r%s %s (%.1fs)" "${SPINNER_FRAMES[$frame]}" "$message" "$elapsed"
        frame=$(( (frame + 1) % ${#SPINNER_FRAMES[@]} ))

        sleep $delay
        elapsed=$(awk "BEGIN {print $elapsed + $delay}")
    done

    printf "\r\033[K\033[0;31m✗\033[0m %s (timeout after ${timeout}s)\n" "$message"
    tput cnorm 2>/dev/null || true
    return 1
}

#===============================================================================
# CLEANUP
#===============================================================================

# Ensure cursor is shown on script exit
cleanup_progress() {
    tput cnorm 2>/dev/null || true
}

# Register cleanup
trap cleanup_progress EXIT INT TERM
