const crypto = require('crypto');
const config = require('./config');
const logger = require('./logger');
const auth = require('./auth');
const SessionLog = require('./session-log');
const DeviceRegistry = require('./device-registry');

class SessionManager {
  constructor() {
    // Připojení agenti
    this.agents = new Map();
    // Fronta žádostí o podporu
    this.pendingRequests = new Map();
    // Aktivní sessions
    this.activeSessions = new Map();
    // Připojení admini
    this.admins = new Map();
    // Persistent session log
    this.sessionLog = new SessionLog();
    // Device registry
    this.deviceRegistry = new DeviceRegistry();

    // Periodický cleanup
    this._cleanupInterval = setInterval(() => this.cleanupExpired(), 30000);
  }

  // ── Agenti ──

  registerAgent(ws, data) {
    const { agent_id, customer_name, hostname, os_version, agent_version,
            unattended_enabled, unattended_password_hash, hw_info } = data;

    if (!agent_id || !customer_name || !hostname) {
      return { error: 'INVALID_DATA', message: 'Missing required fields: agent_id, customer_name, hostname' };
    }

    // Pokud agent už existuje, aktualizovat WS
    if (this.agents.has(agent_id)) {
      const existing = this.agents.get(agent_id);
      existing.ws = ws;
      existing.lastHeartbeat = Date.now();
      logger.info('Agent reconnected', { agentId: agent_id, hostname });
    } else {
      this.agents.set(agent_id, {
        ws,
        agentId: agent_id,
        customerName: customer_name,
        hostname,
        osVersion: os_version || 'Unknown',
        agentVersion: agent_version || '0.0.0',
        hwInfo: hw_info || null,
        status: 'connected',
        sessionId: null,
        connectedAt: Date.now(),
        lastHeartbeat: Date.now(),
      });
      logger.info('Agent registered', { agentId: agent_id, hostname });
    }

    const sessionId = auth.generateSessionId();
    const agent = this.agents.get(agent_id);
    agent.sessionId = sessionId;
    agent.status = 'connected';

    // Uložit/aktualizovat do device registry
    this.deviceRegistry.upsertDevice(agent_id, {
      hostname,
      osVersion: os_version || 'Unknown',
      agentVersion: agent_version || '0.0.0',
      customerName: customer_name,
      unattendedEnabled: unattended_enabled || false,
      unattendedPasswordHash: unattended_password_hash || '',
      hwInfo: hw_info || null,
    });

    return {
      type: 'agent_registered',
      payload: { session_id: sessionId, status: 'waiting' },
    };
  }

  requestSupport(agentId, data) {
    const agent = this.agents.get(agentId);
    if (!agent) {
      return { error: 'AGENT_NOT_FOUND', message: 'Agent not registered' };
    }

    if (this.pendingRequests.size >= config.maxPendingRequests) {
      return { error: 'RATE_LIMITED', message: 'Too many pending requests' };
    }

    const sessionId = agent.sessionId;
    agent.status = 'waiting';

    this.pendingRequests.set(sessionId, {
      agentId,
      customerName: data.customer_name || agent.customerName,
      hostname: agent.hostname,
      osVersion: agent.osVersion,
      message: data.message || '',
      screenWidth: data.screen_width || 1920,
      screenHeight: data.screen_height || 1080,
      requestedAt: Date.now(),
    });

    logger.info('Support requested', { sessionId, customer: agent.customerName });

    // Notifikovat všechny adminy
    const notification = {
      type: 'support_request',
      payload: {
        session_id: sessionId,
        customer_name: data.customer_name || agent.customerName,
        hostname: agent.hostname,
        os_version: agent.osVersion,
        requested_at: new Date().toISOString(),
        message: data.message || '',
        hw_info: agent.hwInfo || null,
      },
    };

    for (const [, admin] of this.admins) {
      if (admin.authenticated && admin.ws.readyState === 1) {
        admin.ws.send(JSON.stringify(notification));
      }
    }

    return null; // Success, no response needed to agent
  }

  acceptSupport(sessionId, adminWs, adminName) {
    const request = this.pendingRequests.get(sessionId);
    if (!request) {
      return { error: 'SESSION_NOT_FOUND', message: 'Session neexistuje nebo vypršela' };
    }

    if (this.activeSessions.size >= config.maxActiveSessions) {
      return { error: 'RATE_LIMITED', message: 'Too many active sessions' };
    }

    const agent = this.agents.get(request.agentId);
    if (!agent || agent.ws.readyState !== 1) {
      this.pendingRequests.delete(sessionId);
      return { error: 'AGENT_DISCONNECTED', message: 'Agent se odpojil' };
    }

    // Odebrat z fronty
    this.pendingRequests.delete(sessionId);

    // Vytvořit aktivní session
    agent.status = 'in_session';
    this.activeSessions.set(sessionId, {
      agentId: request.agentId,
      agentWs: agent.ws,
      viewerWs: adminWs,
      adminName,
      startedAt: Date.now(),
      lastActivity: Date.now(),
    });

    // Oznámit agentovi
    const agentMsg = {
      type: 'session_accepted',
      payload: {
        admin_name: adminName,
        message: 'Připojuji se, prosím nechte PC zapnuté.',
      },
    };
    agent.ws.send(JSON.stringify(agentMsg));

    // Oznámit vieweru
    const viewerMsg = {
      type: 'session_started',
      payload: {
        session_id: sessionId,
        screen_width: request.screenWidth || 1920,
        screen_height: request.screenHeight || 1080,
      },
    };

    // Zalogovat session start
    this.sessionLog.logSessionStart(sessionId, request.agentId, request.customerName, request.hostname, adminName);

    logger.info('Session accepted', { sessionId, admin: adminName });

    return viewerMsg;
  }

