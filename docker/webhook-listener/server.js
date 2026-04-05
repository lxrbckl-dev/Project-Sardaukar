const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const PORT = process.env.PORT || 3800;
const QUEUE_DIR = process.env.QUEUE_DIR || '/data/queue/incoming';
const ORG_CONFIG_PATH = process.env.ORG_CONFIG_PATH || '/config/organizations.yml';
const MAX_BODY_SIZE = 10 * 1024 * 1024; // 10MB — GitHub payloads are typically <256KB

// Parse org config into a secrets map
function parseOrgSecrets(config) {
    const secrets = {};
    if (!config?.organizations || !Array.isArray(config.organizations)) {
        console.warn('[webhook-listener] WARNING: No organizations array in config');
        return secrets;
    }
    for (const org of config.organizations) {
        let secret = org.webhook_secret;
        const envMatch = secret.match(/^\$\{(.+)\}$/);
        if (envMatch) {
            secret = process.env[envMatch[1]] || '';
        }
        if (!secret) {
            const hint = envMatch ? `Set ${envMatch[1]} in .env` : 'Set webhook_secret in organizations.yml';
            console.warn(`[webhook-listener] WARNING: No webhook secret for org '${org.name}'. Events from this org will be rejected. ${hint}`);
        }
        secrets[org.name] = secret;
    }
    return secrets;
}

// Load organization config at startup (sync is fine here — happens once before server starts)
function loadOrgSecrets() {
    try {
        const raw = fs.readFileSync(ORG_CONFIG_PATH, 'utf8');
        return parseOrgSecrets(yaml.load(raw));
    } catch (err) {
        console.error(`[webhook-listener] Failed to load org config: ${err.message}`);
        return {};
    }
}

let orgSecrets = loadOrgSecrets();

// Reload config periodically (every 5 minutes) to pick up changes without blocking
setInterval(() => {
    fs.readFile(ORG_CONFIG_PATH, 'utf8', (err, raw) => {
        if (err) {
            console.error(`[webhook-listener] Failed to reload org config: ${err.message}`);
            return;
        }
        try {
            orgSecrets = parseOrgSecrets(yaml.load(raw));
            console.log(`[webhook-listener] Reloaded org config. Orgs: ${Object.keys(orgSecrets).join(', ')}`);
        } catch (parseErr) {
            console.error(`[webhook-listener] Failed to parse org config: ${parseErr.message}`);
        }
    });
}, 5 * 60 * 1000);

function verifySignature(payload, signature, secret) {
    if (!secret || !signature) return false;
    const expected = 'sha256=' + crypto.createHmac('sha256', secret).update(payload).digest('hex');
    const sigBuffer = Buffer.from(signature);
    const expectedBuffer = Buffer.from(expected);
    // timingSafeEqual throws on length mismatch — guard against malformed signatures
    if (sigBuffer.length !== expectedBuffer.length) return false;
    return crypto.timingSafeEqual(sigBuffer, expectedBuffer);
}

function writeToQueue(envelope) {
    return new Promise((resolve, reject) => {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        // Sanitize delivery ID (UUIDs contain hyphens) to avoid ambiguous filenames
        const safeDeliveryId = envelope.delivery_id.replace(/-/g, '');
        const filename = `${timestamp}_${envelope.org}_${envelope.event}_${safeDeliveryId}.json`;
        const filepath = path.join(QUEUE_DIR, filename);
        // Write to temp file then rename for atomicity — prevents TPM from reading a half-written file
        const tmpPath = filepath + '.tmp';
        fs.writeFile(tmpPath, JSON.stringify(envelope, null, 2), (writeErr) => {
            if (writeErr) return reject(writeErr);
            fs.rename(tmpPath, filepath, (renameErr) => {
                if (renameErr) {
                    // Clean up orphaned temp file
                    fs.unlink(tmpPath, () => {});
                    return reject(renameErr);
                }
                console.log(`[webhook-listener] Queued: ${filename}`);
                resolve();
            });
        });
    });
}

const server = http.createServer((req, res) => {
    // Health check
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', orgs: Object.keys(orgSecrets) }));
        return;
    }

    // Webhook endpoint
    if (req.method === 'POST' && req.url === '/hooks/github') {
        let body = '';
        let aborted = false;
        req.on('data', chunk => {
            body += chunk;
            if (body.length > MAX_BODY_SIZE) {
                aborted = true;
                res.writeHead(413, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Payload too large' }));
                req.destroy();
            }
        });
        req.on('end', () => {
            if (aborted) return;
            try {
                const payload = JSON.parse(body);
                const event = req.headers['x-github-event'];
                const deliveryId = req.headers['x-github-delivery'];
                const signature = req.headers['x-hub-signature-256'];

                // Identify org from payload
                const orgName = payload.organization?.login;

                // Validate signature before processing any event.
                // If org is known, use its specific secret.
                // If org is missing (e.g., ping events), try all known secrets.
                if (orgName) {
                    const secret = orgSecrets[orgName];
                    if (!secret) {
                        console.warn(`[webhook-listener] Unknown org: ${orgName}`);
                        res.writeHead(403, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ error: 'Unknown organization' }));
                        return;
                    }

                    if (!verifySignature(body, signature, secret)) {
                        console.warn(`[webhook-listener] Invalid signature for org: ${orgName}, Delivery: ${deliveryId}`);
                        res.writeHead(403, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ error: 'Invalid signature' }));
                        return;
                    }
                } else {
                    // No org in payload — try all known secrets to authenticate
                    const validWithAnySecret = Object.values(orgSecrets).some(
                        secret => secret && verifySignature(body, signature, secret)
                    );
                    if (!validWithAnySecret) {
                        console.warn(`[webhook-listener] No organization in payload and signature matches no known org. Event: ${event}, Delivery: ${deliveryId}`);
                        res.writeHead(403, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ error: 'Invalid signature' }));
                        return;
                    }
                }

                // Handle GitHub ping event (sent when webhook is first configured)
                if (event === 'ping') {
                    console.log(`[webhook-listener] Ping received. Zen: ${payload.zen}`);
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ status: 'pong' }));
                    return;
                }

                // Reject non-ping events without an organization
                if (!orgName) {
                    console.warn(`[webhook-listener] No organization in payload. Event: ${event}, Delivery: ${deliveryId}`);
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'No organization in payload' }));
                    return;
                }

                // Write to queue
                const envelope = {
                    org: orgName,
                    event: event,
                    delivery_id: deliveryId,
                    timestamp: new Date().toISOString(),
                    payload: payload
                };

                writeToQueue(envelope).then(() => {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ status: 'queued' }));
                }).catch(err => {
                    console.error(`[webhook-listener] Failed to write queue file: ${err.message}`);
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'Failed to queue event' }));
                });
            } catch (err) {
                console.error(`[webhook-listener] Error processing webhook: ${err.message}`);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Internal error' }));
            }
        });
        return;
    }

    // 404
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
});

// Ensure queue directory exists at startup
fs.mkdirSync(QUEUE_DIR, { recursive: true });

// Guard against slow clients holding connections open
server.requestTimeout = 30000;  // 30 seconds
server.headersTimeout = 15000;  // 15 seconds

server.listen(PORT, () => {
    console.log(`[webhook-listener] Listening on port ${PORT}`);
    console.log(`[webhook-listener] Configured orgs: ${Object.keys(orgSecrets).join(', ')}`);
});
