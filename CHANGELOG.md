# Changelog

All notable changes to Project Sardaukar are documented in this file.

---

## [Unreleased]

### Added
- Initial project structure and full platform implementation
- Agent definitions: TPM, SWE, QA (`.claude/agents/`)
- Organization config (`.claude/config/organizations.yml`)
- Docker infrastructure: agent Dockerfile, entrypoint script
- Webhook listener: Node.js service with per-org signature validation
- Dashboard: auto-refreshing dark-themed UI for agent session URLs
- Ctrl container: Bulletproof Ctrl with Bun, headless mode, relay sharing
- Cron container: 30-minute sweep trigger via file queue
- `docker-compose.yml` with 5 services (tpm-agent, webhook-listener, dashboard, ctrl, cron)
- `start.sh` startup script
- `CLAUDE.md` as single reference for the full spec
- `README.md` with setup guide, container docs, Caddy config, table of contents
- `CHANGELOG.md`
- `.gitignore` with rules for secrets, runtime data, node_modules, OS files
- `.gitkeep` files to preserve empty directory structure in git

### Fixed (stress test — 10 rounds)

1. **Agent Dockerfile: gh CLI hardcoded to `linux_amd64`** — Mac Mini M-series runs ARM. Changed to multi-arch detection using `uname -m` to select `amd64` or `arm64` at build time.

2. **Cron container: env vars not passed to cron jobs** — Alpine's `crond` does not forward container environment variables. Inlined `QUEUE_DIR=/data/queue/incoming` directly in the crontab entry.

3. **Webhook listener: crashes on GitHub `ping` event** — GitHub sends a `ping` event when a webhook is first configured. This event has no `organization` field, causing a 400 response. Added explicit `ping` handler that returns `pong`.

4. **No `.gitignore`** — `docker/.env` (secrets), `sessions/`, `queue/`, `logs/`, and `node_modules/` had no gitignore rules. Created `.gitignore` with all necessary exclusions and `.gitkeep` files to preserve directory structure.

5. **Webhook listener: adding a new org required editing `docker-compose.yml`** — Each new org's webhook secret env var had to be manually added to the compose `environment` block, violating single-source-of-truth. Changed to `env_file: .env` which passes all env vars automatically.

6. **Webhook listener: `crypto.timingSafeEqual` crashes on malformed signatures** — If a signature has a different byte length than expected, `timingSafeEqual` throws instead of returning false. Added buffer length guard before comparison.

7. **Entrypoint: pipeline swallows claude exit code** — The `tee | while` pipeline meant if `claude` crashed, `set -e` wouldn't catch the non-zero exit. Added `set -eo pipefail` so pipeline failures propagate correctly and trigger container restart.

8. **Queue directory permissions** — Directories created by `start.sh` on the host are owned by the host user, but container processes run as non-root users (`app`, `agent`). Added `chmod -R 777` in `start.sh` for runtime directories.

9. **SWE agents: no workspace for cloning repos** — SWE agents need to clone repositories to work on them, but had no designated workspace. Added `/home/agent/repos/` directory to the agent Dockerfile and updated the SWE agent definition to use it.

10. **Dashboard: no health check** — Webhook listener had a Docker `HEALTHCHECK` but the dashboard did not. Added health check to dashboard Dockerfile.

### Fixed (stress test — rounds 11-20)

11. **QA agent: corrupted unicode character** — Line 108 of `qa-agent.md` had garbled bytes (`���`) instead of an em dash. Replaced with `—`.

12. **Webhook listener: no body size limit** — No cap on request body size. A malicious actor could send a massive payload and exhaust container memory. Added 10MB limit with 413 response on overflow and `req.destroy()` to kill the connection.

13. **Webhook listener: ping event bypasses signature validation** — The `ping` handler returned 200 before any signature check, allowing unauthenticated fake pings. Moved signature validation before ping handling so all events are authenticated first.

14. **Dashboard: XSS vulnerability** — Session names and URLs from `/sessions/` files were injected directly into `innerHTML` without escaping. If a malicious file was written to the sessions volume, it could execute arbitrary JavaScript. Added `esc()` helper using `textContent` for all dynamic values and `rel="noopener"` on links.

15. **Webhook listener: no request timeout** — No timeout on incoming connections. Slow clients (slowloris attack) could hold connections indefinitely. Added `requestTimeout` (30s) and `headersTimeout` (15s) on the server.

16. **QA agent: no workspace path for cloning repos** — QA needs to clone repos to run tests independently, but the agent definition didn't specify where. Updated to use `/home/agent/repos/` (same as SWE agents).

