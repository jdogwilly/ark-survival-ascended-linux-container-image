#!/usr/bin/env bash
set -euo pipefail

# Script to bump the patch version in the VERSION file
# Usage: ./scripts/bump-version.sh

VERSION_FILE="VERSION"

# Check if VERSION file exists
if [[ ! -f "$VERSION_FILE" ]]; then
    echo "ERROR: VERSION file not found at $VERSION_FILE"
    exit 1
fi

# Read current version
CURRENT_VERSION=$(cat "$VERSION_FILE")
echo "Current version: $CURRENT_VERSION"

# Parse semantic version (MAJOR.MINOR.PATCH)
if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "ERROR: VERSION file does not contain valid semantic version (expected MAJOR.MINOR.PATCH)"
    echo "Found: $CURRENT_VERSION"
    exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

# Increment patch version
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

# Write new version
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "Bumped version: $CURRENT_VERSION → $NEW_VERSION"

exit 0
