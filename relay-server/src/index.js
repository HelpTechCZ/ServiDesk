const http = require('http');
const url = require('url');
const path = require('path');
const fs = require('fs');
const config = require('./config');
const logger = require('./logger');
const authModule = require('./auth');
const RelayWebSocketServer = require('./websocket-server');

const MAX_BODY_SIZE = 65536; // 64KB max request body

// Rate limiting pro /api/provision (per-IP)
const _provisionAttempts = new Map(); // ip → { count, lastAttempt }
function checkProvisionRateLimit(ip) {
  const now = Date.now();
  const record = _provisionAttempts.get(ip);
  if (!record) {
    _provisionAttempts.set(ip, { count: 1, lastAttempt: now });
    return true;
  }
  // Reset po 15 minutách
  if (now - record.lastAttempt > 900000) {
    _provisionAttempts.set(ip, { count: 1, lastAttempt: now });
    return true;
  }
  record.count++;
  record.lastAttempt = now;
  // Max 10 pokusů za 15 minut
  if (record.count > 10) {
    return false;
  }
  return true;
}

// Bezpečné čtení request body s limitem velikosti
function readBody(req, maxSize, callback) {
  let body = '';
  let size = 0;
  let aborted = false;
  req.on('data', chunk => {
    size += chunk.length;
    if (size > maxSize) {
      aborted = true;
      req.destroy();
      return;
    }
    body += chunk;
  });
  req.on('end', () => {
    if (aborted) {
      callback(new Error('Body too large'));
    } else {
      callback(null, body);
    }
  });
  req.on('error', () => {
    if (!aborted) callback(new Error('Request error'));
  });
}

// HTTP server pro health endpoint, API a WebSocket upgrade
const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }

  const parsed = url.parse(req.url, true);

  // ── Agent provisioning – autentizace provisioning tokenem (ne admin tokenem) ──
  if (req.method === 'POST' && parsed.pathname === '/api/provision') {
    const ip = config.trustProxy
      ? (req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress)
      : req.socket.remoteAddress;

    if (!checkProvisionRateLimit(ip)) {
      res.writeHead(429, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'RATE_LIMITED', message: 'Too many provision attempts' }));
      return;
    }

    readBody(req, MAX_BODY_SIZE, (err, body) => {
      if (err) {
        res.writeHead(413, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'BODY_TOO_LARGE', message: 'Request body exceeds limit' }));
        return;
      }
      try {
        const { provision_token, agent_id, hostname } = JSON.parse(body);
        const pm = wsServer.sessionManager.provisionManager;
        const result = pm.provisionAgent(provision_token, agent_id, hostname);
        if (result.error) {
          res.writeHead(403, { 'Content-Type': 'application/json' });
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json' });
        }
        res.end(JSON.stringify(result));
      } catch {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'INVALID_DATA', message: 'Invalid JSON' }));
      }
    });
    return;
  }

  // ── Update manifest a soubory ──
  if (req.method === 'GET' && parsed.pathname.startsWith('/update/')) {
    const safeName = path.basename(parsed.pathname);
    const filePath = path.join(__dirname, '..', 'update', safeName);

    fs.stat(filePath, (err, stats) => {
      if (err || !stats.isFile()) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not found' }));
        return;
      }

      const ext = path.extname(safeName).toLowerCase();
      const contentTypes = {
        '.json': 'application/json',
        '.exe': 'application/octet-stream',
        '.msi': 'application/octet-stream',
        '.zip': 'application/zip',
      };
      const contentType = contentTypes[ext] || 'application/octet-stream';

      res.writeHead(200, {
        'Content-Type': contentType,
        'Content-Length': stats.size,
        'Cache-Control': 'no-cache',
      });
      fs.createReadStream(filePath).pipe(res);
    });
    return;
  }

  // ── Admin API – vyžadují Bearer token ──
  if (req.url.startsWith('/api/')) {
    const token = (req.headers['authorization'] || '').replace('Bearer ', '');
    if (!authModule.verifyAdminToken(token)) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    const pm = wsServer.sessionManager.provisionManager;

    if (req.method === 'GET' && parsed.pathname === '/api/status') {
      const status = wsServer ? wsServer.getStatus() : {};
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'ok',
        uptime: Math.floor(process.uptime()),
        ...status,
      }));
      return;
    }

    if (req.method === 'GET' && parsed.pathname === '/api/sessions') {
      const limit = parseInt(parsed.query.limit) || 50;
      const offset = parseInt(parsed.query.offset) || 0;
      const sessions = wsServer.sessionManager.sessionLog.getHistory(limit, offset);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ sessions, total: wsServer.sessionManager.sessionLog._sessions.length }));
      return;
    }

    if (req.method === 'GET' && parsed.pathname === '/api/stats') {
      const stats = wsServer.sessionManager.sessionLog.getStats();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(stats));
      return;
    }

    // ── Provision tokens management ──

    if (req.method === 'GET' && parsed.pathname === '/api/provision-tokens') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ tokens: pm.listProvisionTokens() }));
      return;
    }

    if (req.method === 'POST' && parsed.pathname === '/api/provision-tokens') {
      readBody(req, MAX_BODY_SIZE, (err, body) => {
        if (err) {
          res.writeHead(413, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Body too large' }));
          return;
        }
        try {
          const { label, max_uses, expires_in_days } = JSON.parse(body);
          const record = pm.createProvisionToken(label, max_uses || 0, expires_in_days || 0);
          res.writeHead(201, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ token: record.token, label: record.label }));
        } catch {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Invalid JSON' }));
        }
      });
      return;
    }

    if (req.method === 'DELETE' && parsed.pathname.startsWith('/api/provision-tokens/')) {
      const tokenPrefix = parsed.pathname.split('/').pop();
      const ok = pm.revokeProvisionToken(tokenPrefix);
      res.writeHead(ok ? 200 : 404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: ok }));
      return;
    }

    // ── Agent tokens management ──

    if (req.method === 'GET' && parsed.pathname === '/api/agent-tokens') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ tokens: pm.listAgentTokens() }));
      return;
    }

    if (req.method === 'DELETE' && parsed.pathname.startsWith('/api/agent-tokens/')) {
      const agentId = decodeURIComponent(parsed.pathname.split('/').pop());
      const ok = pm.revokeAgentToken(agentId);
      res.writeHead(ok ? 200 : 404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: ok }));
      return;
    }
  }
});

// WebSocket server
const wsServer = new RelayWebSocketServer(server);

// Spuštění
server.listen(config.port, config.host, () => {
  logger.info(`Relay server listening on ${config.host}:${config.port}`);
  logger.info(`Health check: http://${config.host}:${config.port}/health`);
  logger.info(`WebSocket: ws://${config.host}:${config.port}/ws`);
});

// Graceful shutdown
function shutdown(signal) {
  logger.info(`Received ${signal}, shutting down...`);
  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });

  // Force exit po 5s
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 5000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

process.on('uncaughtException', (err) => {
  logger.error('Uncaught exception', { error: err.message, stack: err.stack });
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  logger.error('Unhandled rejection', { reason: String(reason) });
});
