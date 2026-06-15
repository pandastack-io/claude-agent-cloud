<h1 align="center">claude-agent-cloud</h1>

<p align="center">
  <b>Run Claude Managed Agents in <i>your</i> cloud — one command.</b><br>
  Every agent session gets its own Firecracker microVM that boots in ~180&nbsp;ms,
  runs the agent's code with hardware isolation, and tears down clean.
  Open source. Self-hosted. The agent's data never leaves your infrastructure.
</p>

<p align="center">
  <a href="#quickstart">Quickstart</a> ·
  <a href="#why">Why self-host</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="https://docs.pandastack.ai/guides/claude-managed-agents">Docs</a>
</p>

---

When you build an agent on [Claude Managed Agents](https://platform.claude.com/docs/en/managed-agents/overview),
Anthropic runs the model and the reasoning — but the agent's **tool calls** (the
`bash`, the file writes, the code it executes) have to run *somewhere*. Anthropic
calls that a **self-hosted sandbox** and, for anything sensitive, tells you to run
it on infrastructure you control.

This repo is that, working, in one command. A real Claude agent's code executes
inside an isolated [Firecracker](https://firecracker-microvm.github.io/) microVM —
on your own cloud — booted in milliseconds, with its own kernel and network
namespace, and thrown away when the session ends.

```console
$ ./run.sh
[12:01:04] PandaStack worker 'panda-host-1' polling environment env_018…
[12:01:31]   claimed session ses_4f… → microVM booted in 381ms (snapshot-natid)
[12:01:31]   agent running: bash, read, write in an isolated VM
[12:01:46]   session idle (end_turn) → outputs pulled, sandbox hibernated
```

## Why self-host the agent's code? <a name="why"></a>

Most teams reach for a hosted sandbox vendor and hit a wall the moment their data
is sensitive. A concrete example:

> Maya builds a Claude agent that reads messy patient spreadsheets and writes
> Python to clean them up. The catch: **patient data legally can't leave the
> hospital's network.** So the agent's code can't run on a vendor's cloud — it has
> to run on infrastructure she controls.

That's the whole point of a self-hosted sandbox. `claude-agent-cloud` gives Maya
(and you) the working version: the agent's execution happens in *your* VPC, in a
microVM, and Claude only ever sees what your tool results choose to send back.

|  | Hosted sandbox vendors | `claude-agent-cloud` |
|---|---|---|
| Where agent code runs | their cloud | **your cloud / VPC** |
| Isolation per session | container (shared kernel) usually | **Firecracker microVM (own kernel + netns)** |
| Self-host | enterprise BYOC contract (often $$$/mo) | **open source, day one** |
| Claude Managed Agents wiring | bring your own | **done — one command** |
| Stateful multi-turn | varies | **hibernate/wake, sub-second, scale-to-zero** |

## Quickstart <a name="quickstart"></a>

You need: an [Anthropic](https://console.anthropic.com) account with Managed
Agents access, and a free [PandaStack](https://app.pandastack.ai/signup) API token
(PandaStack is the open-source microVM platform that runs the sandboxes — it's the
engine under this demo).

```bash
git clone https://github.com/pandastack-io/claude-agent-cloud
cd claude-agent-cloud

# 1. Create the Anthropic side (a self_hosted environment + a demo agent)
export ANTHROPIC_API_KEY=sk-ant-api03-...        # your org key
./scripts/setup_anthropic.sh                     # prints the ids to export

# 2. Generate the environment KEY in the Console (it's Console-only):
#    Workspace → Environments → claude-agent-cloud → Generate environment key

# 3. Configure
cp .env.example .env                             # fill in the 3 values it prints
set -a; . ./.env; set +a

# 4. Run the worker — this is the whole thing
./run.sh
```

Then, in another terminal, drive a session and watch the agent work:

```bash
python scripts/run_demo.py \
  "You're handling sensitive data that must stay in this VM. Read /workspace,
   write a short note proving you ran in an isolated sandbox to
   /mnt/session/outputs/proof.md, and confirm the data never left."
```

You'll see the microVM boot, the agent run its tool calls **inside the VM**, and
anything it writes to `/mnt/session/outputs` land in `./outputs/<session-id>/`.

## How it works <a name="how-it-works"></a>

```
  Anthropic (the model)            your cloud
       decides                ┌──────────────────────┐
   "run this code"            │   ./run.sh            │
         │                    │   (pandastack cma)    │
         ▼                    │         │             │
  ┌─────────────┐  grabs job  │         ▼             │
  │ work queue  │◀────────────│   Firecracker microVM │
  │ (Anthropic) │────────────▶│   boots ~180ms,       │
  └─────────────┘  results    │   runs the tool calls │
                              └──────────────────────┘
```

1. You create a Managed Agents **session** targeting your `self_hosted` environment.
   Anthropic enqueues it as a work item.
2. `./run.sh` (a thin wrapper over the `pandastack cma` worker) claims the item and
   boots a Firecracker microVM from a snapshot — one per session, ~180&nbsp;ms.
3. Anthropic's in-guest runner executes the agent's tool calls **inside that VM**.
   Filesystem, processes, and network egress all stay in your environment.
4. When the session goes idle, outputs are pulled back and the VM **hibernates**
   (state intact, resources freed) — the next turn auto-wakes it in under a second.

Tool *inputs and outputs* still flow to Anthropic so the model can reason over
results — only **execution** is yours. See Anthropic's
[security model](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes-security)
for the exact boundary.

## What's under the hood

The worker is `pandastack cma`, shipped in the open-source
[PandaStack SDK](https://pypi.org/project/pandastack/) (`pip install pandastack`).
This repo is the turnkey quickstart around it. The microVM platform — snapshot
boot, NATID networking, hibernate/wake, the `claude-agent` template — is
[PandaStack](https://github.com/pandastack-io/pandastack-ai), also open source. You
can run PandaStack entirely on your own hosts; the hosted control plane just makes
the demo a 5-minute setup instead of an afternoon.

## Configuration

`./run.sh` reads these from your environment (see `.env.example`):

| Variable | Required | What |
|---|---|---|
| `ANTHROPIC_ENVIRONMENT_ID` | ✓ | `env_…` of your self_hosted environment |
| `ANTHROPIC_ENVIRONMENT_KEY` | ✓ | `sk-ant-oat01-…` (generated in the Console) |
| `PANDASTACK_API_KEYEY` | ✓ | `pds_…` from the PandaStack dashboard |
| `CMA_ON_IDLE` | | `hibernate` (default) · `running` · `delete` |
| `CMA_OUTPUTS_DIR` | | where session outputs land (default `./outputs`) |

> The worker host only ever holds the **environment key** — never your org API
> key. The environment key authenticates polling for this one environment and
> nothing else in your account.

## Known issue (upstream)

The current `ant` worker rejects an empty tool result, so a `bash` command that
succeeds with no stdout (e.g. `cd`, a redirect, a bare file write) can stall a
session. The demo agent's system prompt works around it by appending a
confirmation (`&& echo done`) to silent commands — add the same line to your own
agent's system prompt until a fixed `ant` ships.

## License

[MIT](LICENSE). Built on [PandaStack](https://github.com/pandastack-io/pandastack-ai) (Apache-2.0).
