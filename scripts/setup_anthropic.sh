#!/usr/bin/env bash
# Create the Anthropic side: a self_hosted environment and a demo agent.
# Prints the ids to export. The environment KEY is Console-only — this script
# can't generate it (you do that step in the Console, see the output below).
#
# Usage:
#   export ANTHROPIC_API_KEY=sk-ant-api03-...
#   ./scripts/setup_anthropic.sh
set -euo pipefail

: "${ANTHROPIC_API_KEY:?set ANTHROPIC_API_KEY (your org key) first}"
API="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
H=(-H "x-api-key: $ANTHROPIC_API_KEY"
   -H "anthropic-version: 2023-06-01"
   -H "anthropic-beta: managed-agents-2026-04-01"
   -H "content-type: application/json")

echo "Creating self_hosted environment 'claude-agent-cloud'…"
ENV_JSON=$(curl -fsSL "$API/v1/environments" "${H[@]}" \
  -d '{"name":"claude-agent-cloud","config":{"type":"self_hosted"}}')
ENV_ID=$(printf '%s' "$ENV_JSON" | jq -r '.id')
echo "  environment: $ENV_ID"

echo "Creating demo agent…"
AGENT_JSON=$(curl -fsSL "$API/v1/agents" "${H[@]}" -d @- <<'JSON'
{
  "name": "claude-agent-cloud-demo",
  "description": "Demo agent that runs its tool calls in an isolated, self-hosted PandaStack microVM",
  "model": {"id": "claude-sonnet-4-6"},
  "system": "You are an agent running inside an isolated Firecracker microVM that the operator self-hosts in their own cloud. Treat anything in this VM as sensitive: it must never leave the sandbox. You can write code, run shell commands, and read/write files in /workspace. Write any final deliverables to /mnt/session/outputs. When you run a shell command that would produce no output (for example cd, a redirect, or a file write), append a confirmation such as `&& echo done` so the command always prints at least one line.",
  "tools": [{"type": "agent_toolset_20260401", "default_config": {"enabled": true, "permission_policy": {"type": "always_allow"}}}]
}
JSON
)
AGENT_ID=$(printf '%s' "$AGENT_JSON" | jq -r '.id')
echo "  agent: $AGENT_ID"

cat <<EOF

Done. Next:
  1. Generate the environment KEY in the Console (Console-only):
       Workspace > Environments > claude-agent-cloud > Generate environment key
  2. Put these in your .env (cp .env.example .env):
       ANTHROPIC_ENVIRONMENT_ID=$ENV_ID
       ANTHROPIC_ENVIRONMENT_KEY=sk-ant-oat01-...   # from step 1
       CMA_AGENT_ID=$AGENT_ID                         # only needed for run_demo.py
EOF
