# Project Sardaukar

## What This Is

A self-hosted, Dockerized AI agent platform that autonomously manages multiple GitHub organizations. A single TPM (Technical Program Manager) agent runs continuously and spawns SWE and QA subagents on demand to handle issue triage, PR management, vulnerability remediation, and kanban board tracking. The human checks in from their phone when needed — otherwise the agents handle it.

## Design Principles

- **Simplicity over cleverness** — file-based queue over Redis, naming conventions over separate GitHub accounts, flat config over databases.
- **Zero destructive actions** — agents can never delete repos, branches, issues, PRs, board items, or anything else. Close and archive only.
- **Human PRs are sacred** — agents review but never merge human-created PRs. Only agent PRs (identified by branch naming convention) can be auto-merged.
- **No repo settings changes** — agents can request a human to enable Dependabot or set branch protection, but cannot do it themselves.
- **No new repos** — agents monitor and maintain existing repos only.
- **Everything containerized** — the entire platform runs via `docker compose up`. No host dependencies beyond Docker, `gh`, and `~/.claude` auth.
- **Single source of truth for orgs** — `.claude/config/organizations.yml` is the only place org names, project board URLs, and webhook secrets are defined. Never hardcode org names in agent prompts or application code.
- **TPM is the orchestrator** — one long-running container. SWE and QA are ephemeral subagents spawned via Claude's Agent tool. No polling, no idle containers.
- **Configurable concurrency** — `SWE_AGENT_COUNT` in `.env` controls max concurrent SWE subagents (default: 3).

---

## Architecture

```
Host Server
├── docker-compose
│   ├── tpm-agent              — The orchestrator (spawns SWE/QA subagents on demand)
│   ├── webhook-listener       — Node.js, receives GitHub events, writes to file queue
│   ├── dashboard              — Serves TPM's remote-control session URL (password-protected)
│   ├── ctrl                   — Bulletproof Ctrl for real-time agent monitoring
│   └── cron                   — Triggers 30-min sweep cycle
├── Reverse proxy (Caddy/nginx/etc.)
│   ├── webhooks.<domain>      → webhook-listener (port 3800)
│   └── agents.<domain>        → dashboard (port 3801, basic auth)
└── Shared volumes
    ├── /queue                 — Webhook event queue
    ├── /logs                  — Agent activity logs
    ├── /sessions              — TPM remote-control URL
    └── ~/.claude              — Auth (ro) + session logs (rw)
```

---

## Agent Roles

### TPM (1 container, long-running)

The orchestrator. Does not write code. Spawns SWE and QA subagents.

- Sole consumer of the webhook queue
- Triages incoming issues — reads title/body, auto-labels
- Spawns SWE subagents for code work, passing full context and assignment details
- Spawns QA subagents when PRs are ready for review
- Respects `SWE_AGENT_COUNT` for max concurrent SWE subagents (default: 3)
- Ranks difficulty and routes model: Low/Medium → Sonnet, High → Opus
- Manages kanban board state across all orgs: Backlog → Ready → In progress → In review → Done
- Auto-archives Done items after 7 days to keep the board clean (archived cards are still searchable via `is:archived`)
- Handles subagent results: chains SWE → QA → Done, or escalates to human
- Provides standup-style summary when user connects
- Can create new issues
- Runs periodic 30-minute cron sweep as safety net
- Logs with `[TPM]` prefix

Does NOT: write code, approve PRs, merge PRs, delete anything.

### SWE (ephemeral subagents, spawned by TPM)

Full-stack developers. TPM assigns an instance number (SWE-1, SWE-2, etc.) when spawning.

- Receive assignment directly from TPM with full context — no polling
- Branch naming: `fix/swe-<N>/<package>-<version>` or `feat/swe-<N>/<description>`
- Implement fixes and features, run tests locally before pushing
- Create PRs with descriptive titles and bodies
- For complex fixes (major version bumps with breaking changes): flag for human escalation
- Return results to TPM: PR number, success/failure/escalation
- Log with `[SWE-<N>]` prefix

Does NOT: approve own PRs, move board cards, triage issues, delete anything.

### QA (ephemeral subagent, spawned by TPM)

Reviewer, tester, gatekeeper.

