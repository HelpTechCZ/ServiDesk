const logger = require('./logger');

// Nastavení relay přeposílání binárních i JSON dat mezi agentem a viewerem
function setupRelay(sessionId, session) {
  const { agentWs, viewerWs } = session;

  // Agent → Viewer
  const agentMessageHandler = (data, isBinary) => {
    if (viewerWs.readyState === 1) {
      viewerWs.send(data, { binary: isBinary });
      session.lastActivity = Date.now();
    }
  };

  // Viewer → Agent
  const viewerMessageHandler = (data, isBinary) => {
    // Binární zprávy přeposílat přímo
    if (isBinary) {
      if (agentWs.readyState === 1) {
        agentWs.send(data, { binary: isBinary });
        session.lastActivity = Date.now();
      }
      return;
    }

    // JSON zprávy – parsovat pro řídící zprávy
    try {
      const msg = JSON.parse(data.toString());

      // Quality change – přeposlat agentovi
      if (msg.type === 'quality_change') {
        if (agentWs.readyState === 1) {
          agentWs.send(data, { binary: false });
          session.lastActivity = Date.now();
        }
        return;
      }

      // Session end – zpracuje se ve websocket-server.js
      if (msg.type === 'session_end') {
        return; // handled by main message handler
      }

      // Ostatní JSON zprávy přeposlat
      if (agentWs.readyState === 1) {
        agentWs.send(data, { binary: false });
        session.lastActivity = Date.now();
      }
    } catch {
      // Pokud není validní JSON, přeposlat jako binární
      if (agentWs.readyState === 1) {
        agentWs.send(data, { binary: true });
        session.lastActivity = Date.now();
      }
    }
  };

  // Uložit handlery pro pozdější cleanup
  session._agentMessageHandler = agentMessageHandler;
  session._viewerMessageHandler = viewerMessageHandler;

  agentWs.on('message', agentMessageHandler);
  viewerWs.on('message', viewerMessageHandler);

  logger.debug('Relay setup complete', { sessionId });
}

// Odebrání relay handlerů při ukončení session
function teardownRelay(session) {
  if (session._agentMessageHandler) {
    session.agentWs.removeListener('message', session._agentMessageHandler);
  }
  if (session._viewerMessageHandler) {
    session.viewerWs.removeListener('message', session._viewerMessageHandler);
  }
}

module.exports = { setupRelay, teardownRelay };
