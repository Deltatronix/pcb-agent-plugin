#!/bin/sh
# The skill's plan step must not name `expectedRevision`: pcb_plan_propose's schema
# refuses it (additionalProperties: false), so a client that sends it fails its first call.
# It must also say that approval adds expertise skills (Deltatronix-pcb#4587): an approved
# pcb_plan_get returns them, so "skills do not change during the plan" is wrong.
# Usage: scripts/check-skill.sh [SKILL.md]
skill=${1:-"$(dirname "$0")/../skills/pcb-agent/SKILL.md"}
step=$(awk '/^2\. Propose one plan with `pcb_plan_propose`/{on=1} on&&/^3\. /{exit} on' "$skill")
[ -n "$step" ] || { echo "check-skill: plan step not found in $skill" >&2; exit 1; }
if printf '%s\n' "$step" | grep -n expectedRevision; then
  echo "check-skill: the pcb_plan_propose step names expectedRevision" >&2
  exit 1
fi
if ! printf '%s\n' "$step" | grep -q 'the approval adds the expertise'; then
  echo "check-skill: the plan step does not say that approval adds expertise skills" >&2
  exit 1
fi
if printf '%s\n' "$step" | grep -n 'do not change during the plan'; then
  echo "check-skill: the plan step says pinned skills do not change during the plan" >&2
  exit 1
fi
echo "check-skill: ok"
