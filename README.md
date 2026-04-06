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
- [Monitoring (Ctrl)](#4-monitoring-ctrl-optional)
  - [Auto-Start on Boot](#5-auto-start-on-boot-macos-launchagent)
- [Architecture](#architecture)
- [Agents](#agents)

---

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed and authenticated (`claude auth login`)
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- A Claude Max, Pro, or Team subscription (for `remote-control`)
- Playwright plugin: `claude plugin install playwright@claude-plugins-official`
- Firecrawl plugin: `claude plugin install firecrawl@claude-plugins-official`
- Firecrawl CLI: `npm install -g firecrawl-cli` then `firecrawl login --browser`

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
claude remote-control --permission-mode bypassPermissions
```

Then connect from your phone at [claude.ai/code](https://claude.ai/code). CLAUDE.md instructs TPM to boot automatically. Just say "go" or any message to trigger the Startup Sequence.

If TPM doesn't boot automatically, send:

```
Read .claude/agents/tpm-agent.md and execute your Startup Sequence.
```

After that, just talk naturally — "check for vulnerabilities", "fix issue #5", "what's the status?"

### 4. Monitoring (Ctrl) — optional

[Bulletproof Ctrl](https://ctrl.bulletproof.sh) visualizes all agent activity as animated pixel art characters in a virtual office. Run it in a separate terminal:

```bash
npx @bulletproof-sh/ctrl-daemon@latest --port 3871 --share
```

- Auto-detects Claude Code sessions by watching `~/.claude/projects/`
- `--share` generates an encrypted relay link you can view from your phone
- Read-only — cannot send commands to agents

To expose Ctrl via a subdomain, add to your Caddyfile:

```
ctrl.your-domain.com {
    basic_auth {
        <username> <hashed-password>
    }
    reverse_proxy localhost:3871
}
```

Then run Ctrl bound to all interfaces:

```bash
npx @bulletproof-sh/ctrl-daemon@latest --port 3871 --host 0.0.0.0 --no-open
```

### 5. Auto-Start on Boot (macOS LaunchAgent)

To have TPM and Ctrl start automatically on login, run the setup script from the project root:

```bash
./setup-launchagents.sh
```

This detects your local paths, generates the plist files, installs them, and starts both services immediately. They will restart on crash and start on every login.

To stop:
```bash
launchctl unload ~/Library/LaunchAgents/com.sardaukar.tpm.plist
launchctl unload ~/Library/LaunchAgents/com.sardaukar.ctrl.plist
```

Logs are at `logs/tpm-launch.log` and `logs/ctrl-launch.log`.

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
