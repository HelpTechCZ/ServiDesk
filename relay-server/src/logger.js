const config = require('./config');

const LEVELS = { debug: 0, info: 1, warn: 2, error: 3 };
const currentLevel = LEVELS[config.logLevel] ?? LEVELS.info;

function formatTimestamp() {
  return new Date().toISOString();
}

function log(level, message, context = {}) {
  if (LEVELS[level] < currentLevel) return;

  const contextStr = Object.keys(context).length > 0
    ? ' ' + Object.entries(context).map(([k, v]) => `${k}=${v}`).join(', ')
    : '';

  const line = `[${formatTimestamp()}] [${level.toUpperCase()}] ${message}${contextStr}`;
  if (level === 'error') {
    console.error(line);
  } else {
    console.log(line);
  }
}

module.exports = {
  debug: (msg, ctx) => log('debug', msg, ctx),
  info: (msg, ctx) => log('info', msg, ctx),
  warn: (msg, ctx) => log('warn', msg, ctx),
  error: (msg, ctx) => log('error', msg, ctx),
};
