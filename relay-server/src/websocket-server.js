const { WebSocketServer } = require('ws');
const crypto = require('crypto');
const config = require('./config');
const logger = require('./logger');
const authModule = require('./auth');
const SessionManager = require('./session-manager');
const { setupRelay, teardownRelay } = require('./relay-handler');

class RelayWebSocketServer {
  constructor(httpServer) {
    this.sessionManager = new SessionManager();

    this.wss = new WebSocketServer({
      server: httpServer,
      path: '/ws',
      maxPayload: config.maxMessageSizeBytes,
    });

    this.wss.on('connection', (ws, req) => this._onConnection(ws, req));

    // Heartbeat interval
    this._heartbeatInterval = setInterval(() => {
      this.wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
          return ws.terminate();
        }
        ws.isAlive = false;
        ws.ping();
      });
    }, config.heartbeatIntervalMs);

    this.wss.on('close', () => {
      clearInterval(this._heartbeatInterval);
      this.sessionManager.destroy();
    });

    logger.info('WebSocket server initialized', { path: '/ws' });
  }

  _onConnection(ws, req) {
    const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress;

    // Rate limit check
    if (authModule.isIpBanned(ip)) {
      logger.warn('Banned IP attempted connection', { ip });
      ws.close(4003, 'Temporarily banned');
      return;
    }

    ws.isAlive = true;
    ws.clientType = null; // 'agent' | 'admin'
    ws.clientId = null;
    ws.ip = ip;

    ws.on('pong', () => {
      ws.isAlive = true;
      this.sessionManager.updateHeartbeat(ws);
    });

    ws.on('error', (err) => {
      logger.error('WebSocket error', { ip, error: err.message });
    });

    ws.on('close', () => this._onDisconnect(ws));

    // Čekáme na první zprávu pro identifikaci typu klienta
    ws.once('message', (data, isBinary) => {
      if (isBinary) {
        ws.close(4000, 'First message must be JSON');
        return;
      }

      try {
        const msg = JSON.parse(data.toString());
        this._handleFirstMessage(ws, msg);
      } catch {
        ws.close(4000, 'Invalid JSON');
      }
    });

    logger.debug('New connection', { ip });
  }

  _handleFirstMessage(ws, msg) {
    switch (msg.type) {
      case 'agent_register':
        this._handleAgentRegister(ws, msg.payload || {});
        break;
      case 'admin_auth':
        this._handleAdminAuth(ws, msg.payload || {});
        break;
      default:
        this._sendError(ws, 'INVALID_MESSAGE', 'First message must be agent_register or admin_auth');
        ws.close(4000, 'Unknown client type');
    }
  }

  _handleAgentRegister(ws, payload) {
    const result = this.sessionManager.registerAgent(ws, payload);

    if (result.error) {
      this._sendError(ws, result.error, result.message);
      ws.close(4001, result.message);
      return;
    }

    ws.clientType = 'agent';
    ws.clientId = payload.agent_id;
    ws.send(JSON.stringify(result));

    // Notifikovat adminy o novém/reconected agentovi
    this._broadcastDeviceStatus(payload.agent_id, true);

    // Nastavit zpracování dalších zpráv od agenta
    ws.on('message', (data, isBinary) => this._handleAgentMessage(ws, data, isBinary));
  }

  _handleAdminAuth(ws, payload) {
    const { admin_token, admin_name } = payload;

    if (!authModule.verifyAdminToken(admin_token)) {
      authModule.recordAuthFailure(ws.ip);
      this._sendError(ws, 'AUTH_FAILED', 'Invalid admin token');
      ws.close(4001, 'Auth failed');
      return;
    }

    authModule.clearAuthFailures(ws.ip);

    const adminId = crypto.randomUUID();
    ws.clientType = 'admin';
    ws.clientId = adminId;

    const result = this.sessionManager.registerAdmin(ws, adminId, admin_name || 'Admin');
    ws.send(JSON.stringify(result));

    // Nastavit zpracování dalších zpráv od admina
    ws.on('message', (data, isBinary) => this._handleAdminMessage(ws, data, isBinary));
  }

  _handleAgentMessage(ws, data, isBinary) {
    // Binární zprávy – pokud je agent v session, relay handler se o to postará
    if (isBinary) return;

    try {
      const msg = JSON.parse(data.toString());

      switch (msg.type) {
        case 'request_support': {
          const found = this.sessionManager.findAgentByWs(ws);
          if (!found) return;
          const err = this.sessionManager.requestSupport(found.agentId, msg.payload || {});
          if (err) this._sendError(ws, err.error, err.message);
          break;
        }

        case 'session_end': {
          const sessionId = msg.payload?.session_id;
          if (sessionId) {
            const session = this.sessionManager.activeSessions.get(sessionId);
            if (session) teardownRelay(session);
            this.sessionManager.endSession(sessionId, msg.payload?.reason || 'completed', 'customer');
          }
          break;
        }

        case 'update_agent_info': {
          const found = this.sessionManager.findAgentByWs(ws);
          if (found) {
            this.sessionManager.updateAgentInfo(found.agentId, msg.payload || {});
            this._broadcastDeviceStatus(found.agentId, true);
          }
          break;
        }

        case 'heartbeat':
          this.sessionManager.updateHeartbeat(ws);
          ws.send(JSON.stringify({
            type: 'heartbeat_ack',
            payload: { timestamp: msg.payload?.timestamp }
          }));
          break;

        default:
          logger.debug('Unknown agent message type', { type: msg.type });
      }
    } catch {
      logger.warn('Invalid JSON from agent');
    }
  }

  _handleAdminMessage(ws, data, isBinary) {
    // Binární zprávy – pokud je admin v session, relay handler se o to postará
    if (isBinary) return;

    try {
      const msg = JSON.parse(data.toString());

      switch (msg.type) {
        case 'accept_support': {
          const sessionId = msg.payload?.session_id;
          const found = this.sessionManager.findAdminByWs(ws);
          if (!found) return;

          const result = this.sessionManager.acceptSupport(sessionId, ws, found.admin.adminName);
          if (result.error) {
            this._sendError(ws, result.error, result.message);
            return;
          }

          ws.send(JSON.stringify(result));

          // Nastavit relay
          const session = this.sessionManager.activeSessions.get(sessionId);
          if (session) {
            setupRelay(sessionId, session);
          }
          break;
        }

        case 'session_end': {
          const sessionId = msg.payload?.session_id;
          if (sessionId) {
            const session = this.sessionManager.activeSessions.get(sessionId);
            if (session) teardownRelay(session);
            this.sessionManager.endSession(sessionId, msg.payload?.reason || 'completed', 'admin');
          }
          break;
        }

        case 'get_device_list': {
          const devices = this.sessionManager.getDeviceList();
          ws.send(JSON.stringify({
            type: 'device_list',
            payload: { devices },
          }));
          break;
        }

        case 'delete_device': {
          const { agent_id } = msg.payload || {};
          if (!agent_id) {
            this._sendError(ws, 'INVALID_DATA', 'Chybí agent_id');
            break;
          }

          const delResult = this.sessionManager.deleteDevice(agent_id);
          if (delResult) {
            this._sendError(ws, delResult.error, delResult.message);
          } else {
            ws.send(JSON.stringify({
              type: 'device_deleted',
              payload: { agent_id },
            }));
          }
          break;
        }

        case 'connect_unattended': {
          const { agent_id, password, admin_token } = msg.payload || {};
          if (!authModule.verifyAdminToken(admin_token)) {
            this._sendError(ws, 'AUTH_FAILED', 'Invalid admin token');
            break;
          }

          const found = this.sessionManager.findAdminByWs(ws);
          if (!found) {
            this._sendError(ws, 'NOT_AUTHENTICATED', 'Admin not authenticated');
            break;
          }

          const result = this.sessionManager.connectUnattended(ws, agent_id, password, found.admin.adminName);
          if (result.error) {
            this._sendError(ws, result.error, result.message);
            break;
          }

          ws.send(JSON.stringify(result));

          // Nastavit relay
          const sessionId = result.payload.session_id;
          const session = this.sessionManager.activeSessions.get(sessionId);
          if (session) {
            setupRelay(sessionId, session);
          }
          break;
        }

        case 'heartbeat':
          this.sessionManager.updateHeartbeat(ws);
          ws.send(JSON.stringify({
            type: 'heartbeat_ack',
            payload: { timestamp: msg.payload?.timestamp }
          }));
          break;

        default:
          logger.debug('Unknown admin message type', { type: msg.type });
      }
    } catch {
      logger.warn('Invalid JSON from admin');
    }
  }

  _onDisconnect(ws) {
    if (ws.clientType === 'agent' && ws.clientId) {
      // Teardown relay pokud existuje
      const found = this.sessionManager.findSessionByWs(ws);
      if (found) teardownRelay(found.session);
      this.sessionManager.removeAgent(ws.clientId);
      // Notifikovat adminy o offline agentovi
      this._broadcastDeviceStatus(ws.clientId, false);
    } else if (ws.clientType === 'admin' && ws.clientId) {
      const found = this.sessionManager.findSessionByWs(ws);
      if (found) teardownRelay(found.session);
      this.sessionManager.removeAdmin(ws.clientId);
    }
  }

  _broadcastDeviceStatus(agentId, isOnline) {
    const msg = JSON.stringify({
      type: 'device_status_changed',
      payload: { agent_id: agentId, is_online: isOnline },
    });
    for (const [, admin] of this.sessionManager.admins) {
      if (admin.authenticated && admin.ws.readyState === 1) {
        admin.ws.send(msg);
      }
    }
  }

  _sendError(ws, code, message) {
    if (ws.readyState !== 1) return;
    ws.send(JSON.stringify({
      type: 'error',
      payload: { code, message },
    }));
  }

  getStatus() {
    return this.sessionManager.getStatus();
  }
}

module.exports = RelayWebSocketServer;
