#!/usr/bin/env bash
# claude-agent-cloud — run a self-hosted Claude Managed Agents worker.
#
# Boots a Firecracker microVM per agent session (via the open-source PandaStack
# `pandastack cma` worker) so the agent's code runs isolated, in your own cloud.
#
# Usage:
#   cp .env.example .env   # fill it in, then:
#   set -a; . ./.env; set +a
#   ./run.sh
set -euo pipefail

# Load .env if present and the caller didn't already export it.
if [[ -f .env && -z "${PANDASTACK_API_KEY:-}" ]]; then
  set -a; . ./.env; set +a
fi

missing=()
[[ -n "${ANTHROPIC_ENVIRONMENT_ID:-}"  ]] || missing+=("ANTHROPIC_ENVIRONMENT_ID")
[[ -n "${ANTHROPIC_ENVIRONMENT_KEY:-}" ]] || missing+=("ANTHROPIC_ENVIRONMENT_KEY")
[[ -n "${PANDASTACK_API_KEY:-}"          ]] || missing+=("PANDASTACK_API_KEY")
if (( ${#missing[@]} )); then
  echo "error: missing required config: ${missing[*]}" >&2
  echo "  → copy .env.example to .env, fill it in, then: set -a; . ./.env; set +a" >&2
  echo "  → run ./scripts/setup_anthropic.sh first if you don't have the env id/agent yet" >&2
  exit 1
fi

# Ensure the worker (PandaStack SDK) is available; install on demand.
if ! command -v pandastack >/dev/null 2>&1 && ! python3 -c "import pandastack" >/dev/null 2>&1; then
  echo "Installing the PandaStack SDK (provides the 'pandastack cma' worker)…"
  python3 -m pip install --quiet --upgrade pandastack
fi

echo "Starting the self-hosted Claude Managed Agents worker…"
echo "  environment: ${ANTHROPIC_ENVIRONMENT_ID}"
echo "  on idle:     ${CMA_ON_IDLE:-hibernate}"
echo

# `pandastack cma` polls the work queue and runs each session in its own microVM.
if command -v pandastack >/dev/null 2>&1; then
  exec pandastack cma
else
  exec python3 -m pandastack cma
fi
