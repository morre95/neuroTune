import {expect, test, type Browser, type Page} from '@playwright/test';
import {randomUUID} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {cpus, release} from 'node:os';

const rate = 48_000;
const windowFrames = 5 * rate;
const sourceFrames = 3_600 * rate;
const MiB = 1024 * 1024;

async function rendererRss(browser: Browser): Promise<number> {
  const session = await browser.newBrowserCDPSession();
  try {
    const {processInfo} = await session.send('SystemInfo.getProcessInfo');
    const renderers = processInfo.filter(process => process.type === 'renderer');
    expect(renderers.length).toBeGreaterThan(0);
    const sizes = await Promise.all(renderers.map(async process => {
      const status = await readFile(`/proc/${process.id}/status`, 'utf8');
      const rss = status.match(/^VmRSS:\s+(\d+) kB$/m);
      if (!rss) throw new Error('Linux renderer RSS could not be measured.');
      return Number(rss[1]) * 1024;
    }));
    return sizes.reduce((sum, size) => sum + size, 0);
  } finally {
    await session.detach();
  }
}

async function signIn(page: Page, email: string) {
  await page.getByLabel('Email', {exact: true}).fill(email);
  await page.getByLabel('Password', {exact: true}).fill('probe-password');
  await page.getByRole('button', {name: 'Sign in', exact: true}).click();
  await expect(page.getByRole('button', {name: 'Audition five seconds'})).toBeEnabled();
}

test('one-hour source is private and windows have strict byte/frame bounds', async ({request}) => {
  const account = async () => {
    const response = await request.post('/v1/auth/register', {
      data: {email: `probe-${randomUUID()}@example.com`, password: 'probe-password'},
    });
    expect(response.ok()).toBeTruthy();
    return {Authorization: `Bearer ${(await response.json()).access_token}`};
  };
  const headers = await account();
  const fixture = await request.post('/probe/fixture', {headers});
  expect(fixture.status()).toBe(200);
  const {id, frames, bytes} = await fixture.json();
  expect(frames).toBe(sourceFrames);
  expect(bytes).toBe(44 + sourceFrames * 4);
  const path = `/probe/audio/${id}/window?start_frame=${720 * rate}&frames=${windowFrames}`;
  const window = await request.get(path, {headers});
  expect(window.status()).toBe(200);
  expect(window.headers()['cache-control']).toBe('private, no-store');
  expect(window.headers()['content-type']).toContain('audio/wav');
  const data = await window.body();
  expect(data.length).toBe(44 + windowFrames * 4);
  expect(data.toString('ascii', 0, 4)).toBe('RIFF');
  expect(data.readUInt32LE(40)).toBe(windowFrames * 4);
  // At minute 12 the deterministic left channel is 280 Hz, not minute 0's 220 Hz.
  expect(data.readInt16LE(44 + 10 * 4)).toBeCloseTo(Math.round(8000 * Math.sin(2 * Math.PI * 280 * 10 / rate)), 0);
  expect((await request.get(path)).status()).toBe(401);
  const stranger = await account();
  expect((await request.get(path, {headers: stranger})).status()).toBe(404);
  expect((await request.get(`/probe/audio/${id}/peaks`, {headers: stranger})).status()).toBe(404);
  for (const query of ['start_frame=-1&frames=1', 'start_frame=0&frames=240001', 'start_frame=0&frames=0', `start_frame=${sourceFrames}&frames=1`]) {
    expect((await request.get(`/probe/audio/${id}/window?${query}`, {headers})).status()).toBe(422);
  }
  const last = await request.get(`/probe/audio/${id}/window?start_frame=${sourceFrames - 1}&frames=1`, {headers});
  expect((await last.body()).length).toBe(48);
  const peaks = await request.get(`/probe/audio/${id}/peaks`, {headers});
  expect((await peaks.body()).length).toBeLessThan(100_000);
  expect((await peaks.json()).peaks).toHaveLength(3_600);
});

