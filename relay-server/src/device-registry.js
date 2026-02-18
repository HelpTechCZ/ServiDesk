const fs = require('fs');
const path = require('path');
const logger = require('./logger');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DEVICES_FILE = path.join(DATA_DIR, 'devices.json');

class DeviceRegistry {
  constructor() {
    this.devices = new Map();
    this.load();
  }

  load() {
    try {
      if (fs.existsSync(DEVICES_FILE)) {
        const raw = fs.readFileSync(DEVICES_FILE, 'utf8');
        const arr = JSON.parse(raw);
        for (const device of arr) {
          this.devices.set(device.agentId, device);
        }
        logger.info('Device registry loaded', { count: this.devices.size });
      }
    } catch (err) {
      logger.warn('Failed to load device registry', { error: err.message });
    }
  }

  save() {
    try {
      if (!fs.existsSync(DATA_DIR)) {
        fs.mkdirSync(DATA_DIR, { recursive: true });
      }
      const arr = Array.from(this.devices.values());
      fs.writeFileSync(DEVICES_FILE, JSON.stringify(arr, null, 2), 'utf8');
    } catch (err) {
      logger.warn('Failed to save device registry', { error: err.message });
    }
  }

  upsertDevice(agentId, info) {
    const existing = this.devices.get(agentId);
    const now = new Date().toISOString();

    const record = {
      agentId,
      hostname: info.hostname || existing?.hostname || 'Unknown',
      osVersion: info.osVersion || existing?.osVersion || 'Unknown',
      agentVersion: info.agentVersion || existing?.agentVersion || '0.0.0',
      customerName: info.customerName || existing?.customerName || '',
      lastSeen: now,
      firstSeen: existing?.firstSeen || now,
      unattendedEnabled: info.unattendedEnabled ?? existing?.unattendedEnabled ?? false,
      unattendedPasswordHash: info.unattendedPasswordHash || existing?.unattendedPasswordHash || '',
      hwInfo: info.hwInfo || existing?.hwInfo || null,
    };

    this.devices.set(agentId, record);
    this.save();
    return record;
  }

  getDeviceList(onlineAgentIds) {
    const result = [];
    for (const [agentId, device] of this.devices) {
      result.push({
        ...device,
        isOnline: onlineAgentIds.has(agentId),
      });
    }
    // Online zařízení první, pak podle lastSeen
    result.sort((a, b) => {
      if (a.isOnline !== b.isOnline) return b.isOnline ? 1 : -1;
      return new Date(b.lastSeen) - new Date(a.lastSeen);
    });
    return result;
  }

  removeDevice(agentId) {
    this.devices.delete(agentId);
    this.save();
  }

  getDevice(agentId) {
    return this.devices.get(agentId) || null;
  }
}

module.exports = DeviceRegistry;
