import {defineConfig} from '@playwright/test';

// Opt-in research probe. Never reuse a developer's backend or browser profile.
export default defineConfig({
  testDir: './tests',
  testMatch: 'audio-delivery-probe.spec.ts',
  outputDir: './playwright-report/audio-probe',
  workers: 1,
  timeout: 60_000,
  expect: {timeout: 10_000},
  use: {
    browserName: 'chromium',
    baseURL: 'http://127.0.0.1:18021',
    trace: 'off',
  },
  webServer: {
    command: 'python3 ../scripts/probe-editor-audio.py',
    url: 'http://127.0.0.1:18021/v1/health',
    timeout: 60_000,
    reuseExistingServer: false,
    gracefulShutdown: {signal: 'SIGTERM', timeout: 5_000},
  },
});
