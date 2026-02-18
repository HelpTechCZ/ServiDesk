const crypto = require('crypto');
const config = require('./config');
const logger = require('./logger');

// Timing-safe porovnání tokenů
function verifyAdminToken(providedToken) {
  if (!config.adminToken) {
    logger.error('ADMIN_TOKEN is not configured');
    return false;
  }

  const expected = Buffer.from(config.adminToken, 'utf8');
  const provided = Buffer.from(String(providedToken), 'utf8');

  if (expected.length !== provided.length) {
    return false;
  }

  return crypto.timingSafeEqual(expected, provided);
}

// Rate limiting per IP
const authAttempts = new Map(); // ip -> { count, firstAttempt }
const AUTH_WINDOW_MS = 5 * 60 * 1000; // 5 minut
const MAX_AUTH_FAILURES = 5;
const BAN_DURATION_MS = 15 * 60 * 1000; // 15 minut

const bannedIps = new Map(); // ip -> bannedUntil

function isIpBanned(ip) {
  const bannedUntil = bannedIps.get(ip);
  if (!bannedUntil) return false;

  if (Date.now() > bannedUntil) {
    bannedIps.delete(ip);
    return false;
  }
  return true;
}

function recordAuthFailure(ip) {
  const now = Date.now();
  let record = authAttempts.get(ip);

  if (!record || (now - record.firstAttempt) > AUTH_WINDOW_MS) {
    record = { count: 0, firstAttempt: now };
  }

  record.count++;
  authAttempts.set(ip, record);

  if (record.count >= MAX_AUTH_FAILURES) {
    bannedIps.set(ip, now + BAN_DURATION_MS);
    authAttempts.delete(ip);
    logger.warn('IP banned for repeated auth failures', { ip, duration: '15min' });
  }
}

function clearAuthFailures(ip) {
  authAttempts.delete(ip);
}

// Generování session tokenu
function generateSessionId() {
  return crypto.randomBytes(24).toString('hex');
}

// Periodický cleanup starých záznamů
function cleanupAuthRecords() {
  const now = Date.now();

  for (const [ip, record] of authAttempts) {
    if ((now - record.firstAttempt) > AUTH_WINDOW_MS) {
      authAttempts.delete(ip);
    }
  }

  for (const [ip, bannedUntil] of bannedIps) {
    if (now > bannedUntil) {
      bannedIps.delete(ip);
    }
  }
}

// Timing-safe SHA-256 porovnání pro unattended heslo
function verifyUnattendedPassword(providedHash, storedHash) {
  if (!storedHash || !providedHash) return false;

  const stored = Buffer.from(storedHash, 'hex');
  const provided = Buffer.from(providedHash, 'hex');

  if (stored.length !== provided.length) return false;

  return crypto.timingSafeEqual(stored, provided);
}

module.exports = {
  verifyAdminToken,
  verifyUnattendedPassword,
  isIpBanned,
  recordAuthFailure,
  clearAuthFailures,
  generateSessionId,
  cleanupAuthRecords,
};
