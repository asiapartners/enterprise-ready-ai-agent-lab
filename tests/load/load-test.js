/**
 * k6 Load Test — openclaw-agent365
 *
 * Performance target: p95 < 3 seconds, error rate < 1%
 *
 * Run locally:
 *   BASE_URL=https://your-staging-url k6 run tests/load/load-test.js
 *
 * Run via CI (staging):
 *   k6 run --env BASE_URL=$STAGING_URL tests/load/load-test.js
 *
 * Install k6: https://k6.io/docs/get-started/installation/
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// ─── Custom Metrics ───────────────────────────────────────────────────────────
const healthLatency    = new Trend('health_latency_ms',    true);
const healthErrors     = new Counter('health_errors');
const errorRate        = new Rate('error_rate');

// ─── Test Configuration ───────────────────────────────────────────────────────
export const options = {
  stages: [
    { duration: '30s', target: 10  },  // Warm-up ramp
    { duration: '2m',  target: 50  },  // Sustained load (50 VUs)
    { duration: '30s', target: 100 },  // Spike test
    { duration: '1m',  target: 50  },  // Back to sustained
    { duration: '30s', target: 0   },  // Ramp-down
  ],
  thresholds: {
    // Performance contract: p95 < 3s on health endpoint
    'health_latency_ms': [
      { threshold: 'p(95)<3000', abortOnFail: false },
      { threshold: 'p(99)<5000', abortOnFail: false },
    ],
    // Error rate must stay below 1%
    'error_rate': [{ threshold: 'rate<0.01', abortOnFail: true }],
    // Standard k6 HTTP error rate
    'http_req_failed': [{ threshold: 'rate<0.01', abortOnFail: true }],
    // Overall http duration
    'http_req_duration': ['p(95)<3000'],
  },
};

// ─── Test Setup ───────────────────────────────────────────────────────────────
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3978';

export default function () {
  // Health endpoint — primary performance indicator
  const healthRes = http.get(`${BASE_URL}/health`, {
    headers: { 'Accept': 'application/json' },
    timeout: '10s',
  });

  const healthOk = check(healthRes, {
    'health status 200':        (r) => r.status === 200,
    'health body has status ok': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.status === 'ok';
      } catch {
        return false;
      }
    },
    'health response time < 3s': (r) => r.timings.duration < 3000,
  });

  healthLatency.add(healthRes.timings.duration);

  if (!healthOk || healthRes.status !== 200) {
    healthErrors.add(1);
    errorRate.add(1);
  } else {
    errorRate.add(0);
  }

  // Simulate realistic pacing between requests
  sleep(Math.random() * 2 + 0.5);  // 0.5–2.5s between iterations
}

// ─── Teardown: Print summary ──────────────────────────────────────────────────
export function handleSummary(data) {
  const p95    = data.metrics?.health_latency_ms?.values?.['p(95)'] ?? 'N/A';
  const p99    = data.metrics?.health_latency_ms?.values?.['p(99)'] ?? 'N/A';
  const errors = data.metrics?.error_rate?.values?.rate ?? 'N/A';

  console.log('\n=== Load Test Summary ===');
  console.log(`Health endpoint p95:   ${typeof p95    === 'number' ? p95.toFixed(0)    : p95}ms`);
  console.log(`Health endpoint p99:   ${typeof p99    === 'number' ? p99.toFixed(0)    : p99}ms`);
  console.log(`Error rate:            ${typeof errors === 'number' ? (errors * 100).toFixed(2) : errors}%`);
  console.log(`Performance threshold: p95 < 3000ms — ${typeof p95 === 'number' && p95 < 3000 ? '✅ PASS' : '❌ FAIL'}`);
  console.log('========================\n');

  return {
    stdout: JSON.stringify(data, null, 2),
  };
}
