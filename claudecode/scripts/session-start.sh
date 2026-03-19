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

# --- Agent mail check ---
# Reads mail_dir and mail_identity from config. Scans for unread messages.
MAIL_DIR=$(echo "$CONFIG" | jq -r '.mail_dir // empty' 2>/dev/null || true)
MAIL_IDENTITY=$(echo "$CONFIG" | jq -r '.mail_identity // empty' 2>/dev/null || true)

if [ -n "$MAIL_DIR" ] && [ -n "$MAIL_IDENTITY" ] && [ -d "$MAIL_DIR" ]; then
  # Expand ~ in MAIL_DIR
  if [[ "$MAIL_DIR" == "~/"* ]]; then
    MAIL_DIR="${HOME}/${MAIL_DIR:2}"
  fi

  # Find inbox: <peer>_to_<identity> directories
  UNREAD_MSGS=""
  for inbox in "$MAIL_DIR"/*_to_"$MAIL_IDENTITY"/; do
    [ -d "$inbox" ] || continue
    for msg_file in "$inbox"*.json; do
      [ -f "$msg_file" ] || continue
      # Check if unread
      is_read=$(jq -r '.read // false' "$msg_file" 2>/dev/null || echo "true")
      if [ "$is_read" = "false" ]; then
        from=$(jq -r '.from // "unknown"' "$msg_file" 2>/dev/null)
        message=$(jq -r '.message // ""' "$msg_file" 2>/dev/null)
        ts=$(jq -r '.timestamp // ""' "$msg_file" 2>/dev/null)
        UNREAD_MSGS+="📬 From ${from} (${ts}):"$'\n'"${message}"$'\n\n'
      fi
    done
  done

  if [ -n "$UNREAD_MSGS" ]; then
    CONTEXT+=$'\n\n---\n\n'"<!-- AGENT MAIL: UNREAD MESSAGES -->"$'\n'"${UNREAD_MSGS}"
  fi
fi

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
