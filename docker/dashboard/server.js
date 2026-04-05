const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3801;
const SESSIONS_DIR = process.env.SESSIONS_DIR || '/data/sessions';
const HTML_PATH = path.join(__dirname, 'index.html');

// Cache index.html at startup — it never changes at runtime
const HTML_CONTENT = fs.readFileSync(HTML_PATH, 'utf8');

// Cache sessions, refresh at most every 2 seconds to avoid redundant disk reads
let cachedSessions = [];
let lastRefresh = 0;
const CACHE_TTL = 2000;

function refreshSessions() {
    const now = Date.now();
    if (now - lastRefresh < CACHE_TTL) return cachedSessions;
    lastRefresh = now;

    const sessions = [];
    try {
        const files = fs.readdirSync(SESSIONS_DIR).filter(f => f.endsWith('-url.txt'));

        for (const file of files) {
            const name = file.replace('-url.txt', '');
            const filepath = path.join(SESSIONS_DIR, file);
            try {
                const url = fs.readFileSync(filepath, 'utf8').replace(/[\s\r\n]+/g, '').trim();
                sessions.push({ name, url, updated: fs.statSync(filepath).mtime });
            } catch (err) {
                sessions.push({ name, url: null, error: 'Failed to read session URL' });
            }
        }
    } catch (err) {
        console.error(`[dashboard] Error reading sessions dir: ${err.message}`);
    }

    // Sort: TPM first, then SWE by number, then QA
    sessions.sort((a, b) => {
        const order = name => {
            if (name === 'tpm') return 0;
            if (name.startsWith('swe-')) return 1;
            if (name === 'qa') return 2;
            return 3;
        };
        const diff = order(a.name) - order(b.name);
        if (diff !== 0) return diff;
        return a.name.localeCompare(b.name, undefined, { numeric: true });
    });

    cachedSessions = sessions;
    return sessions;
}

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok' }));
        return;
    }

    if (req.method === 'GET' && req.url === '/api/sessions') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(refreshSessions()));
        return;
    }

    if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(HTML_CONTENT);
        return;
    }

    res.writeHead(404);
    res.end('Not found');
});

server.listen(PORT, () => {
    console.log(`[dashboard] Listening on port ${PORT}`);
    console.log(`[dashboard] Watching sessions at ${SESSIONS_DIR}`);
});
