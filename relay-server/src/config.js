require('dotenv').config();

module.exports = {
  port: parseInt(process.env.PORT, 10) || 8090,
  host: process.env.HOST || '0.0.0.0',

  adminToken: process.env.ADMIN_TOKEN || '',
  agentSecret: process.env.AGENT_SECRET || '',
  trustProxy: process.env.TRUST_PROXY === 'true',
  maxConnectionsPerIp: parseInt(process.env.MAX_CONNECTIONS_PER_IP, 10) || 20,
  maxDevices: parseInt(process.env.MAX_DEVICES, 10) || 500,

  sessionTimeoutMs: parseInt(process.env.SESSION_TIMEOUT_MS, 10) || 3600000,
  heartbeatIntervalMs: parseInt(process.env.HEARTBEAT_INTERVAL_MS, 10) || 10000,
  heartbeatTimeoutMs: parseInt(process.env.HEARTBEAT_TIMEOUT_MS, 10) || 30000,

  maxPendingRequests: parseInt(process.env.MAX_PENDING_REQUESTS, 10) || 50,
  maxActiveSessions: parseInt(process.env.MAX_ACTIVE_SESSIONS, 10) || 10,
  maxMessageSizeBytes: parseInt(process.env.MAX_MESSAGE_SIZE_BYTES, 10) || 2097152,
  maxMessagesPerSecond: parseInt(process.env.MAX_MESSAGES_PER_SECOND, 10) || 100,
  maxRelayFrameBytes: parseInt(process.env.MAX_RELAY_FRAME_BYTES, 10) || 2097152, // 2MB
  allowedOrigins: process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',').map(s => s.trim()) : [],

  logLevel: process.env.LOG_LEVEL || 'info',
};
