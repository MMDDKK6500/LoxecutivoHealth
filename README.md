# Loxecutivo Health

Small internal monitor for the Core, Auth, and Export services. It binds to `127.0.0.1:8084`, so the probe endpoint is available to the VPS itself and is not exposed directly to the public network.

## Endpoints

- `GET /health` reports that the monitor process is running.
- `GET /services` probes Core, Auth, and Export and returns each service's `up` or `down` state and response time. It returns HTTP 503 when any dependency is unavailable.

The response intentionally omits internal URLs and error details.

## Local setup

```bash
cp .env.example .env
npm ci
npm start
```

Then query it locally:

```bash
curl http://127.0.0.1:8084/health
curl -i http://127.0.0.1:8084/services
```

## Install on the VPS

Clone this repository as `/home/ubuntu/loxecutivo/LoxecutivoHealth` and create its ignored `.env`. Replace `<health-repository-url>` with the GitHub URL configured for this repository:

```bash
git clone <health-repository-url> /home/ubuntu/loxecutivo/LoxecutivoHealth
cd /home/ubuntu/loxecutivo/LoxecutivoHealth
cp .env.example .env
nano .env
chmod 600 .env
sudo install -m 0755 deploy-loxecutivo.sh /home/ubuntu/loxecutivo/deploy.sh
cd /home/ubuntu/loxecutivo
bash ./deploy.sh
```

The deployment script pulls and builds all five repositories, restarts the existing Auth and Core services, starts Health with PM2, then waits up to one minute for all services to report healthy before it replaces the frontend files. It expects the Core systemd unit and Auth PM2 process (`2`) and Export PM2 process (`loxecutivo-export`) to already be configured.

The Health service does not need an NGINX location for the current setup. Keeping it on loopback avoids exposing infrastructure status publicly; administer it over SSH with the `curl` commands above.

## Core and Auth health endpoints

Core and Auth each expose a minimal unauthenticated `GET /health` response containing only `status` and `service`. These are probe endpoints; all application APIs keep their existing authentication behavior.
