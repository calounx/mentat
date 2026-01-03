#!/usr/bin/env bash
# Helper script to check where your deployment files are
# Run this on mentat server to find the correct path

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          CHOM Deployment Location Checker                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "Searching for deploy-chom-automated.sh..."
echo ""

# Find all instances
found_paths=$(find ~ -name "deploy-chom-automated.sh" -type f 2>/dev/null)

if [[ -z "$found_paths" ]]; then
    echo "✗ deploy-chom-automated.sh NOT FOUND anywhere in your home directory"
    echo ""
    echo "You need to clone the repository:"
    echo "  cd ~"
    echo "  git clone https://github.com/calounx/mentat.git"
    exit 1
fi

echo "Found deployment script at:"
count=1
while IFS= read -r path; do
    echo "  $count. $path"
    ((count++))
done <<< "$found_paths"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          How to Run Deployment                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get the first (most likely correct) path
first_path=$(echo "$found_paths" | head -1)
deploy_dir=$(dirname "$first_path")
repo_root=$(dirname "$deploy_dir")

echo "1. Change to repository root:"
echo "   cd $repo_root"
echo ""
echo "2. Run deployment:"
echo "   sudo ./deploy/deploy-chom-automated.sh"
echo ""
echo "Full command to copy/paste:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "cd $repo_root && sudo ./deploy/deploy-chom-automated.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if we're already in the right directory
if [[ "$(pwd)" == "$repo_root" ]]; then
    echo "✓ You're already in the correct directory!"
    echo "  Just run: sudo ./deploy/deploy-chom-automated.sh"
else
    echo "Note: You're currently in: $(pwd)"
    echo "      You need to cd to: $repo_root"
fi