  endSession(sessionId, reason, endedBy) {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      // Zkusit odebrat z pending
      if (this.pendingRequests.has(sessionId)) {
        this.pendingRequests.delete(sessionId);
        logger.info('Pending request cancelled', { sessionId });
      }
      return;
    }

    const endMsg = {
      type: 'session_ended',
      payload: { reason: reason || 'completed', ended_by: endedBy || 'unknown' },
    };
    const endMsgStr = JSON.stringify(endMsg);

    // Oznámit obě strany
    if (session.agentWs && session.agentWs.readyState === 1) {
      session.agentWs.send(endMsgStr);
    }
    if (session.viewerWs && session.viewerWs.readyState === 1) {
      session.viewerWs.send(endMsgStr);
    }

    // Resetovat stav agenta
    const agent = this.agents.get(session.agentId);
    if (agent) {
      agent.status = 'connected';
      agent.sessionId = null;
    }

    // Zalogovat session end
    this.sessionLog.logSessionEnd(sessionId, reason, endedBy);

    this.activeSessions.delete(sessionId);
    logger.info('Session ended', { sessionId, reason, endedBy });
  }

  // ── Admini ──

  registerAdmin(ws, adminId, adminName) {
    this.admins.set(adminId, {
      ws,
      adminName,
      authenticated: true,
      connectedAt: Date.now(),
      lastHeartbeat: Date.now(),
    });

    logger.info('Admin connected', { adminId, name: adminName });

    // Vrátit seznam čekajících žádostí
    const pendingList = [];
    for (const [sid, req] of this.pendingRequests) {
      pendingList.push({
        session_id: sid,
        customer_name: req.customerName,
        hostname: req.hostname,
        os_version: req.osVersion,
        requested_at: new Date(req.requestedAt).toISOString(),
        message: req.message,
      });
    }

    return {
      type: 'admin_auth_result',
      payload: { success: true, pending_requests: pendingList },
    };
  }

  // ── Odpojení ──

  removeAgent(agentId) {
    const agent = this.agents.get(agentId);
    if (!agent) return;

    // Ukončit aktivní session pokud existuje
    if (agent.sessionId && this.activeSessions.has(agent.sessionId)) {
      this.endSession(agent.sessionId, 'error', 'agent_disconnected');
    }

    // Odebrat z pending
    if (agent.sessionId && this.pendingRequests.has(agent.sessionId)) {
      this.pendingRequests.delete(agent.sessionId);
    }

    this.agents.delete(agentId);
    logger.info('Agent disconnected', { agentId });
  }

  removeAdmin(adminId) {
    const admin = this.admins.get(adminId);
    if (!admin) return;

    // Ukončit sessions které tento admin má
    for (const [sid, session] of this.activeSessions) {
      if (session.viewerWs === admin.ws) {
        this.endSession(sid, 'error', 'viewer_disconnected');
      }
    }

    this.admins.delete(adminId);
    logger.info('Admin disconnected', { adminId });
  }

  // ── Device list ──

  getOnlineAgentIds() {
    return new Set(this.agents.keys());
  }

  getDeviceList() {
    return this.deviceRegistry.getDeviceList(this.getOnlineAgentIds());
  }

  deleteDevice(agentId) {
    // Pokud je agent online, nelze smazat
    if (this.agents.has(agentId)) {
      return { error: 'AGENT_ONLINE', message: 'Nelze smazat online zařízení' };
    }

    const device = this.deviceRegistry.getDevice(agentId);
    if (!device) {
      return { error: 'NOT_FOUND', message: 'Zařízení nebylo nalezeno' };
    }

    this.deviceRegistry.removeDevice(agentId);
    logger.info('Device deleted by admin', { agentId });
    return null; // Success
  }

  // ── Unattended access ──

  connectUnattended(adminWs, agentId, passwordHash, adminName) {
    // Najít agenta
    const agent = this.agents.get(agentId);
    if (!agent || agent.ws.readyState !== 1) {
      return { error: 'AGENT_OFFLINE', message: 'Agent není online' };
    }

    // Ověřit z device registry
    const device = this.deviceRegistry.getDevice(agentId);
    if (!device || !device.unattendedEnabled) {
      return { error: 'UNATTENDED_DISABLED', message: 'Unattended přístup není povolen' };
    }

    if (!device.unattendedPasswordHash) {
      return { error: 'NO_PASSWORD', message: 'Heslo není nastaveno' };
    }

    // Timing-safe SHA-256 porovnání
    const storedHash = Buffer.from(device.unattendedPasswordHash, 'hex');
    const providedHash = Buffer.from(passwordHash, 'hex');

    if (storedHash.length !== providedHash.length ||
        !crypto.timingSafeEqual(storedHash, providedHash)) {
      return { error: 'INVALID_PASSWORD', message: 'Nesprávné heslo' };
    }

    // Vytvořit session (podobně jako acceptSupport)
    if (this.activeSessions.size >= config.maxActiveSessions) {
      return { error: 'RATE_LIMITED', message: 'Too many active sessions' };
    }

    const sessionId = auth.generateSessionId();
    agent.status = 'in_session';
    agent.sessionId = sessionId;

    this.activeSessions.set(sessionId, {
      agentId,
      agentWs: agent.ws,
      viewerWs: adminWs,
      adminName,
      startedAt: Date.now(),
      lastActivity: Date.now(),
    });

    // Oznámit agentovi – session_accepted (přeskočí GUI approval)
    const agentMsg = {
      type: 'session_accepted',
      payload: {
        admin_name: adminName,
        message: 'Unattended připojení',
        unattended: true,
      },
    };
    agent.ws.send(JSON.stringify(agentMsg));

    // Session log
    this.sessionLog.logSessionStart(sessionId, agentId, agent.customerName, agent.hostname, adminName);

    logger.info('Unattended session started', { sessionId, agentId, admin: adminName });

    // Vrátit viewer response
    return {
      type: 'session_started',
      payload: {
        session_id: sessionId,
        screen_width: 1920,
        screen_height: 1080,
      },
    };
  }

  // ── Update agent info ──

  updateAgentInfo(agentId, info) {
    const agent = this.agents.get(agentId);
    if (!agent) return;

    // Aktualizovat device registry s novými unattended údaji
    this.deviceRegistry.upsertDevice(agentId, {
      hostname: agent.hostname,
      osVersion: agent.osVersion,
      agentVersion: agent.agentVersion,
      customerName: agent.customerName,
      unattendedEnabled: info.unattended_enabled || false,
      unattendedPasswordHash: info.unattended_password_hash || '',
    });

    logger.info('Agent info updated', { agentId, unattended: info.unattended_enabled });
  }

  // ── Heartbeat ──

  updateHeartbeat(ws) {
    // Najít agenta nebo admina podle ws
    for (const [, agent] of this.agents) {
      if (agent.ws === ws) {
        agent.lastHeartbeat = Date.now();
        return;
      }
    }
    for (const [, admin] of this.admins) {
      if (admin.ws === ws) {
        admin.lastHeartbeat = Date.now();
        return;
      }
    }
  }

  // ── Cleanup ──

  cleanupExpired() {
    const now = Date.now();

    // Expired sessions
    for (const [sid, session] of this.activeSessions) {
      if ((now - session.startedAt) > config.sessionTimeoutMs) {
        logger.warn('Session expired', { sessionId: sid });
        this.endSession(sid, 'timeout', 'server');
      }
    }

    // Dead agents (no heartbeat)
    for (const [agentId, agent] of this.agents) {
      if ((now - agent.lastHeartbeat) > config.heartbeatTimeoutMs) {
        logger.warn('Agent heartbeat timeout', { agentId });
        if (agent.ws.readyState === 1) agent.ws.close();
        this.removeAgent(agentId);
      }
    }

    // Dead admins
    for (const [adminId, admin] of this.admins) {
      if ((now - admin.lastHeartbeat) > config.heartbeatTimeoutMs) {
        logger.warn('Admin heartbeat timeout', { adminId });
        if (admin.ws.readyState === 1) admin.ws.close();
        this.removeAdmin(adminId);
      }
    }

    // Cleanup auth records
    auth.cleanupAuthRecords();
  }

  // ── Vyhledávání ──

  findAgentByWs(ws) {
    for (const [agentId, agent] of this.agents) {
      if (agent.ws === ws) return { agentId, agent };
    }
    return null;
  }

  findAdminByWs(ws) {
    for (const [adminId, admin] of this.admins) {
      if (admin.ws === ws) return { adminId, admin };
    }
    return null;
  }

  findSessionByWs(ws) {
    for (const [sessionId, session] of this.activeSessions) {
      if (session.agentWs === ws || session.viewerWs === ws) {
        return { sessionId, session };
      }
    }
    return null;
  }

  // ── Status ──

  getStatus() {
    return {
      connectedAgents: this.agents.size,
      connectedAdmins: this.admins.size,
      pendingRequests: this.pendingRequests.size,
      activeSessions: this.activeSessions.size,
    };
  }

  destroy() {
    clearInterval(this._cleanupInterval);
  }
}

module.exports = SessionManager;
