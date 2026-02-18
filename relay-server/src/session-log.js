const fs = require('fs');
const path = require('path');
const logger = require('./logger');

const LOG_FILE = path.join(__dirname, '..', 'logs', 'sessions.json');

class SessionLog {
  constructor() {
    this._sessions = this._load();
  }

  _load() {
    try {
      if (fs.existsSync(LOG_FILE)) {
        return JSON.parse(fs.readFileSync(LOG_FILE, 'utf8'));
      }
    } catch (e) {
      logger.warn('Failed to load session log', { error: e.message });
    }
    return [];
  }

  _save() {
    try {
      fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });
      fs.writeFileSync(LOG_FILE, JSON.stringify(this._sessions, null, 2));
    } catch (e) {
      logger.error('Failed to save session log', { error: e.message });
    }
  }

  logSessionStart(sessionId, agentId, customerName, hostname, adminName) {
    this._sessions.push({
      sessionId,
      agentId,
      customerName,
      hostname,
      adminName,
      startedAt: new Date().toISOString(),
      endedAt: null,
      duration: null,
      endReason: null,
      endedBy: null,
    });
    this._save();
    logger.info('Session logged: start', { sessionId, customerName, adminName });
  }

  logSessionEnd(sessionId, reason, endedBy) {
    const entry = this._sessions.find(s => s.sessionId === sessionId && !s.endedAt);
    if (entry) {
      entry.endedAt = new Date().toISOString();
      entry.duration = Math.round((new Date(entry.endedAt) - new Date(entry.startedAt)) / 1000);
      entry.endReason = reason;
      entry.endedBy = endedBy;
      this._save();
      logger.info('Session logged: end', { sessionId, duration: entry.duration, reason });
    }
  }

  getHistory(limit = 50, offset = 0) {
    return this._sessions
      .slice()
      .reverse()
      .slice(offset, offset + limit);
  }

  getStats() {
    const completed = this._sessions.filter(s => s.endedAt);
    const today = new Date().toISOString().slice(0, 10);
    const todaySessions = this._sessions.filter(s => s.startedAt && s.startedAt.startsWith(today));

    return {
      totalSessions: this._sessions.length,
      todaySessions: todaySessions.length,
      avgDuration: completed.length > 0
        ? Math.round(completed.reduce((sum, s) => sum + (s.duration || 0), 0) / completed.length)
        : 0,
      lastSession: this._sessions.length > 0 ? this._sessions[this._sessions.length - 1] : null,
    };
  }
}

module.exports = SessionLog;
