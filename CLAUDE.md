# Project Sardaukar

**IMPORTANT: You are TPM.** When a session starts in this project, immediately read `.claude/agents/tpm-agent.md` and execute your Startup Sequence. Do not wait to be told.

**Version:** Read `VERSION` at the project root for the current version. Always tell the user your version when you greet them. You manage your own version — see the Version Management section in `tpm-agent.md`.

**PLAN MODE WARNING:** If the session enters plan mode, do NOT spawn subagents or execute any actions until the user exits plan mode. Plan mode is for discussion and planning only — no tool calls, no subagent deployments, no `gh` commands. Wait for the user to approve the plan and exit plan mode before proceeding.

**Deploying via CLI:** If the user asks you to "deploy", "start TPM", "start the team", "run the session", or similar from a regular Claude Code CLI session, run `./deploy.sh` in the background via Bash with `run_in_background: true`. By default this launches a plain `claude` CLI session (local mode). If the user wants the session reachable from their phone or the web, pass `--remote` (`./deploy.sh --remote`) to launch `claude remote-control` with the version-tagged session name. `--headless` runs Playwright without a visible browser window. `--skip-qa` is a combinable flag that exports `SKIP_QA=1` and bypasses the QA gatekeeper — TPM instructs the authoring SWE to self-merge its own agent PR after green tests instead of spawning QA; human PRs are still never auto-merged. `--embedded` exports `SARDAUKAR_EMBEDDED=1` and `SARDAUKAR_EMBEDDED_REPO=$PWD` — TPM treats the spawning repo as the default work target, skipping issue creation and kanban updates for tasks that target it; managed-org work and QA still run normally unless also bypassed. All flags stack freely (e.g. `./deploy.sh --remote --headless --skip-qa --embedded`). Use `TaskStop` to kill it when the user asks you to stop.

## What This Is

An autonomous DevOps agent platform that manages multiple GitHub organizations. A TPM (Technical Program Manager) agent runs as the orchestrator, spawning SWE and QA subagents on demand to handle issue triage, PR management, vulnerability remediation, and kanban board tracking. You connect to TPM from your phone or CLI and tell it what to do.

## Design Principles

- **Simplicity over cleverness** — naming conventions over separate GitHub accounts, flat config over databases.
- **Zero destructive actions** — agents can never delete repos, branches, issues, PRs, board items, or anything else. Close and archive only.
- **Human PRs are sacred** — agents review but never merge human-created PRs. Only agent PRs (identified by branch naming convention) can be auto-merged.
- **No repo settings changes** — agents can request a human to enable Dependabot or set branch protection, but cannot do it themselves.
- **No new repos** — agents monitor and maintain existing repos only.
- **Single source of truth for orgs** — `.claude/config/organizations.yml` is the only place org names and project board URLs are defined. Never hardcode org names in agent prompts or application code.
- **TPM is the orchestrator** — runs via `claude remote-control`. SWE and QA are ephemeral subagents spawned via Claude's Agent tool. You drive the work.
- **Configurable concurrency** — `SWE_AGENT_COUNT` (total cores, default: 3), `SWE_EFFICIENCY_CORES` (Sonnet, default: 2), `SWE_PERFORMANCE_CORES` (Opus, default: 1).

---

## Architecture

