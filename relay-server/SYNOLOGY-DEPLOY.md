# ServiDesk Relay Server – Nasazení na Synology NAS

## Přehled

```
Internet → router:443 → Synology:443 (reverse proxy + TLS) → Docker:8090 (relay server)
```

Doména: `your-relay-domain.example.com`

---

## Krok 1: DNS záznam

U správce domény servigo.cz vytvořit A záznam:

```
Typ:    A
Název:  remote
Hodnota: <veřejná IP adresa tvého NAS / routeru>
TTL:    300
```

Pokud máš dynamickou IP, použij DDNS:
- Synology DSM → Control Panel → External Access → DDNS
- Nebo nastav CNAME na DDNS hostname

**Ověření:** `nslookup your-relay-domain.example.com` by měl vrátit tvoji veřejnou IP.

---

## Krok 2: Port forwarding na routeru

Na routeru přesměrovat:

| Protokol | Vnější port | Vnitřní IP      | Vnitřní port |
|----------|-------------|-----------------|--------------|
| TCP      | 443         | IP Synology NAS | 443          |

Port 80 je potřeba pro Let's Encrypt ověření:

| Protokol | Vnější port | Vnitřní IP      | Vnitřní port |
|----------|-------------|-----------------|--------------|
| TCP      | 80          | IP Synology NAS | 80           |

---

## Krok 3: Let's Encrypt certifikát

1. **DSM → Control Panel → Security → Certificate**
2. Klikni **Add**
3. Vyber **Add a new certificate** → **Get a certificate from Let's Encrypt**
4. Vyplň:
   - Domain name: `your-relay-domain.example.com`
   - Email: tvůj email
5. Klikni **Done**

Certifikát se automaticky obnovuje.

**Přiřazení certifikátu:**
1. V záložce **Certificate** klikni **Configure**
2. Pro službu `your-relay-domain.example.com` (reverse proxy) přiřaď nový certifikát

---

## Krok 4: Nahrát relay-server na NAS

### Varianta A: Přes File Station

1. Otevři **File Station**
2. Přejdi do sdíleného adresáře, např. `/docker/servidesk-relay/`
3. Nahraj celou složku `relay-server/` (kromě `node_modules/`)

### Varianta B: Přes SSH/SCP

```bash
scp -r relay-server/ user@synology-ip:/volume1/docker/servidesk-relay/
```

---

## Krok 5: Vytvořit .env na NAS

V `/volume1/docker/servidesk-relay/` vytvořit soubor `.env`:

```env
PORT=8090
HOST=0.0.0.0
ADMIN_TOKEN=CHANGE_ME_GENERATE_RANDOM_TOKEN
SESSION_TIMEOUT_MS=3600000
HEARTBEAT_INTERVAL_MS=10000
HEARTBEAT_TIMEOUT_MS=30000
MAX_PENDING_REQUESTS=50
MAX_ACTIVE_SESSIONS=10
MAX_MESSAGE_SIZE_BYTES=2097152
LOG_LEVEL=info
```

---

## Krok 6: Spustit Docker kontejner

### Přes Container Manager (GUI)

1. **Container Manager → Project**
2. Klikni **Create**
3. Název: `servidesk-relay`
4. Cesta: `/volume1/docker/servidesk-relay/`
5. Použij přiložený `docker-compose.yml`
6. Klikni **Build & Start**

### Přes SSH (CLI)

```bash
cd /volume1/docker/servidesk-relay/
docker compose up -d --build
```

**Ověření:**

```bash
# Healthcheck
curl http://localhost:8090/health

# Logy
docker logs servidesk-relay
```

---

## Krok 7: Reverse Proxy pro WSS

1. **DSM → Control Panel → Login Portal → Advanced → Reverse Proxy**
2. Klikni **Create**
3. Vyplň:

**General:**
| Pole              | Hodnota                  |
|--------------------|--------------------------|
| Description        | ServiDesk Relay          |
| Source Protocol     | HTTPS                    |
| Source Hostname     | your-relay-domain.example.com        |
| Source Port         | 443                      |
| Destination Protocol| HTTP                    |
| Destination Hostname| localhost                |
| Destination Port    | 8090                     |

4. Přejdi na záložku **Custom Header**
5. Klikni **Create → WebSocket**
   - Tím se automaticky přidají:
     - `Upgrade: $http_upgrade`
     - `Connection: "Upgrade"`

6. Klikni **Save**

**DŮLEŽITÉ:** Záložka Custom Header → WebSocket je klíčová! Bez ní WebSocket spojení nefunguje.

---

## Krok 8: Firewall na Synology

1. **DSM → Control Panel → Security → Firewall**
2. Klikni **Edit Rules**
3. Přidej pravidla:

| Port | Protokol | Zdroj        | Akce   |
|------|----------|--------------|--------|
| 443  | TCP      | Všechny      | Allow  |
| 80   | TCP      | Všechny      | Allow  |
| 8090 | TCP      | Pouze lokální| Deny z internetu |

---

## Krok 9: Ověření

### Health endpoint (z internetu)

```bash
curl https://your-relay-domain.example.com/health
```

Očekávaná odpověď:
```json
{
  "status": "ok",
  "uptime": 123,
  "connectedAgents": 0,
  "connectedAdmins": 0,
  "pendingRequests": 0,
  "activeSessions": 0
}
```

### WebSocket test

```bash
# Nainstaluj wscat: npm install -g wscat
wscat -c wss://your-relay-domain.example.com/ws
```

Po připojení pošli:
```json
{"type":"admin_auth","payload":{"admin_token":"CHANGE_ME_GENERATE_RANDOM_TOKEN","admin_name":"Test"}}
```

Měl bys dostat odpověď `admin_auth_result` s `success: true`.

---

## Řešení problémů

### WebSocket nefunguje (Error 400/502)
- Zkontroluj Custom Headers v Reverse Proxy (WebSocket hlavičky)
- Zkontroluj, že kontejner běží: `docker ps`

### Certifikát nefunguje
- Port 80 musí být otevřený pro Let's Encrypt ověření
- DNS musí ukazovat na správnou IP

### Kontejner neběží
```bash
docker logs servidesk-relay
docker compose down && docker compose up -d --build
```

### Timeout při připojení
- Zkontroluj port forwarding na routeru (443 → Synology)
- Zkontroluj firewall na Synology
