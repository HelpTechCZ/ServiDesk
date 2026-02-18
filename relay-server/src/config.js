require('dotenv').config();

module.exports = {
  port: parseInt(process.env.PORT, 10) || 8090,
  host: process.env.HOST || '0.0.0.0',

  adminToken: process.env.ADMIN_TOKEN || '',

  sessionTimeoutMs: parseInt(process.env.SESSION_TIMEOUT_MS, 10) || 3600000,
  heartbeatIntervalMs: parseInt(process.env.HEARTBEAT_INTERVAL_MS, 10) || 10000,
  heartbeatTimeoutMs: parseInt(process.env.HEARTBEAT_TIMEOUT_MS, 10) || 30000,

  maxPendingRequests: parseInt(process.env.MAX_PENDING_REQUESTS, 10) || 50,
  maxActiveSessions: parseInt(process.env.MAX_ACTIVE_SESSIONS, 10) || 10,
  maxMessageSizeBytes: parseInt(process.env.MAX_MESSAGE_SIZE_BYTES, 10) || 2097152,

  logLevel: process.env.LOG_LEVEL || 'info',
};
