process.env.CORE_HEALTH_URL = 'http://core.test/health';
process.env.AUTH_HEALTH_URL = 'http://auth.test/health';
process.env.EXPORT_HEALTH_URL = 'http://export.test/health';

const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { app, checkService, services } = require('../src');

test('marks a service down when it times out or throws', async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => { throw new Error('offline'); };
  try {
    const result = await checkService({ name: 'test', url: 'http://test' });
    assert.equal(result.status, 'down');
    assert.equal(typeof result.latencyMs, 'number');
  } finally { global.fetch = originalFetch; }
});

test('marks only a valid JSON ok response as healthy', async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => ({ ok: true, headers: { get: () => 'application/json' }, json: async () => ({ status: 'ok' }) });
  try { assert.equal((await checkService({ name: 'test', url: 'http://test' })).status, 'up'); }
  finally { global.fetch = originalFetch; }
});

test('returns degraded status when one dependency is unavailable', async () => {
  const originalFetch = global.fetch;
  global.fetch = async (url) => ({ ok: !String(url).includes('auth'), headers: { get: () => 'application/json' }, json: async () => ({ status: String(url).includes('auth') ? 'down' : 'ok' }) });
  try {
    const response = await request(app).get('/services');
    assert.equal(response.status, 503);
    assert.equal(response.body.status, 'degraded');
    assert.equal(response.body.services.length, services.length);
  } finally { global.fetch = originalFetch; }
});