17. **TPM agent: misleading work assignment mechanism** — TPM definition said "tagging the SWE agent name" but all agents share one GitHub account, so @mentions don't work. Replaced with a structured assignment comment block (`**Assignment: SWE-<N>**`) that SWE agents poll for.

18. **All agents: log directory inside read-only mount** — Agent definitions pointed logs to `.claude/agents/logs/org-agent/<org-name>/` which lives inside the `.claude` volume mounted as `:ro`. Agents could never write logs there. Changed all agent log paths to `/data/logs/<org-name>/YYYY-MM-DD.md` which maps to the writable `./logs/` host volume. Updated CLAUDE.md accordingly.

19. **No `.dockerignore` files** — Build contexts for agent, webhook-listener, and dashboard containers had no `.dockerignore`, copying unnecessary files (markdown, node_modules) into images. Added `.dockerignore` to all three build contexts.

20. **Stale session URLs survive container restarts** — When a container restarts, the old session URL file remains until the new URL is captured, causing the dashboard to briefly show an invalid link. Added `rm -f` of the session URL file at entrypoint startup so the dashboard shows "Offline" until the new URL is ready.

### Fixed (stress test — rounds 21-25)

21. **Webhook listener: synchronous file writes block event loop** — `writeToQueue` used `writeFileSync`, meaning concurrent webhook deliveries would block each other. Converted to async `writeFile` with promises. Also added atomic write-then-rename pattern (`file.tmp` → `file`) so TPM never reads a half-written JSON envelope.

22. **Cron sweep: non-atomic queue file write** — `sweep.sh` wrote directly to the final filename. If TPM read the file mid-write, it would get partial JSON. Added write-to-temp-then-`mv` pattern, matching the webhook listener's approach.

23. **`start.sh`: no validation of `SWE_AGENT_COUNT`** — Setting `SWE_AGENT_COUNT=0`, a negative number, or a non-numeric string would silently pass to `docker compose --scale` and produce unpredictable results. Added validation requiring a positive integer, with a clear error message on failure.

24. **Webhook listener: silent failure on missing secrets** — If a webhook secret env var wasn't set, the org would appear in the configured list but all events from it would fail signature validation with no clear indication why. Added a startup warning that names the missing env var and explains that events will be rejected.

25. **`.env.example`: placeholder secrets look deployable** — Placeholder values like `your-herzog-webhook-secret-here` could be missed during setup. Changed to `CHANGE_ME` with a `openssl rand -hex 32` generation hint. Added a guard in `start.sh` that refuses to start if any `CHANGE_ME` values remain.

### Fixed (stress test — rounds 26-30)

26. **Webhook listener: ambiguous queue filenames** — GitHub delivery IDs are UUIDs containing hyphens. Combined with hyphenated timestamps, parsing the filename segments back is unreliable. Stripped hyphens from the delivery ID before building the filename.

27. **Dashboard: `loadSessions` crashes on non-200 responses** — If the `/api/sessions` endpoint returned an error (e.g., during restart), `res.json()` would throw on non-JSON bodies with no catch. Added `res.ok` guard before parsing.

28. **Entrypoint: stdout duplication** — `tee` already writes claude's output to stdout, but the `while` loop also `echo`'d every line, producing duplicate output in container logs. Removed the redundant `echo` and redirected the entrypoint's own status messages to stderr to keep them separate.

29. **Dashboard: `index.html` read from disk on every request** — `fs.readFileSync` was called on every `GET /` request. The file is static and never changes at runtime. Cached the HTML content at startup.

30. **Webhook listener: misleading warning on literal secrets** — The `envMatch` variable used in the missing-secret warning message could be `null` when the secret was a literal string (not an `${ENV_VAR}` reference), producing a confusing message. Extracted the hint into a conditional that gives the correct guidance for both env var and literal secret configurations.

### Changed — Architecture: TPM as subagent orchestrator

Major architectural change: TPM is now the sole long-running container that spawns SWE and QA as ephemeral subagents via Claude's Agent tool.

**Before:** 5+ containers (1 TPM + 3 SWE + 1 QA), all running independently. SWE/QA had no polling loop, so they couldn't discover work on their own — a design gap.

**After:** 1 agent container (TPM) spawns SWE/QA subagents on demand with full context. No polling needed. No idle containers. Direct delegation.

