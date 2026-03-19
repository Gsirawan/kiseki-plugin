#!/bin/bash
# kiseki session-start.sh
# Fires once at session start. Reads foundation_paths from .claude/kiseki.json
# and injects each file's content into the system context.
# If config is absent, exits silently with empty JSON (plugin inactive).

set -euo pipefail

# Read stdin (CC passes session context as JSON)
STDIN_DATA=$(cat)

# Extract CWD from hook input — fall back to PWD if not present
HOOK_CWD=$(echo "$STDIN_DATA" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$HOOK_CWD" ]; then
  HOOK_CWD="${PWD}"
fi

CONFIG_PATH="${HOOK_CWD}/.claude/kiseki.json"

# If no config, this project has kiseki disabled — output nothing meaningful and exit.
if [ ! -f "$CONFIG_PATH" ]; then
  echo '{}'
  exit 0
fi

# Read the entire config once.
CONFIG=$(cat "$CONFIG_PATH")

# Extract foundation_paths array. If key is absent or null, jq outputs nothing.
PATHS=$(echo "$CONFIG" | jq -r '(.foundation_paths // [])[]' 2>/dev/null || true)

if [ -z "$PATHS" ]; then
  echo '{}'
  exit 0
fi

CONTEXT=""

while IFS= read -r raw_path; do
  # Expand ~ to $HOME
  if [[ "$raw_path" == "~/"* ]]; then
    expanded_path="${HOME}/${raw_path:2}"
  elif [[ "$raw_path" == "~" ]]; then
    expanded_path="$HOME"
  else
    expanded_path="$raw_path"
  fi

  # Skip missing files silently
  if [ ! -f "$expanded_path" ]; then
    continue
  fi

  filename=$(basename "$expanded_path")
  file_content=$(cat "$expanded_path")

  if [ -n "$CONTEXT" ]; then
    CONTEXT+=$'\n\n---\n\n'
  fi
  CONTEXT+="<!-- FILE: ${filename} -->"$'\n'"${file_content}"

done <<< "$PATHS"

if [ -z "$CONTEXT" ]; then
  echo '{}'
  exit 0
fi

CONTEXT_ESCAPED=$(printf '%s' "$CONTEXT" | jq -Rs .)

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ${CONTEXT_ESCAPED}
  }
}
EOF
