import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate   = new Rate('errors');
const shortenTrend = new Trend('shorten_duration');
const redirectTrend = new Trend('redirect_duration');

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
  stages: [
    { duration: '30s', target: 10  },  // ramp up
    { duration: '1m',  target: 50  },  // stay at 50
    { duration: '2m',  target: 100 },  // peak load
    { duration: '30s', target: 0   },  // ramp down
  ],
  thresholds: {
    http_req_duration:  ['p(95)<500'],  // 95% under 500ms
    http_req_failed:    ['rate<0.01'],  // less than 1% errors
    errors:             ['rate<0.01'],
  },
};

// Pre-created short codes for redirect testing
const shortCodes = [];

export function setup() {
  // Create 10 URLs to use during the test
  for (let i = 0; i < 10; i++) {
    const res = http.post(
      `${BASE_URL}/shorten`,
      JSON.stringify({ url: `https://example.com/page-${i}` }),
      { headers: { 'Content-Type': 'application/json' } }
    );
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      shortCodes.push(body.short_code);
    }
  }
  return { shortCodes };
}

export default function (data) {
  const codes = data.shortCodes;

  // 30% shorten new URLs
  if (Math.random() < 0.3) {
    const start = Date.now();
    const res = http.post(
      `${BASE_URL}/shorten`,
      JSON.stringify({ url: `https://example.com/load-test-${Date.now()}` }),
      { headers: { 'Content-Type': 'application/json' } }
    );
    shortenTrend.add(Date.now() - start);
    check(res, { 'shorten 200': (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
  }

  // 60% redirect existing URLs
  if (Math.random() < 0.6 && codes.length > 0) {
    const code = codes[Math.floor(Math.random() * codes.length)];
    const start = Date.now();
    const res = http.get(`${BASE_URL}/r/${code}`, {
      redirects: 0, // don't follow redirect
    });
    redirectTrend.add(Date.now() - start);
    check(res, { 'redirect 302': (r) => r.status === 302 });
    errorRate.add(res.status !== 302);
  }

  // 10% health checks
  if (Math.random() < 0.1) {
    const res = http.get(`${BASE_URL}/health`);
    check(res, { 'health 200': (r) => r.status === 200 });
  }

  sleep(Math.random() * 2);
}

export function handleSummary(data) {
  return {
    'load-test/results.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}

function textSummary(data, opts) {
  return `
=== Load Test Summary ===
Total requests:     ${data.metrics.http_reqs.values.count}
Failed requests:    ${data.metrics.http_req_failed.values.passes}
p50 latency:        ${Math.round(data.metrics.http_req_duration.values['p(50)'])}ms
p95 latency:        ${Math.round(data.metrics.http_req_duration.values['p(95)'])}ms
p99 latency:        ${Math.round(data.metrics.http_req_duration.values['p(99)'])}ms
Shorten p95:        ${Math.round(data.metrics.shorten_duration?.values?.['p(95)'] || 0)}ms
Redirect p95:       ${Math.round(data.metrics.redirect_duration?.values?.['p(95)'] || 0)}ms
`;
}