**What changed:**
- `tpm-agent.md` — rewritten as orchestrator with Subagent Management section, deployment examples, result handling, and concurrency limits
- `swe-agent.md` — rewritten as ephemeral subagent that receives assignment directly, does work, returns results
- `qa-agent.md` — rewritten as ephemeral subagent that receives PR to review, returns results
- `docker-compose.yml` — removed `swe-agent` and `qa-agent` services (5 containers → 5 services total, down from 7+)
- `entrypoint.sh` — simplified, removed SWE instance ID derivation (TPM assigns IDs to subagents)
- `start.sh` — removed `--scale` flag, simplified to plain `docker compose up`
- `.env.example` — `SWE_AGENT_COUNT` now controls max concurrent subagents (passed as env var to TPM)
- `CLAUDE.md` — fully rewritten for subagent architecture
- `README.md` — updated containers section, architecture diagram, and table of contents

### Fixed (stress test — rounds 31-40)

31. **Entrypoint boot prompt duplicates agent definition** — The `BOOT_PROMPT` in `entrypoint.sh` repeated the full Startup Sequence already defined in `tpm-agent.md`. Slimmed to one line: "Execute your Startup Sequence, then enter your Main Loop." Single source of truth for startup logic.

32. **TPM Main Loop has no concrete wait mechanism** — "Briefly wait" is vague and Claude has no native sleep. Changed to explicit `sleep 30` via bash. Also added instruction to ignore `.tmp` files in the queue (from atomic writes).

33. **TPM queue processing doesn't filter temp files** — Webhook listener and cron sweep write `.tmp` files that get renamed atomically. TPM could pick up a half-written `.tmp` file. Added explicit `.json`-only filter to queue processing instructions.

34. **Concurrent SWE subagents collide on repo clones** — Multiple SWEs working on the same repo would clone to the same directory. Changed clone paths to include the SWE instance number: `/home/agent/repos/<org>/<repo>-swe-<N>/`. Same fix for QA: `/home/agent/repos/<org>/<repo>-qa/`.

35. **SWE/QA subagents told to read org config they don't need** — Subagents receive their org and repo directly from TPM. Removed the unnecessary "Read organizations.yml" instruction and the org-config hard rule from both. Replaced with "Use the org/repo TPM gave you."

36. **Webhook listener periodic config reload blocks event loop** — `loadOrgSecrets()` used `readFileSync` inside a `setInterval`, blocking the event loop for the duration of the disk read every 5 minutes. Replaced with async `fs.readFile` callback.

37. **Dashboard health check hits HTML endpoint** — Docker HEALTHCHECK used `curl /` which returns the full HTML page. Added a proper `/health` JSON endpoint and updated the HEALTHCHECK to use it.

38. **Subagents won't load agent definition files automatically** — TPM's examples said "Read your full agent definition at .claude/agents/swe-agent.md" but subagents spawned via the Agent tool only see their prompt — they don't get `--agent` flags. TPM must now read the `.md` file first and include its full content in the subagent prompt.

39. **Stale queue files after crash** — If TPM crashes while processing a queue event, the file stays in `processing/` forever and never gets retried. Added recovery step to Startup Sequence: move any `.json` files from `processing/` back to `incoming/` on boot.

40. **Cron sweep.sh uses bash shebang on Alpine** — Alpine's cron container only has `sh` (BusyBox ash), not bash. Changed shebang from `#!/bin/bash` to `#!/bin/sh`.

### Fixed (stress test — rounds 41-50)

41. **TPM Startup Sequence has duplicate step numbering** — Two step 2's caused by inserting the recovery step without renumbering. Fixed to sequential 1-9.

42. **Webhook listener duplicates secret-parsing logic** — The `loadOrgSecrets` function and the `setInterval` reload callback had identical parsing code. Extracted `parseOrgSecrets()` as a shared function used by both the startup sync load and the async periodic reload.

43. **Dashboard reads session files on every API call** — `getAgentSessions` did synchronous disk reads on every `/api/sessions` request. With 10-second polling from the frontend, this is excessive. Added a 2-second TTL cache so rapid-fire requests reuse the last result.

44. **Entrypoint `--prompt` may not be compatible with `--remote-control`** — The `--prompt` flag's behavior with `--remote-control` is undocumented. Added a comment noting that if the flag is ignored, TPM still follows its agent definition which contains the full Startup Sequence. The prompt is kept as a best-effort boot instruction.

45. **Webhook listener leaves orphaned `.tmp` files on rename failure** — If `writeFile` succeeds but `rename` fails (e.g., disk full), the `.tmp` file stays forever. Added `fs.unlink` cleanup of the temp file in the rename error path.

46. **Org config says "restart the platform" to add an org** — The webhook listener hot-reloads every 5 minutes, so only the TPM container needs restarting. Updated the comment in `organizations.yml` to be specific.

