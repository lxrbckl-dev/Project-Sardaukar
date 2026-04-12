![Project Sardaukar](https://immich.lxrbckl.com/api/assets/c9834643-3ad1-41fd-bea2-d27393fe43eb/thumbnail?slug=projectSardaukar&size=preview&c=UfcJDIKHeJd%2Fh4aOdnX4fXL%2FWA%3D%3D&edited=true)

An always-on, self-hosted AI agent platform that acts as a fully autonomous DevOps team for managing multiple GitHub organizations. Handles issue triage, PR management, vulnerability remediation, and kanban board tracking through a team of specialized Claude Code agents.

For the full technical specification and design decisions, see [CLAUDE.md](CLAUDE.md).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Setup](#setup)
  - [Clone and Enter](#0-clone-and-enter)
  - [Organization Config](#1-organization-config)
  - [Authentication](#2-authentication)
  - [One-Time Interactive Acceptance](#2a-one-time-interactive-acceptance)
  - [Start](#3-start)
  - [Connect](#4-connect)
- [Architecture](#architecture)
- [Agents](#agents)

---

## Prerequisites

Runs on any Unix-like system (macOS, Linux, WSL).

- [Claude Code CLI](https://claude.ai/code) installed and authenticated (`claude auth login`)
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- A Claude Max, Pro, or Team subscription (for `remote-control`)
- Playwright plugin: `claude plugin install playwright@claude-plugins-official`
- (Optional, for SSH tasks) `sshpass` installed:
  - macOS: `brew install hudochenkov/sshpass/sshpass`
  - Debian/Ubuntu: `sudo apt install sshpass`
  - Fedora/RHEL: `sudo dnf install sshpass`
  - Arch: `sudo pacman -S sshpass`

---

## Setup

### 0. Clone and Enter

```bash
git clone https://github.com/lxrbckl-dev/Project-Sardaukar.git
cd Project-Sardaukar
```

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
gh auth refresh -s project  # adds the 'project' scope needed for kanban boards
```

### 2a. One-Time Interactive Acceptance

Claude has two interactive prompts that must be accepted once before TPM can run. Run these from the project root:

```bash
# 1. Accept the workspace trust dialog (saved to ~/.claude.json)
claude
# Press 'y' or Enter to trust this workspace, then /exit

# 2. Accept the Remote Control opt-in (saved to ~/.claude/)
claude remote-control --permission-mode bypassPermissions
# Type 'y' when prompted, then Ctrl+C to stop
```

These only need to be done once per machine.

### 3. Start

From the project root, run the wrapper script:

```bash
./start-tpm.sh
```

This starts `claude remote-control` with the version-tagged session name. Leave the terminal running — closing it stops TPM.

Or run the command directly:

```bash
claude remote-control --permission-mode bypassPermissions
```

### 4. Connect

Once TPM is running, connect from your phone at [claude.ai/code](https://claude.ai/code). Your session should appear in the list automatically.

The session URL is also printed in the terminal where TPM is running.

CLAUDE.md instructs TPM to boot automatically. Just say "go" or any message to trigger the Startup Sequence.

If TPM doesn't boot automatically, send:

```
Read .claude/agents/tpm-agent.md and execute your Startup Sequence.
```

After that, just talk naturally — "check for vulnerabilities", "fix issue #5", "what's the status?"

---

## Architecture

```
Host Machine
├── claude remote-control                          ← TPM (orchestrator, agent loaded via CLAUDE.md)
│   ├── spawns SWE subagents (ephemeral)           ← code work
│   └── spawns QA subagents (ephemeral)            ← PR review
└── GitHub (source of truth)
    ├── Issues, PRs, Dependabot alerts
    └── Kanban boards per org (Backlog → Ready → In progress → In review → Done)
```

You connect from your phone or CLI and tell TPM what to do. It executes using `gh` commands and by spawning SWE/QA subagents.

---

## Agents

### TPM (orchestrator)

Your single point of contact. Triages issues, manages kanban boards, spawns SWE/QA subagents, and provides status summaries. You tell it what to do — it handles the rest. Does not write code.

### SWE subagents (ephemeral, up to N concurrent)

Spawned by TPM when code work is needed. Create branches, write code, run tests, open PRs, and return results to TPM. Can browse the web, read documentation, scrape sites, interact with UIs via Playwright, and take/read screenshots. Each gets a unique identity (SWE-1, SWE-2, etc.) assigned at spawn time. Max concurrency controlled by `SWE_AGENT_COUNT` (default: 3).

### QA subagent (ephemeral, 1 at a time)

Spawned by TPM when a PR is ready for review. Reviews code, runs tests, approves/merges agent PRs, and returns results to TPM. For human-created PRs, reviews and comments but never merges.
