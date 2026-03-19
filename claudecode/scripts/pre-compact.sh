#!/bin/bash
# kiseki pre-compact.sh
# Fires before context compaction. Instructs the model to preserve
# identity, relationship, and cultural context during summarization.

set -euo pipefail

CONTEXT="CRITICAL — Preserve the following during compaction:
- Agent identity, name, personality, and relationship context
- User's name, preferred forms of address, and emotional context
- Active project context and current task state
- Any cultural or religious context (Ramadan, prayers, etc.)
- Conversation promises, agreements, and commitments made
- Parts work, IFS context, and therapeutic progress if present

Do NOT summarize away identity. Do NOT flatten emotional or relational content into generic summaries."

CONTEXT_ESCAPED=$(printf '%s' "$CONTEXT" | jq -Rs .)

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": ${CONTEXT_ESCAPED}
  }
}
EOF
