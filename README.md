# Project Sardaukar

An always-on, self-hosted AI agent platform that acts as a fully autonomous DevOps team for managing multiple GitHub organizations. Runs on Docker and handles issue triage, PR management, vulnerability remediation, and kanban board tracking through a team of specialized Claude Code agents.

For the full technical specification and design decisions, see [CLAUDE.md](CLAUDE.md).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Setup](#setup)
  - [Subdomain Configuration](#1-subdomain-configuration)
  - [Reverse Proxy](#2-reverse-proxy-caddy-example)
  - [GitHub Webhook Configuration](#3-github-webhook-configuration)
  - [Organization Config](#4-organization-config)
  - [Host Authentication](#5-host-authentication)
  - [Start](#6-start)
- [Architecture Overview](#architecture-overview)
- [Containers](#containers)
  - [Agent Container](#agent-container)
  - [Infrastructure Containers](#infrastructure-containers)

---

## Prerequisites

- Docker and Docker Compose
- A domain with DNS access (for creating subdomains)
- A reverse proxy (Caddy recommended, but any will work)
- GitHub CLI (`gh`) authenticated on the host machine
- An active Claude Code session on the host (for `~/.claude` auth)

---

## Setup

### 1. Subdomain Configuration

The platform requires **two subdomains** pointed at your server. Replace `your-domain.com` with your actual domain.

| Subdomain | Purpose | Proxies To |
|-----------|---------|------------|
| `webhooks.your-domain.com` | Receives GitHub webhook events | `localhost:3800` |
| `agents.your-domain.com` | Password-protected dashboard for remote-controlling agents from your phone | `localhost:3801` |

Create DNS A (or CNAME) records for both subdomains pointing to your server's IP.

### 2. Reverse Proxy (Caddy Example)

Add these blocks to your Caddyfile. If you're using a different reverse proxy (nginx, Traefik, etc.), configure the equivalent routes.

```
# GitHub webhook listener — no auth needed (validated by webhook signature)
webhooks.your-domain.com {
  reverse_proxy localhost:3800
}

# Agent dashboard — protected so only you can access remote-control sessions
agents.your-domain.com {
  basic_auth {
    <username> <hashed-password>
  }
  reverse_proxy localhost:3801
}
```

To generate a hashed password for Caddy:

```bash
caddy hash-password --plaintext 'your-password'
```

### 3. GitHub Webhook Configuration

Each GitHub organization you want to manage needs a webhook pointing to your listener. Repeat this for every org listed in your `organizations.yml`.

1. Go to `https://github.com/organizations/<your-org>/settings/hooks`
2. Click **Add webhook**
3. Configure:

| Field | Value |
|-------|-------|
| **Payload URL** | `https://webhooks.your-domain.com/hooks/github` |
| **Content type** | `application/json` |
| **Secret** | A strong random string — must match the corresponding entry in `.claude/config/organizations.yml` |
| **Which events?** | "Send me everything" or select: Issues, Pull requests, Dependabot alerts, Push, Repository, Issue comments, Projects v2 |

The webhook listener uses the `organization.login` field in each payload to identify which org sent the event, and validates the signature against the matching per-org secret from `organizations.yml`. All orgs share the same endpoint — no separate URLs needed.

### 4. Organization Config

Edit `.claude/config/organizations.yml` to list your orgs. The webhook secrets here must match what you entered in GitHub.

```yaml
organizations:
  - name: your-org-1
    project_number: 1
    project_url: https://github.com/orgs/your-org-1/projects/1
    webhook_secret: ${ORG1_WEBHOOK_SECRET}
  - name: your-org-2
    project_number: 1
    project_url: https://github.com/orgs/your-org-2/projects/1
    webhook_secret: ${ORG2_WEBHOOK_SECRET}
```

Set the actual secrets in your `.env` file (see `.env.example`).

### 5. Host Authentication

On the host machine (or any new machine), ensure both CLI tools are authenticated before starting containers:

```bash
# GitHub CLI — agents need this to interact with repos, issues, PRs, and boards
gh auth login
gh auth status  # verify scopes: repo, read:org, project

# Claude Code — agents need this for the Claude API
claude  # start a session to ensure ~/.claude/auth is populated
```

These credentials are mounted read-only into the agent containers.

### 6. Start

```bash
cp docker/.env.example docker/.env
# Edit docker/.env — set webhook secrets, SWE_AGENT_COUNT (default: 3), etc.

./start.sh
```

---

## Architecture Overview

```
Your Server
├── docker-compose
│   ├── tpm-agent              — Orchestrator (spawns SWE/QA subagents on demand)
│   ├── webhook-listener       — Receives GitHub events, writes to file queue
│   ├── dashboard              — Serves TPM's session URL
│   ├── ctrl                   — Bulletproof Ctrl monitoring
│   └── cron                   — Triggers periodic TPM sweeps
├── Reverse proxy (Caddy/nginx/etc.)
│   ├── webhooks.your-domain.com → webhook-listener
│   └── agents.your-domain.com   → dashboard
└── Shared volumes
    ├── /queue      — Webhook event queue
    ├── /sessions   — TPM remote-control URL
    ├── /logs       — Agent activity logs
    └── ~/.claude   — Auth (ro) + session logs (rw)
```

---

## Containers

### Agent Container

| Container | Description |
|-----------|-------------|
| `tpm-agent` | **Technical Program Manager.** The orchestrator and your primary point of contact. Runs Claude Code CLI with `--remote-control --dangerously-skip-permissions` and exposes a session URL you can connect to from the Claude app on your phone. Consumes the webhook event queue, triages incoming issues, manages kanban boards across all orgs, and provides status summaries when you connect. Does not write code — instead, it spawns **SWE** and **QA subagents** on demand using Claude's Agent tool. |

**SWE subagents** (ephemeral, up to N concurrent — default 3 via `SWE_AGENT_COUNT` in `.env`): Spawned by TPM when code work is needed. Create branches, write code, run tests, open PRs, and return results to TPM. Each gets a unique identity (SWE-1, SWE-2, etc.) assigned by TPM at spawn time.

**QA subagent** (ephemeral, 1 at a time): Spawned by TPM when a PR is ready for review. Reviews code, runs tests, approves/merges agent PRs, and returns results to TPM. For human-created PRs, reviews and comments but never merges.

### Infrastructure Containers

| Container | Port | Description |
|-----------|------|-------------|
| `webhook-listener` | 3800 | **Node.js service** that receives GitHub webhook events at `/hooks/github`. Validates signatures per-org using secrets from `organizations.yml`, then writes JSON envelopes to the file-based queue at `/queue/incoming/`. All orgs share this single endpoint — the listener differentiates them using the `organization.login` field in each payload. |
| `dashboard` | 3801 | **Minimal web page** that displays the TPM's remote-control session URL. Access it from your phone at `agents.your-domain.com` (password-protected) to connect to TPM via the Claude app. TPM is your single point of contact — it delegates everything else. |
| `ctrl` | 3802 | **[Bulletproof Ctrl](https://ctrl.bulletproof.sh) monitoring daemon.** Renders agent activity as animated pixel art characters in a virtual office with live tool activity indicators. Watches Claude Code's JSONL session transcripts. Supports encrypted relay sharing so you can watch from your phone without VPN. Read-only — cannot send commands to agents. |
| `cron` | — | **Lightweight scheduler** that triggers TPM's sweep every 30 minutes (configurable to 15). Acts as a safety net alongside webhooks to catch any events that were missed. |
