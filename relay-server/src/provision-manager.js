const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const logger = require('./logger');

const DATA_DIR = path.join(__dirname, '..', 'data');
const PROVISION_TOKENS_FILE = path.join(DATA_DIR, 'provision-tokens.json');
const AGENT_TOKENS_FILE = path.join(DATA_DIR, 'agent-tokens.json');

class ProvisionManager {
  constructor() {
    this.provisionTokens = [];
    this.agentTokens = new Map(); // agentId → token record
    this._load();
  }

  // ── Persistence ──

  _load() {
    try {
      if (fs.existsSync(PROVISION_TOKENS_FILE)) {
        this.provisionTokens = JSON.parse(fs.readFileSync(PROVISION_TOKENS_FILE, 'utf8'));
      }
    } catch (err) {
      logger.warn('Failed to load provision tokens', { error: err.message });
    }

    try {
      if (fs.existsSync(AGENT_TOKENS_FILE)) {
        const arr = JSON.parse(fs.readFileSync(AGENT_TOKENS_FILE, 'utf8'));
        for (const record of arr) {
          this.agentTokens.set(record.agentId, record);
        }
      }
    } catch (err) {
      logger.warn('Failed to load agent tokens', { error: err.message });
    }
  }

  _saveProvisionTokens() {
    try {
      if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
      fs.writeFileSync(PROVISION_TOKENS_FILE, JSON.stringify(this.provisionTokens, null, 2), 'utf8');
    } catch (err) {
      logger.warn('Failed to save provision tokens', { error: err.message });
    }
  }

  _saveAgentTokens() {
    try {
      if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
      const arr = Array.from(this.agentTokens.values());
      fs.writeFileSync(AGENT_TOKENS_FILE, JSON.stringify(arr, null, 2), 'utf8');
    } catch (err) {
      logger.warn('Failed to save agent tokens', { error: err.message });
    }
  }

  // ── Provisioning enabled? ──

  isProvisioningEnabled() {
    return this.provisionTokens.some(t => t.active);
  }

  // ── Provision tokens (admin manages these) ──

  createProvisionToken(label, maxUses = 0, expiresInDays = 0) {
    const token = crypto.randomBytes(32).toString('hex');
    const record = {
      token,
      label: label || 'Default',
      maxUses,        // 0 = unlimited
      usedCount: 0,
      expiresAt: expiresInDays > 0
        ? new Date(Date.now() + expiresInDays * 86400000).toISOString()
        : null,
      createdAt: new Date().toISOString(),
      active: true,
    };
    this.provisionTokens.push(record);
    this._saveProvisionTokens();
    logger.info('Provision token created', { label, maxUses, expiresInDays });
    return record;
  }

  listProvisionTokens() {
    return this.provisionTokens.map(t => ({
      token: t.token.slice(0, 8) + '...',
      label: t.label,
      maxUses: t.maxUses,
      usedCount: t.usedCount,
      expiresAt: t.expiresAt,
      createdAt: t.createdAt,
      active: t.active,
    }));
  }

  revokeProvisionToken(tokenPrefix) {
    const found = this.provisionTokens.find(t => t.token.startsWith(tokenPrefix));
    if (!found) return false;
    found.active = false;
    this._saveProvisionTokens();
    logger.info('Provision token revoked', { label: found.label });
    return true;
  }

  _validateProvisionToken(token) {
    const record = this.provisionTokens.find(t => t.token === token && t.active);
    if (!record) return null;

    // Check expiry
    if (record.expiresAt && new Date(record.expiresAt) < new Date()) {
      record.active = false;
      this._saveProvisionTokens();
      return null;
    }

    // Check usage limit
    if (record.maxUses > 0 && record.usedCount >= record.maxUses) {
      return null;
    }

    return record;
  }

  // ── Agent provisioning ──

  provisionAgent(provisionToken, agentId, hostname) {
    // Validate provision token
    const provRecord = this._validateProvisionToken(provisionToken);
    if (!provRecord) {
      return { error: 'INVALID_PROVISION_TOKEN', message: 'Invalid or expired provision token' };
    }

    // Validate agent_id format
    if (!agentId || agentId.length > 128 || !/^[a-zA-Z0-9\-_]+$/.test(agentId)) {
      return { error: 'INVALID_DATA', message: 'Invalid agent_id format' };
    }

    // If agent already has a token, return it (idempotent)
    const existing = this.agentTokens.get(agentId);
    if (existing && existing.active) {
      return { agent_token: existing.token };
    }

    // Generate new agent token
    const agentToken = crypto.randomBytes(32).toString('hex');
    const record = {
      agentId,
      token: agentToken,
      hostname: hostname || 'Unknown',
      provisionedAt: new Date().toISOString(),
      provisionedBy: provRecord.label,
      active: true,
    };

    this.agentTokens.set(agentId, record);
    provRecord.usedCount++;
    this._saveAgentTokens();
    this._saveProvisionTokens();

    logger.info('Agent provisioned', { agentId, hostname, provisionLabel: provRecord.label });
    return { agent_token: agentToken };
  }

  // ── Agent token validation (called on every WS connect) ──

  validateAgentToken(agentId, agentToken) {
    const record = this.agentTokens.get(agentId);
    if (!record || !record.active) return false;

    // Timing-safe comparison
    if (record.token.length !== agentToken.length) return false;
    return crypto.timingSafeEqual(
      Buffer.from(record.token),
      Buffer.from(agentToken)
    );
  }

  // ── Agent token management ──

  listAgentTokens() {
    const result = [];
    for (const [agentId, record] of this.agentTokens) {
      result.push({
        agentId,
        hostname: record.hostname,
        provisionedAt: record.provisionedAt,
        provisionedBy: record.provisionedBy,
        active: record.active,
      });
    }
    return result;
  }

  revokeAgentToken(agentId) {
    const record = this.agentTokens.get(agentId);
    if (!record) return false;
    record.active = false;
    this._saveAgentTokens();
    logger.info('Agent token revoked', { agentId });
    return true;
  }

  deleteAgentToken(agentId) {
    if (!this.agentTokens.has(agentId)) return false;
    this.agentTokens.delete(agentId);
    this._saveAgentTokens();
    logger.info('Agent token deleted', { agentId });
    return true;
  }
}

module.exports = ProvisionManager;
