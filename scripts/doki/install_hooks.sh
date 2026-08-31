#!/usr/bin/env bash
set -euo pipefail

# DOKI Git Hooks Installer
# Symlinks .githooks/* to .git/hooks/
# Run this once after cloning the repo

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT_DIR" ]; then
    echo "ERROR: Not in a git repository" >&2
    exit 1
fi

cd "$ROOT_DIR"

GITHOOKS_DIR="$ROOT_DIR/.githooks"
GIT_HOOKS_DIR="$ROOT_DIR/.git/hooks"

if [ ! -d "$GITHOOKS_DIR" ]; then
    echo "ERROR: .githooks directory not found at $GITHOOKS_DIR" >&2
    exit 1
fi

if [ ! -d "$GIT_HOOKS_DIR" ]; then
    echo "ERROR: .git/hooks directory not found at $GIT_HOOKS_DIR" >&2
    exit 1
fi

echo "Installing git hooks from $GITHOOKS_DIR to $GIT_HOOKS_DIR"

for hook in "$GITHOOKS_DIR"/*; do
    [ -f "$hook" ] || continue
    hook_name="$(basename "$hook")"
    target="$GIT_HOOKS_DIR/$hook_name"
    
    # Remove existing hook (file or symlink)
    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -f "$target"
    fi
    
    # Create symlink
    ln -s "$hook" "$target"
    chmod +x "$hook"
    echo "  Linked: $hook_name"
done

# Configure git to use .githooks as core.hooksPath (alternative to symlinks)
git config core.hooksPath "$GITHOOKS_DIR"

echo "Git hooks installed successfully."
echo "Hooks will run on: pre-commit, commit-msg, post-commit"
echo ""
echo "Note: GODOT_BIN must be set and executable for hooks to run fully."
echo "      export GODOT_BIN=/path/to/godot_console"