47. **Entrypoint session URL regex is too broad** — The pattern matched any URL containing "session", "remote", or "connect", which would false-positive on GitHub URLs in claude's output (e.g., "connecting to repo"). Narrowed to match `claude.ai` / `app.claude.ai` URLs specifically.

48. **TPM container has no Docker health check** — If claude crashes inside the container, Docker doesn't know. Added a health check that verifies `tpm-url.txt` exists (120s start period to allow for initial bootstrap).

49. **`.gitignore` missing `*.log` files** — Entrypoint writes `tpm-stdout.log` to the sessions directory. These would get committed. Added `*.log` to gitignore.

50. **Webhook listener assumes queue directory exists** — On a completely fresh start with empty volumes, the first webhook event would fail because `/data/queue/incoming/` doesn't exist yet. Added `fs.mkdirSync(QUEUE_DIR, { recursive: true })` at startup.

### Fixed (stress test — rounds 51-55)

51. **Webhook listener: misplaced comment** — The "Guard against slow clients" comment got separated from the `requestTimeout`/`headersTimeout` lines when `mkdirSync` was inserted between them. Reordered so the comment sits with its code.

52. **Entrypoint writes full line as session URL** — The grep matched the line containing the URL, but `echo "$line"` wrote the entire line (e.g., "Session URL: https://...") to the URL file. The dashboard would then use the whole string as an `<a href>`, producing a broken link. Changed to `grep -o` to extract only the URL itself.

53. **Dashboard URL sanitization incomplete** — `trim()` handles trailing `\n` but not `\r\n` from different platforms. Replaced with a regex that strips all whitespace characters including carriage returns before trimming.

54. **Cron container has no health check** — If `crond` dies silently inside the Alpine container, sweep triggers stop and nobody notices until the user checks. Added a `pgrep crond` health check.

55. **Webhook listener crashes on malformed org config** — If `organizations.yml` is empty, has a syntax error that parses to non-object, or is missing the `organizations` array, `parseOrgSecrets` would throw on `for..of undefined`. Added a guard that checks for the array and logs a warning instead of crashing.

### Changed — Authentication: persistent OAuth via mounted volume

Replaced the split read-only auth mounts with a single read-write `~/.claude` volume mount. Claude Code authenticates via OAuth inside the container using its Linux file-based credential store (independent of the macOS Keychain on the host).

**What changed:**
- `docker-compose.yml` — replaced `~/.claude/auth:/home/agent/.claude/auth:ro` + `~/.claude/projects:rw` split mounts with single `~/.claude:/home/agent/.claude:rw`
- `entrypoint.sh` — added auth check on startup. If not authenticated, prints instructions and waits (keeps container alive for `docker exec`)
- `start.sh` — added first-run auth instructions to startup output
- `CLAUDE.md` — added Authentication section, updated volume mounts and bootstrap docs
- `README.md` — replaced host auth instructions with container-first auth flow, added "First-Run: Authenticate Claude" section

**First-run flow:** start containers → `docker exec -it <container> claude auth login` → visit URL in browser → authenticate → restart container → done forever.

### Fixed — Deployment testing

56. **Cron container: `chmod` fails on read-only mount** — `sweep.sh` is mounted `:ro` into the container, so `chmod +x /sweep.sh` in the compose command fails on every boot, causing a restart loop. Removed the `chmod` from the compose command — the file already has execute permissions set on the host.

57. **Ctrl container: silent crash on startup** — `ctrl-daemon` exits with code 1 and no log output. Under investigation — likely a runtime compatibility issue with the headless Docker environment. Non-blocking for core platform functionality (monitoring is a nice-to-have). Ctrl container left in compose but may need further debugging.

### Changed — Removed Docker, moved to native host execution

Docker was removed entirely. `claude remote-control` requires full OAuth login which cannot be completed inside a Docker container (interactive terminal input issues). Running natively on the host is simpler and fully supported.

**Removed:**
- `docker/` directory (all Dockerfiles, compose, entrypoint, .dockerignore, .env)
- `start.sh`, `refresh-token.sh`
- `queue/`, `sessions/`, `logs/` directories and `.gitkeep` files
- All Docker-related documentation

**What remains:**
- `.claude/agents/` — TPM, SWE, QA agent definitions
- `.claude/config/organizations.yml` — org configuration
- `CLAUDE.md` — full spec (rewritten for native execution)
- `README.md` — setup guide (rewritten)
- `CHANGELOG.md`
- `.gitignore`

**How it runs now:**
```
claude remote-control --dangerously-skip-permissions --agent .claude/agents/tpm-agent.md
```
TPM runs natively on the host, spawns SWE/QA subagents via the Agent tool. No containers, no volume mounts, no auth workarounds.