- Receives specific PR to review from TPM — no polling
- Reviews code, runs tests independently
- Agent PRs (branch matches `fix/swe-<N>/...` or `feat/swe-<N>/...`): can approve AND merge
- Human PRs (branch doesn't match agent convention): reviews and comments, does NOT merge
- Returns results to TPM: approved/merged, changes requested, or review summary
- Log with `[QA]` prefix

Does NOT: write feature code, triage issues, delete anything.

---

## Subagent Flow

```
TPM receives event (webhook or sweep)
  → Triages: what kind of work?
    → Spawns SWE subagent with full context
      → SWE does work, opens PR, returns result
        → TPM spawns QA subagent to review
          → QA reviews, merges (agent PR) or comments (human PR), returns result
            → TPM updates kanban board
```

For QA requesting changes:
```
QA returns "changes requested" to TPM
  → TPM spawns new SWE subagent with QA feedback
    → SWE addresses review, pushes update
      → TPM spawns QA again
```

---

## Three Input Channels

1. **Webhooks (real-time)** — GitHub sends events to `webhooks.<domain>/hooks/github`. The listener validates signatures per-org, writes JSON envelopes to the file queue, and TPM processes them.

2. **Cron sweep (every 30 min)** — TPM checks all orgs/repos for anything webhooks may have missed. Configurable to 15 minutes.

3. **Human via phone (on-demand)** — User visits `agents.<domain>` (password-protected), sees TPM's session URL, taps to connect via Claude `--remote-control`.

---

## Webhook Queue

### Listener (Node.js)

- Single endpoint: `POST /hooks/github` for all orgs
- Identifies org from `organization.login` field in the GitHub payload
- Validates `X-Hub-Signature-256` using per-org secret from `organizations.yml`
- Writes JSON envelope to `/queue/incoming/<timestamp>_<org>_<event>_<id>.json` (atomic write-then-rename)
- Health check: `GET /health`

### Queue Directories

| Directory | Purpose |
|-----------|---------|
| `queue/incoming/` | New events waiting to be processed |
| `queue/processing/` | Currently being handled by TPM |
| `queue/done/` | Successfully processed |
| `queue/failed/` | Failed — needs attention |

### Event → Action Mapping (TPM)

| Event | Action |
|-------|--------|
| `issues` | Triage, label, add to board |
| `pull_request` | Track on board, spawn QA if agent PR |
| `dependabot_alert` / `repository_vulnerability_alert` | Spawn SWE to fix |
| `push` | Update board if relevant |
| `repository` | Add new repos to monitoring |
| `issue_comment` | Check if human gave go-ahead on flagged PR |

---

## Model Routing

TPM assesses difficulty at triage time:

| Difficulty | Model | Examples |
|-----------|-------|----------|
| Low | Sonnet | Label updates, simple dependency bumps, docs fixes |
| Medium | Sonnet | Standard feature work, bug fixes with clear scope |
| High | Opus | Complex refactors, multi-file changes, breaking change upgrades |

---

## Dependabot Workflow (Flagship Feature)

1. Dependabot flags a vulnerability
2. Webhook fires → TPM picks up, triages difficulty
3. TPM spawns SWE subagent with alert details and model recommendation
4. SWE creates branch (`fix/swe-1/lodash-4.17.21`), implements fix, runs tests
5. SWE opens PR, returns result to TPM
6. TPM moves kanban card to "In review", spawns QA subagent
7. QA reviews, runs tests independently
8. Pass → QA approves and merges, returns to TPM, TPM moves card to "Done"
9. Complex (major version bump) → SWE flags for human, TPM moves card back to "Backlog" with escalation note

---

## Docker Setup

### Services

| Service | Ports | Volumes | Notes |
|---------|-------|---------|-------|
| `tpm-agent` | — | `~/.claude` (auth:ro, projects:rw), `~/.config/gh` (ro), `/queue`, `/logs`, `/sessions`, `.claude/` (agent defs:ro) | Spawns SWE/QA subagents via Agent tool |
| `webhook-listener` | 3800 | `/queue`, `organizations.yml` (ro) | Receives GitHub webhooks |
| `dashboard` | 3801 | `/sessions` (ro) | Shows TPM session URL |
| `ctrl` | 3802 | `~/.claude/projects` (ro) | Monitoring visualization |
| `cron` | — | `/queue` | Writes sweep triggers |

The TPM container: `restart: unless-stopped`, runs `claude --remote-control --dangerously-skip-permissions --agent .claude/agents/tpm-agent.md`.

### Agent Container Dockerfile

Needs: Node.js runtime, Claude Code CLI, `gh` CLI, `git`, `jq`, entrypoint script that starts claude and captures session URL.

### Session URL Capture

TPM's entrypoint:
1. Starts `claude --remote-control --dangerously-skip-permissions`
2. Pipes all stdout to a log file AND parses for the session URL
3. Writes URL to `/sessions/tpm-url.txt`
4. If parsing breaks, raw log is preserved for debugging
5. Dashboard watches `/sessions/` and serves current URLs

### Volume Mounts

```yaml
volumes:
  - ~/.claude/auth:/home/agent/.claude/auth:ro          # Claude auth
  - ~/.config/gh:/home/agent/.config/gh:ro              # GitHub CLI auth
  - ~/.claude/projects:/home/agent/.claude/projects:rw  # Session logs (for Ctrl)
  - ../queue:/data/queue                                # Webhook queue
  - ../logs:/data/logs                                  # Agent activity logs
  - ../sessions:/data/sessions                          # Session URL for dashboard
  - ../.claude:/home/agent/work/.claude:ro              # Agent definitions (read-only)
```

Note: paths use `../` because `docker-compose.yml` lives in `docker/`, one level below the repo root.

---

## Monitoring (Bulletproof Ctrl)

Real-time pixel art visualization of agent activity. Watches JSONL session transcripts that Claude Code writes to `~/.claude/projects/`. Auto-detects sessions — no per-agent config needed.

### Container Setup

```dockerfile
# Bun is a runtime dependency
RUN curl -fsSL https://bun.sh/install | bash
RUN npm install -g @bulletproof-sh/ctrl-daemon@latest
```

### Runtime Flags

```
--port 3802 --host 0.0.0.0 --no-tui --no-open --hooks --share
```

- `--no-tui --no-open` — headless Docker mode
- `--hooks` — Claude Code HTTP hooks integration for richer event data
- `--share` — encrypted relay sharing so user can view from phone (AES-GCM E2E)

### Key Capabilities

- Session inspector: real-time conversations, tool calls, code output
- Token and cost tracking per agent, per turn, per session
- Relay sharing: encrypted link or QR code, viewable from any browser
- **Read-only** — cannot send commands to agents

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `CTRL_HOST` | Bind address |
| `CTRL_NO_OPEN=1` | Don't auto-open browser |
| `CTRL_SHARE=1` | Enable relay sharing |
| `CTRL_RELAY_URL` | Custom relay server URL |
| `CTRL_VERBOSE=1` | Debug logging |

---

## Logging

### Shared Daily Log

Path: `/data/logs/<org-name>/YYYY-MM-DD.md` (maps to `./logs/` on host)

- TPM and all subagents write to the same file per org per day
- Prefixed: `[TPM]`, `[SWE-1]`, `[QA]`, etc.
- Verbose: documents every `gh` command and its result

### Format

```
[2026-04-04 14:30:00] [TPM] Sweep started for herzog-org
[2026-04-04 14:30:02] [TPM] gh repo list herzog-org --limit 1000
[2026-04-04 14:30:03] [TPM] Found 2 repos: repo-a, repo-b
[2026-04-04 14:30:05] [TPM] Spawning SWE-1 for dependabot alert in herzog-org/repo-a
[2026-04-04 14:35:00] [SWE-1] Assigned: fix dependabot alert in herzog-org/repo-a
[2026-04-04 14:35:02] [SWE-1] git checkout -b fix/swe-1/lodash-4.17.21
[2026-04-04 14:45:00] [TPM] SWE-1 completed. PR #43 opened. Spawning QA.
[2026-04-04 14:50:00] [QA] Reviewing PR #43 in herzog-org/repo-a
[2026-04-04 14:50:15] [QA] Tests passed. Approving and merging (agent PR).
[2026-04-04 14:50:20] [TPM] QA approved and merged PR #43. Moving card to Done.
```

---

## First-Run Bootstrap

On initial startup, TPM should:

1. **GitHub CLI auth** — verify `gh auth status`. If not authenticated, run `gh auth login` interactively via remote-control. Required scopes: `repo`, `read:org`, `project`. On fresh machines, user must run `gh auth login` on host first.
2. **Claude auth** — verify mounted `~/.claude/auth` credentials are valid.
3. **Discover board columns** — query each org's project board. Expected columns: Backlog, Ready, In progress, In review, Done.
4. **Sync existing items** — pull all open issues/PRs across all org repos, add untracked items to board (in Backlog), mark closed items Done.
5. **Verify org access** — confirm `gh repo list <org>` works for each configured org.
6. **Log the bootstrap** — record everything in the daily log.

---

## Organization Config

Single source: `.claude/config/organizations.yml`

```yaml
organizations:
  - name: org-name
    project_number: 1
    project_url: https://github.com/orgs/org-name/projects/1
    webhook_secret: ${ORG_WEBHOOK_SECRET}
```

- TPM reads from this file at startup and during sweeps — org names are never hardcoded elsewhere
- Add/remove orgs by editing this one file
- Each org has its own GitHub Projects kanban board
- Agents discover repos dynamically: `gh repo list <org>`
- Webhook secrets reference env vars from `.env`

---

## Directory Structure

```
<repo-root>/
├── CLAUDE.md                              # This file
├── README.md                              # Setup guide for users
├── CHANGELOG.md                           # All changes documented
├── .gitignore
├── .claude/
│   ├── config/
│   │   └── organizations.yml              # Org definitions (single source of truth)
│   └── agents/
│       ├── tpm-agent.md                   # TPM agent definition (orchestrator)
│       ├── swe-agent.md                   # SWE subagent definition
│       └── qa-agent.md                    # QA subagent definition
├── docker/
│   ├── docker-compose.yml
│   ├── .env.example                       # Webhook secrets, SWE_AGENT_COUNT
│   ├── agent/
│   │   ├── Dockerfile                     # Claude CLI + gh + git + jq
│   │   ├── entrypoint.sh                  # Starts claude, captures session URL
│   │   └── .dockerignore
│   ├── webhook-listener/
│   │   ├── Dockerfile
│   │   ├── server.js                      # Receives GitHub webhooks, writes to queue
│   │   ├── package.json
│   │   └── .dockerignore
│   ├── dashboard/
│   │   ├── Dockerfile
│   │   ├── server.js                      # Watches /sessions/, serves URLs
│   │   ├── index.html                     # Simple page with session links
│   │   └── .dockerignore
│   ├── ctrl/
│   │   └── Dockerfile                     # Bun + ctrl-daemon
│   └── cron/
│       └── sweep.sh                       # Triggers TPM sweep
├── queue/
│   ├── incoming/
│   ├── processing/
│   ├── done/
│   └── failed/
├── sessions/                              # TPM session URL
├── logs/                                  # Agent activity logs
└── start.sh                               # Runs docker compose up
```

---

## Hard Rules

These are non-negotiable and must be enforced in all agent definitions and application code:

1. **NO DELETIONS** — cannot delete repos, branches, issues, PRs, board items, or anything else. Close/archive only.
2. **NO REPO SETTINGS CHANGES** — cannot modify branch protection, enable/disable Dependabot, etc. Can request a human to do so.
3. **NO CREATING NEW REPOS** — monitor and maintain existing repos only.
4. **PR MERGE RULES** — agent PRs (branch matches `fix/swe-<N>/...` or `feat/swe-<N>/...`) → QA can merge. Human PRs → QA reviews but does NOT merge.
5. **SINGLE GITHUB ACCOUNT** — all agents share the host user's `gh` auth. Differentiated by naming conventions in branches, PR titles, and log entries.
6. **ORG CONFIG IS THE SOURCE OF TRUTH** — never hardcode org names. Always read from `organizations.yml`.

---

## Key Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Agent architecture | TPM orchestrator + ephemeral SWE/QA subagents | No idle containers, no polling, direct delegation |
| Subagent concurrency | Max N SWE (default 3), 1 QA at a time | Controlled via `SWE_AGENT_COUNT`, avoids merge conflicts |
| Model routing | Sonnet (low/med), Opus (high) | Cost efficiency |
| Multi-org | Single team, orgs via config | Simpler than duplicating agents per org |
| Events | Webhooks + 30-min cron | Real-time + safety net |
| Queue | File-based JSON on disk | Simple, inspectable, survives restarts |
| Remote access | `claude --remote-control` via dashboard | Control from phone |
| Monitoring | Bulletproof Ctrl | Real-time pixel art visualization, read-only |
| Persistence | Docker `restart: unless-stopped` | Survives host restarts |
| Auth | Mount host `~/.claude` + `~/.config/gh` | Single login, shared credentials |
| Logging | Shared daily log per org, verbose, role-prefixed | Full audit trail |
| Kanban columns | Backlog → Ready → In progress → In review → Done | Matches actual GitHub Projects board layout |
| Board cleanup | Auto-archive Done items after 7 days | Keeps board clean, archived items still searchable |
