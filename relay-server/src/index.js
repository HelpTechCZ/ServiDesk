const http = require('http');
const url = require('url');
const path = require('path');
const fs = require('fs');
const config = require('./config');
const logger = require('./logger');
const authModule = require('./auth');
const RelayWebSocketServer = require('./websocket-server');

// HTTP server pro health endpoint, API a WebSocket upgrade
const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    const status = wsServer ? wsServer.getStatus() : {};
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      uptime: Math.floor(process.uptime()),
      ...status,
    }));
    return;
  }

  // API endpointy – vyžadují Bearer token
  if (req.url.startsWith('/api/')) {
    const token = (req.headers['authorization'] || '').replace('Bearer ', '');
    if (!authModule.verifyAdminToken(token)) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    const parsed = url.parse(req.url, true);

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
  }

  // Statické soubory pro auto-update: /update/manifest.json, /update/setup.exe
  if (req.method === 'GET' && req.url.startsWith('/update/')) {
    const safeName = path.basename(url.parse(req.url).pathname);
    const filePath = path.join(__dirname, '..', 'update', safeName);
    if (fs.existsSync(filePath)) {
      const ext = path.extname(safeName).toLowerCase();
      const mimeTypes = { '.json': 'application/json', '.exe': 'application/octet-stream' };
      res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'application/octet-stream' });
      fs.createReadStream(filePath).pipe(res);
      return;
    }
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
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