test('real browser auditions late windows within a bounded memory and latency budget', async ({page, request, browser}, info) => {
  const email = `probe-${randomUUID()}@example.com`;
  await request.post('/v1/auth/register', {data: {email, password: 'probe-password'}});
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {if (['error', 'warning'].includes(message.type())) errors.push(message.text());});
  const sizes: number[] = [];
  page.on('response', response => {
    if (response.url().includes('/window?')) sizes.push(Number(response.headers()['content-length']));
  });
  await page.goto('/probe/');
  await signIn(page, email);
  const cdp = await page.context().newCDPSession(page);
  const baselineHeap = (await cdp.send('Runtime.getHeapUsage')).usedSize;
  const baselineRss = await rendererRss(browser);
  let peakHeap = baselineHeap;
  let peakRss = baselineRss;
  const latencies: number[] = [];
  for (const seconds of [0, 720, 1800, 3595, ...Array.from({length: 16}, (_, i) => 721 + i)]) {
    await page.getByLabel('Start (seconds)').fill(String(seconds));
    await page.getByRole('button', {name: 'Audition five seconds'}).click();
    const status = page.getByRole('status');
    await expect(status).toHaveAttribute('data-start-frame', String(seconds * rate));
    await expect(status).toHaveAttribute('data-context-state', 'running');
    await expect(status).toContainText('960044 bytes fetched');
    expect(Number(await status.getAttribute('data-decoded-frames'))).toBe(windowFrames);
    latencies.push(Number(await status.getAttribute('data-latency-ms')));
    peakHeap = Math.max(peakHeap, (await cdp.send('Runtime.getHeapUsage')).usedSize);
    peakRss = Math.max(peakRss, await rendererRss(browser));
  }
  expect(sizes).toHaveLength(20);
  expect(sizes.every(size => size === 44 + windowFrames * 4)).toBeTruthy();
  expect(Math.max(...latencies)).toBeLessThan(2_000);
  expect(peakHeap - baselineHeap).toBeLessThan(32 * MiB);
  expect(peakRss - baselineRss).toBeLessThan(128 * MiB);
  expect(errors).toEqual([]);
  const report = {
    browser: browser.version(), node: process.version, platform: process.platform,
    kernel: release(), cpu: cpus()[0].model, sourceFrames, sourceBytes: 44 + sourceFrames * 4,
    windowFrames, windowBytes: sizes[0], requests: sizes.length,
    maxClickToStartMs: Math.max(...latencies), baselineHeap, peakHeap, baselineRss, peakRss,
    budgets: {clickToStartMs: 2000, heapGrowthBytes: 32 * MiB, rendererRssGrowthBytes: 128 * MiB},
  };
  await writeFile(info.outputPath('metrics.json'), JSON.stringify(report, null, 2));
  await page.screenshot({path: info.outputPath('probe.png')});
  console.log(JSON.stringify(report));
  await cdp.detach();
});

test('new seek and account switch cannot start a stale in-flight window', async ({page, request}) => {
  const owner = `probe-${randomUUID()}@example.com`;
  const other = `probe-${randomUUID()}@example.com`;
  for (const email of [owner, other]) await request.post('/v1/auth/register', {data: {email, password: 'probe-password'}});
  await page.goto('/probe/');
  await signIn(page, owner);
  let unblock!: () => void;
  const gate = new Promise<void>(resolve => {unblock = resolve;});
  await page.route('**/window?**', async route => {
    await gate;
    await route.continue().catch(() => {}); // The earlier fetch can already be aborted.
  }, {times: 1});
  await page.getByLabel('Start (seconds)').fill('720');
  const pending = page.waitForRequest('**/window?**');
  await page.getByRole('button', {name: 'Audition five seconds'}).click();
  await pending;
  await page.getByLabel('Start (seconds)').fill('1800');
  await page.getByRole('button', {name: 'Audition five seconds'}).click();
  unblock();
  await expect(page.getByRole('status')).toHaveAttribute('data-start-frame', String(1800 * rate));
  let releaseOldAccount!: () => void;
  const oldAccountGate = new Promise<void>(resolve => {releaseOldAccount = resolve;});
  await page.route('**/window?**', async route => {
    await oldAccountGate;
    await route.continue().catch(() => {});
  }, {times: 1});
  const oldAccountRequest = page.waitForRequest('**/window?**');
  await page.getByLabel('Start (seconds)').fill('3595');
  await page.getByRole('button', {name: 'Audition five seconds'}).click();
  const oldRequest = await oldAccountRequest;
  await page.getByRole('button', {name: 'Sign out', exact: true}).click();
  await signIn(page, other);
  releaseOldAccount();
  await expect.poll(() => oldRequest.failure()).not.toBeNull();
  await expect(page.getByRole('status')).not.toHaveAttribute('data-start-frame');
  await expect(page.getByRole('status')).toContainText('Ready');
});
