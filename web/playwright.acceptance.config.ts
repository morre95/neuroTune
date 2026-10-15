import {defineConfig} from '@playwright/test';

// Always start a disposable API/worker; never reuse a developer's backend.
export default defineConfig({
  testDir: './tests',
  testMatch: 'acceptance.spec.ts',
  workers: 1,
  timeout: 90_000,
  expect: {timeout: 20_000},
  use: {baseURL: 'http://127.0.0.1:18016', trace: 'retain-on-failure'},
  webServer: {
    command: 'python3 ../scripts/run-browser-acceptance-server.py',
    url: 'http://127.0.0.1:18016/v1/health',
    timeout: 60_000,
    reuseExistingServer: false,
  },
});
