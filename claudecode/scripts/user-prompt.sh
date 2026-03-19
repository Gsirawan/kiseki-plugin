#!/bin/bash
# kiseki user-prompt.sh
# Fires on every user message. Injects real-time time context, Hijri date,
# Ramadan flag, and reminders. Must complete in <100ms.
#
# Performance budget:
#   - One jq call  (config parse)
#   - One date call (time formatting)
#   - One cat call  (reminders, conditional)
#   - All Hijri math in bash $(( )) — zero extra processes

set -euo pipefail

CONFIG_PATH="${PWD}/.claude/kiseki.json"

if [ ! -f "$CONFIG_PATH" ]; then
  echo '{}'
  exit 0
fi

# --- Read config (single jq invocation) ---
# Extract timezone and reminders_path in one pass.
CONFIG_VALS=$(jq -r '
  (.timezone // "UTC"),
  (.reminders_path // "")
' "$CONFIG_PATH" 2>/dev/null || true)

if [ -z "$CONFIG_VALS" ]; then
  echo '{}'
  exit 0
fi

TZ_NAME=$(echo "$CONFIG_VALS" | sed -n '1p')
REMINDERS_RAW=$(echo "$CONFIG_VALS" | sed -n '2p')

# Default timezone if somehow blank
if [ -z "$TZ_NAME" ]; then
  TZ_NAME="UTC"
fi

# --- Single date call: get all needed fields at once ---
# Output: WEEKDAY|MONTH_NAME|DAY|YEAR|HOUR24|HOUR12|MINUTE|AMPM|MONTH_NUM
DATE_PARTS=$(TZ="$TZ_NAME" date '+%A|%B|%-d|%Y|%H|%I|%M|%p|%-m')

WEEKDAY=$(echo "$DATE_PARTS" | cut -d'|' -f1)
MONTH_NAME=$(echo "$DATE_PARTS" | cut -d'|' -f2)
G_DAY=$(echo "$DATE_PARTS" | cut -d'|' -f3)
G_YEAR=$(echo "$DATE_PARTS" | cut -d'|' -f4)
HOUR24=$(echo "$DATE_PARTS" | cut -d'|' -f5)
HOUR12=$(echo "$DATE_PARTS" | cut -d'|' -f6)
MINUTE=$(echo "$DATE_PARTS" | cut -d'|' -f7)
AMPM=$(echo "$DATE_PARTS" | cut -d'|' -f8)
G_MONTH=$(echo "$DATE_PARTS" | cut -d'|' -f9)

# Strip leading zero from HOUR24 for arithmetic (already stripped via %H but be safe)
HOUR24_INT=$(( 10#$HOUR24 ))

# --- Period of day ---
if   [ "$HOUR24_INT" -ge 0 ] && [ "$HOUR24_INT" -le 4 ]; then
  PERIOD="late night"
elif [ "$HOUR24_INT" -ge 5 ] && [ "$HOUR24_INT" -le 11 ]; then
  PERIOD="morning"
elif [ "$HOUR24_INT" -ge 12 ] && [ "$HOUR24_INT" -le 16 ]; then
  PERIOD="afternoon"
elif [ "$HOUR24_INT" -ge 17 ] && [ "$HOUR24_INT" -le 20 ]; then
  PERIOD="evening"
else
  PERIOD="night"
fi

# --- Hijri date (Kuwaiti/tabular algorithm) ---
# Ported exactly from gregorianToHijri() in kiseki-oc-plugin.ts.
# Variable names kept identical for traceability.
#
# Step 1: Gregorian -> Julian Day Number (JDN)
a=$(( (14 - G_MONTH) / 12 ))
y=$(( G_YEAR + 4800 - a ))
m=$(( G_MONTH + 12 * a - 3 ))
jdn=$(( G_DAY + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045 ))

# Step 2: JDN -> Hijri (tabular Islamic calendar)
# Epoch: 1 Muharram 1 AH = JDN 1948440
l=$(( jdn - 1948440 + 10632 ))
n=$(( (l - 1) / 10631 ))
remainder=$(( l - 10631 * n + 354 ))
j=$(( (10985 - remainder) / 5316 * ((50 * remainder) / 17719) + (remainder / 5670) * ((43 * remainder) / 15238) ))
adjustedRemainder=$(( remainder - (30 - j) / 15 * ((17719 * j) / 50) - (j / 16) * ((15238 * j) / 43) + 29 ))
hMonth=$(( (24 * adjustedRemainder) / 709 ))
hDay=$(( adjustedRemainder - (709 * hMonth) / 24 ))
hYear=$(( 30 * n + j - 30 ))

# Islamic month names (1-indexed)
HIJRI_MONTHS=("" "Muharram" "Safar" "Rabi al-Awwal" "Rabi al-Thani" "Jumada al-Ula" "Jumada al-Thani" "Rajab" "Shaban" "Ramadan" "Shawwal" "Dhul Qadah" "Dhul Hijjah")
HIJRI_MONTH_NAME="${HIJRI_MONTHS[$hMonth]:-Month $hMonth}"

HIJRI_STRING="${hDay} ${HIJRI_MONTH_NAME} ${hYear} AH"

# Ramadan flag (hMonth == 9)
IS_RAMADAN=0
if [ "$hMonth" -eq 9 ]; then
  IS_RAMADAN=1
fi

# --- Reminders ---
REMINDERS_CONTENT=""
if [ -n "$REMINDERS_RAW" ]; then
  # Expand ~ to $HOME
  if [[ "$REMINDERS_RAW" == "~/"* ]]; then
    REMINDERS_PATH="${HOME}/${REMINDERS_RAW:2}"
  elif [[ "$REMINDERS_RAW" == "~" ]]; then
    REMINDERS_PATH="$HOME"
  elif [[ "$REMINDERS_RAW" == "./"* ]] || [[ "$REMINDERS_RAW" != "/"* ]]; then
    # Relative path — resolve against CWD
    REMINDERS_PATH="${PWD}/${REMINDERS_RAW#./}"
  else
    REMINDERS_PATH="$REMINDERS_RAW"
  fi

  if [ -f "$REMINDERS_PATH" ]; then
    REMINDERS_CONTENT=$(cat "$REMINDERS_PATH")
  fi
fi

# --- Build the time context block ---
BLOCK="<!-- KISEKI TIME CONTEXT -->
Current time: ${WEEKDAY}, ${MONTH_NAME} ${G_DAY}, ${G_YEAR} at ${HOUR12}:${MINUTE} ${AMPM} (${TZ_NAME})
Period: ${PERIOD}
Islamic date: ${HIJRI_STRING}"

if [ "$IS_RAMADAN" -eq 1 ]; then
  BLOCK+=$'\n'"🌙 Ramadan Mubarak - be mindful of fasting hours and spiritual context."
fi

if [ -n "$REMINDERS_CONTENT" ]; then
  BLOCK+=$'\n'"${REMINDERS_CONTENT}"
fi

BLOCK+=$'\n'"<!-- END KISEKI TIME CONTEXT -->"

# --- Output JSON ---
BLOCK_ESCAPED=$(printf '%s' "$BLOCK" | jq -Rs .)

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": ${BLOCK_ESCAPED}
  }
}
EOF
