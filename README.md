![Project Sardaukar](https://immich.lxrbckl.com/api/assets/c9834643-3ad1-41fd-bea2-d27393fe43eb/thumbnail?slug=projectSardaukar&size=preview&c=UfcJDIKHeJd%2Fh4aOdnX4fXL%2FWA%3D%3D&edited=true)

An always-on, self-hosted AI agent platform that acts as a fully autonomous DevOps team for managing multiple GitHub organizations. Handles issue triage, PR management, vulnerability remediation, and kanban board tracking through a team of specialized Claude Code agents.

For the full technical specification and design decisions, see [CLAUDE.md](CLAUDE.md).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Setup](#setup)
  - [Organization Config](#1-organization-config)
  - [Authentication](#2-authentication)
  - [Start](#3-start)
- [Architecture](#architecture)
- [Agents](#agents)

---

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed and authenticated (`claude auth login`)
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- A Claude Max, Pro, or Team subscription (for `remote-control`)

---

## Setup

### 1. Organization Config

Edit `.claude/config/organizations.yml` to list the GitHub orgs you want to manage:

```yaml
organizations:
  - name: your-org-1
    project_number: 1
    project_url: https://github.com/orgs/your-org-1/projects/1
  - name: your-org-2
    project_number: 1
    project_url: https://github.com/orgs/your-org-2/projects/1
```

Each org should have a GitHub Projects kanban board with columns: Backlog, Ready, In progress, In review, Done.

### 2. Authentication

Ensure both CLI tools are authenticated on your host machine:

```bash
# Claude Code — required for remote-control and subagent spawning
claude auth login

# GitHub CLI — agents need this to interact with repos, issues, PRs, and boards
gh auth login
gh auth status  # verify scopes: repo, read:org, project
```

### 3. Start

From the project root:

```bash
claude remote-control --dangerously-skip-permissions --agent .claude/agents/tpm-agent.md
```

TPM will execute its Startup Sequence (verify auth, read org config, sync boards) then wait for your commands or run periodic sweeps. Connect to it from your phone via the Claude app using the session URL displayed in the terminal.

---

## Architecture

```
Host Machine
├── claude remote-control --agent tpm-agent.md     ← TPM (orchestrator)
│   ├── spawns SWE subagents (ephemeral)           ← code work
│   └── spawns QA subagents (ephemeral)            ← PR review
└── GitHub (source of truth)
    ├── Issues, PRs, Dependabot alerts
    └── Kanban boards per org (Backlog → Ready → In progress → In review → Done)
```

TPM receives work two ways:
1. **You tell it** — connect from phone or CLI and give it commands
2. **Periodic sweep** — TPM scans all orgs for new issues, PRs, alerts every 30 minutes

---

## Agents

### TPM (orchestrator)

Your single point of contact. Scans orgs for work, triages issues, manages kanban boards, spawns SWE/QA subagents, and provides status summaries when you connect. Does not write code.

### SWE subagents (ephemeral, up to N concurrent)

Spawned by TPM when code work is needed. Create branches, write code, run tests, open PRs, and return results to TPM. Each gets a unique identity (SWE-1, SWE-2, etc.) assigned at spawn time. Max concurrency controlled by `SWE_AGENT_COUNT` (default: 3).

### QA subagent (ephemeral, 1 at a time)

Spawned by TPM when a PR is ready for review. Reviews code, runs tests, approves/merges agent PRs, and returns results to TPM. For human-created PRs, reviews and comments but never merges.
