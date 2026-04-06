# Project Sardaukar

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
- **Configurable concurrency** — `SWE_AGENT_COUNT` environment variable controls max concurrent SWE subagents (default: 3).

---

## Architecture

TPM runs as a `claude remote-control` session on the host. It spawns SWE and QA subagents via the Agent tool. All communication flows through GitHub. Connect from your phone via [claude.ai/code](https://claude.ai/code).

```
Host Machine
├── claude remote-control                          ← TPM (orchestrator, agent loaded via settings)
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
- Manages kanban board state across all orgs: Backlog → Ready → In progress → In review → Done
- Auto-archives Done items older than 7 days on request (archived cards are still searchable via `is:archived`)
- Handles subagent results: chains SWE → QA → Done, or escalates to human
- Provides standup-style summary when user connects
- Can create new issues
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
TPM receives work (human command)
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

| Column | When to use |
|--------|------------|
| **Backlog** | New issue triaged but not yet prioritized |
| **Ready** | Prioritized, next in line for an SWE subagent |
| **In progress** | SWE subagent actively working |
| **In review** | PR opened, QA subagent reviewing |
| **Done** | QA approved and merged, or work completed |

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

## Directory Structure

```
<repo-root>/
├── CLAUDE.md                              # This file
├── README.md                              # Setup guide
├── CHANGELOG.md                           # All changes documented
├── .gitignore
├── .claude/
│   ├── config/
│   │   └── organizations.yml              # Org definitions (single source of truth)
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
4. **PR MERGE RULES** — agent PRs (branch matches `fix/swe-<N>/...` or `feat/swe-<N>/...`) → QA can merge. Human PRs → QA reviews but does NOT merge.
5. **SINGLE GITHUB ACCOUNT** — all agents share the host user's `gh` auth. Differentiated by naming conventions in branches, PR titles, and log entries.
6. **ORG CONFIG IS THE SOURCE OF TRUTH** — never hardcode org names. Always read from `organizations.yml`.

---

## Key Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Agent architecture | TPM orchestrator + ephemeral SWE/QA subagents | Direct delegation, human-driven |
| Subagent concurrency | Max N SWE (default 3), 1 QA at a time | Controlled via `SWE_AGENT_COUNT`, avoids merge conflicts |
| Model routing | Sonnet (low/med), Opus (high) | Cost efficiency |
| Multi-org | Single team, orgs via config | Simpler than duplicating agents per org |
| Remote access | `claude remote-control` | Connect from phone via Claude app |
| Auth | Host `gh` + Claude OAuth | Single login, shared credentials |
| Logging | Shared daily log per org, verbose, role-prefixed | Full audit trail |
| Kanban columns | Backlog → Ready → In progress → In review → Done | Matches actual GitHub Projects board |
| Board cleanup | Auto-archive Done items after 7 days | Keeps board clean, archived items still searchable |