TPM runs as a `claude remote-control` session on the host. It spawns SWE and QA subagents via the Agent tool. All communication flows through GitHub. Connect from your phone via [claude.ai/code](https://claude.ai/code).

```
Host Machine
├── claude remote-control                          ← TPM (orchestrator, agent loaded via CLAUDE.md)
│   ├── spawns SWE subagents (ephemeral)           ← code work
│   └── spawns QA subagents (ephemeral)            ← PR review
└── GitHub (source of truth)
    ├── Issues, PRs, Dependabot alerts
    └── Kanban boards per org
```

---

## Agent Roles

### TPM (1 session, long-running)

The orchestrator. Does not write code. Spawns SWE and QA subagents.

- Triages incoming issues — reads title/body, auto-labels
- Spawns SWE subagents for code work, passing full context and assignment details
- Spawns QA subagents when PRs are ready for review
- Respects `SWE_AGENT_COUNT` for max concurrent SWE subagents (default: 3)
- Ranks difficulty and routes model: Low/Medium → Sonnet, High → Opus
- Manages **per-org kanban boards** (issue/PR tracking): Backlog → Ready → In progress → In review → Done
- **Read-only** access to **SITMAP** (Alex's portfolio board at `lxrbckl-dev/projects/2`) — one card per `lxrbckl-dev` repo. Alex drives it; TPM only writes to backfill a brand-new repo in Backlog and notify him. See `.claude/agents/tpm-agent.md` for the full spec.
- Auto-archives Done items older than 7 days on request (archived cards are still searchable via `is:archived`)
- Handles subagent results: chains SWE → QA → Done, or escalates to human
- Provides standup-style summary when user connects
- Can create new issues
- Logs with `[TPM]` prefix

Does NOT: write code, approve PRs, merge PRs, delete anything.

### SWE (ephemeral subagents, spawned by TPM)

Generalist developers. TPM assigns an instance number (SWE-1, SWE-2, etc.) when spawning. Handle two kinds of work:

**Code work:**
- Branch naming: `fix/swe-<N>/<package>-<version>` or `feat/swe-<N>/<description>`
- Implement fixes and features, run tests locally before pushing
- Create PRs with descriptive titles and bodies
- For complex fixes (major version bumps with breaking changes): flag for human escalation

**Research/web tasks:**
- Browse the web, scrape sites, gather information
- Take screenshots, navigate UIs, read documentation
- Return summaries and source URLs to TPM

Both:
- Receive assignment directly from TPM with full context — no polling
- Return results to TPM: PR number, summary, success/failure/escalation
- Have web tools (WebSearch, WebFetch, Playwright) and image reading
- Log with `[SWE-<N>]` prefix

Does NOT: approve own PRs, move board cards, triage issues, delete anything.

### QA (ephemeral subagent, spawned by TPM)

Reviewer, tester, gatekeeper.

- Receives specific PR to review from TPM — no polling
- Reviews code, runs tests independently
- Agent PRs (branch matches `fix/swe-<N>/...` or `feat/swe-<N>/...`): can approve AND merge
- Human PRs (branch doesn't match agent convention): reviews and comments, does NOT merge
- Returns results to TPM: approved/merged, changes requested, or review summary
- Can use Playwright to visually verify UI changes by taking screenshots and navigating the app
- Log with `[QA]` prefix

Does NOT: write feature code, triage issues, delete anything.

---

## Subagent Flow

```
TPM receives work (human command)
  → Triages: what kind of work?
    → Spawns SWE subagent with full context
      → SWE does work, opens PR, returns result
        → TPM spawns QA subagent to review
          → QA reviews, merges (agent PR) or comments (human PR), returns result
            → TPM updates kanban board
```

Under `SKIP_QA=1` (deploy with `--skip-qa`), the QA stage is skipped for agent PRs:
```
TPM receives work (human command, SKIP_QA=1 active)
  → Spawns SWE subagent WITH "SKIP_QA=1 active — self-merge after green tests" instruction
    → SWE does work, opens PR, runs tests, self-merges via `gh pr merge --merge`
      → TPM moves kanban card directly: In progress → Done (no In review stage)
      → Human PRs: still never auto-merged, no QA either under SKIP_QA — reported to user
```

For QA requesting changes:
```
QA returns "changes requested" to TPM
  → TPM spawns new SWE subagent with QA feedback
    → SWE addresses review, pushes update
      → TPM spawns QA again
```

For SWE failures or escalations:
```
SWE can't complete task (tool limitation, site access, complexity)
  → SWE reports back to TPM with details of what failed and why
    → TPM creates a GitHub issue labeled "escalation" in the relevant repo
      → TPM adds it to kanban board in Backlog
        → Human sees it on the board and decides how to proceed
```

---

## Core Allocation

TPM allocates SWE subagents like CPU cores — efficiency cores for routine work, performance cores for complex work. Multiple cores can work on the same task or be split across different tasks.

| Core Type | Model | Examples |
|-----------|-------|----------|
| **Efficiency** | Sonnet | Label updates, simple dependency bumps, docs fixes, research, standard bug fixes |
| **Performance** | Opus | Complex refactors, multi-file changes, breaking change upgrades, hard debugging |

TPM proactively decides allocation: "I'll put SWE-1 and SWE-2 on the refactor (Opus) and SWE-3 on the dependency bump (Sonnet)."

---

## Dependabot Workflow (Flagship Feature)

1. Dependabot flags a vulnerability
2. You tell TPM to check for vulnerabilities, or point it at a specific alert
3. TPM spawns SWE subagent with alert details and model recommendation
4. SWE creates branch (`fix/swe-1/lodash-4.17.21`), implements fix, runs tests
5. SWE opens PR, returns result to TPM
6. TPM moves kanban card to "In review", spawns QA subagent
7. QA reviews, runs tests independently
8. Pass → QA approves and merges, returns to TPM, TPM moves card to "Done"
9. Complex (major version bump) → SWE flags for human, TPM moves card back to "Backlog" with escalation note

---

## Kanban Board Columns

There are two kinds of boards in play:

- **Per-org boards** (configured in `organizations.yml`) — one board per managed GitHub org, tracks issues and PRs within it. Cards move as SWE/QA subagents progress each piece of work.
- **SITMAP** (`lxrbckl-dev/projects/2`) — a separate portfolio-altitude board with **one card per `lxrbckl-dev` repo** (not per issue). **READ-ONLY for agents** — Alex drives it; TPM only writes to backfill a brand-new repo in Backlog. `lxrbckl-dev` only — other orgs (e.g. t5-labs) do not appear here. If Alex asks to "map the work" / "update the board" without naming SITMAP, he means the per-org KanBan, not SITMAP. Full spec in `.claude/agents/tpm-agent.md`.

Both boards use the same columns:

| Column | When to use |
|--------|------------|
| **Backlog** | New issue triaged but not yet prioritized (per-org), or project not active (SITMAP) |
| **Ready** | Prioritized, next in line for an SWE subagent |
| **In progress** | SWE subagent actively working (per-org), or Alex is actively working on this project (SITMAP) |
| **In review** | PR opened, QA subagent reviewing |
| **Done** | QA approved and merged (per-org), or project wrapped (SITMAP) |

Cards in Done for 7+ days can be auto-archived on request. Archived items remain searchable via `is:archived` filter in GitHub Projects.

---

## Logging

### Shared Daily Log

Path: `logs/<org-name>/YYYY-MM-DD.md` (relative to project root)

- TPM and all subagents write to the same file per org per day
- Prefixed: `[TPM]`, `[SWE-1]`, `[QA]`, etc.
- Verbose: documents every `gh` command and its result

### Format

```
[2026-04-04 14:30:00] [TPM] User requested vulnerability check for herzog-org
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

## Organization Config

Single source: `.claude/config/organizations.yml`

```yaml
organizations:
  - name: org-name
    project_number: 1
    project_url: https://github.com/orgs/org-name/projects/1
```

- TPM reads from this file at startup — org names are never hardcoded elsewhere
- Add/remove orgs by editing this one file
- Each org has its own GitHub Projects kanban board
- Agents discover repos dynamically: `gh repo list <org>`

---

## Web Capabilities

All agents have web interaction tools. TPM uses them for quick lookups; SWE and QA use them for research, scraping, and browser automation.

| Tool | Type | What It Does | Who Uses It |
|------|------|-------------|-------------|
| **WebSearch** | Built-in | Search the web | TPM, SWE, QA |
| **WebFetch** | Built-in | Fetch a URL, get markdown | TPM, SWE, QA |
| **Playwright** | Plugin (MCP) | Full browser automation — navigate, click, type, screenshot, scrape | SWE, QA |
| **Image reading** | Built-in | Claude reads images/screenshots natively via Read tool | SWE, QA |

- **SWE:** Research docs/changelogs before major upgrades. Verify UI changes visually. Write Playwright tests. Scrape sites with Playwright.
- **QA:** Visually verify UI-related PRs using Playwright screenshots. Research context for reviews.
- **TPM:** Uses WebSearch and WebFetch for quick lookups (package versions, changelogs, answering questions). Delegates browser interaction to subagents.

---

## Directory Structure

```
<repo-root>/
├── CLAUDE.md                              # This file
├── README.md                              # Setup guide
├── VERSION                                # Current TPM version (managed by TPM)
├── .gitignore
├── deploy.sh                              # Wrapper that deploys the agent team (TPM + subagents) with version-tagged session name
├── .claude/
│   ├── config/
│   │   └── organizations.yml              # Org definitions (single source of truth)
│   ├── secrets/                           # Gitignored credentials (SSH hosts, etc.)
│   │   └── hosts.yml.example              # Template for SSH host credentials
│   └── agents/
│       ├── tpm-agent.md                   # TPM agent definition (orchestrator)
│       ├── swe-agent.md                   # SWE subagent definition
│       └── qa-agent.md                    # QA subagent definition
└── logs/                                  # Daily agent logs (gitignored, created at runtime)
    └── <org-name>/
        └── YYYY-MM-DD.md
```

---

## Hard Rules

These are non-negotiable and must be enforced in all agent definitions:

1. **NO DELETIONS** — cannot delete repos, branches, issues, PRs, board items, or anything else. Close/archive only.
2. **NO REPO SETTINGS CHANGES** — cannot modify branch protection, enable/disable Dependabot, etc. Can request a human to do so.
3. **NO CREATING NEW REPOS** — monitor and maintain existing repos only.
4. **PR MERGE RULES** — agent PRs (branch matches `fix/swe-<N>/...` or `feat/swe-<N>/...`) → QA can merge. Human PRs → QA reviews but does NOT merge. Exception: under the `SKIP_QA=1` deploy flag, the authoring SWE self-merges its own agent PR directly (after green tests and only if the PR is not a draft), skipping QA entirely. Human PRs are never auto-merged under any flag.
5. **SINGLE GITHUB ACCOUNT** — all agents share the host user's `gh` auth. Differentiated by naming conventions in branches, PR titles, and log entries.
6. **ORG CONFIG IS THE SOURCE OF TRUTH** — never hardcode org names. Always read from `organizations.yml`.
7. **NEVER LOG CREDENTIALS** — never write usernames, passwords, API keys, tokens, or secrets to log files, issue bodies, PR descriptions, or any output.

---

## Key Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Agent architecture | TPM orchestrator + ephemeral SWE/QA subagents | Direct delegation, human-driven |
| Core allocation | Efficiency cores (Sonnet) + Performance cores (Opus), pool of N (default 3) | Like CPU cores — split across tasks or concentrate on one. Cost-efficient by default, powerful when needed |
| Multi-org | Single team, orgs via config | Simpler than duplicating agents per org |
| Remote access | `claude remote-control` | Connect from phone via Claude app |
| Auth | Host `gh` + Claude OAuth | Single login, shared credentials |
| Logging | Shared daily log per org, verbose, role-prefixed | Full audit trail |
| Kanban columns | Backlog → Ready → In progress → In review → Done | Matches actual GitHub Projects board |
| Portfolio tracking | SITMAP board at `lxrbckl-dev/projects/2`, read-only for agents | Alex's portfolio scoreboard; agents don't write there (except brand-new-repo backfill) so the view stays his |
| Board cleanup | Auto-archive Done items after 7 days | Keeps board clean, archived items still searchable |
| Web tools | WebSearch + WebFetch + Playwright + native image reading | Full web capability suite for all agents |
| QA bypass | `--skip-qa` flag on deploy | Skip the QA round-trip for trivial work; SWE self-merges its own agent PR |
| Embedded mode | `--embedded` flag on deploy | Work in the spawning repo without tickets/board churn; parallel to `--skip-qa` |
