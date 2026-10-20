require('dotenv').config();

const express = require('express');

const app = express();
app.disable('x-powered-by');

const timeoutMs = Number(process.env.HEALTH_TIMEOUT_MS || 2500);
const services = [
  { name: 'loxecutivo-core', url: process.env.CORE_HEALTH_URL || 'http://127.0.0.1:8081/health' },
  { name: 'loxecutivo-auth', url: process.env.AUTH_HEALTH_URL || 'http://127.0.0.1:8082/health' },
  { name: 'loxecutivo-export', url: process.env.EXPORT_HEALTH_URL || 'http://127.0.0.1:8083/health' },
];

async function checkService(service) {
  const startedAt = Date.now();
  try {
    const response = await fetch(service.url, { signal: AbortSignal.timeout(timeoutMs) });
    const body = response.headers.get('content-type')?.includes('application/json')
      ? await response.json()
      : null;
    const healthy = response.ok && body?.status === 'ok';
    return {
      name: service.name,
      status: healthy ? 'up' : 'down',
      latencyMs: Date.now() - startedAt,
    };
  } catch {
    return {
      name: service.name,
      status: 'down',
      latencyMs: Date.now() - startedAt,
    };
  }
}

app.get('/health', (_request, response) => {
  response.json({ status: 'ok', service: 'loxecutivo-health' });
});

app.get('/services', async (_request, response) => {
  const checks = await Promise.all(services.map(checkService));
  const healthy = checks.every((service) => service.status === 'up');
  response.status(healthy ? 200 : 503).json({
    status: healthy ? 'ok' : 'degraded',
    checkedAt: new Date().toISOString(),
    services: checks,
  });
});

if (require.main === module) {
  const port = Number(process.env.PORT || 8084);
  const host = process.env.HOST || '127.0.0.1';
  app.listen(port, host, () => console.log(`Loxecutivo Health escutando em ${host}:${port}`));
}

module.exports = { app, checkService, services };
