import {expect, test} from '@playwright/test';
import {createHash, randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';

function wave(): Buffer {
  const frames = 4800;
  const data = Buffer.alloc(44 + frames * 4);
  data.write('RIFF'); data.writeUInt32LE(data.length - 8, 4); data.write('WAVEfmt ', 8);
  data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(2, 22);
  data.writeUInt32LE(48000, 24); data.writeUInt32LE(192000, 28);
  data.writeUInt16LE(4, 32); data.writeUInt16LE(16, 34); data.write('data', 36);
  data.writeUInt32LE(frames * 4, 40);
  for (let index = 0; index < frames; index++) {
    data.writeInt16LE(Math.round(2000 * Math.sin(index * Math.PI * 2 * 440 / 48000)), 44 + index * 4);
    data.writeInt16LE(Math.round(3000 * Math.sin(index * Math.PI * 2 * 660 / 48000)), 46 + index * 4);
  }
  return data;
}

function pcmData(wav: Buffer): Buffer {
  for (let offset = 12; offset + 8 <= wav.length;) {
    const size = wav.readUInt32LE(offset + 4);
    if (wav.toString('ascii', offset, offset + 4) === 'data') return wav.subarray(offset + 8, offset + 8 + size);
    offset += 8 + size + (size % 2);
  }
  throw new Error('The downloaded WAV has no PCM data chunk.');
}

test('real account uploads, mixes, auditions and versions a downloadable private profile', async ({page, request}) => {
  const email = `acceptance-${randomUUID()}@example.com`;
  const password = 'acceptance-password';
  const registered = await request.post('/v1/auth/register', {data: {email, password}});
  expect(registered.status()).toBe(200);
  const tokens = await registered.json();
  const headers = {Authorization: `Bearer ${tokens.access_token}`};
  const wav = wave();
  const flac = execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-f', 'wav', '-i', 'pipe:0', '-f', 'flac', 'pipe:1'], {input: wav});

  await page.goto('/editor/');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', {name: 'Sign in', exact: true}).click();
  for (const [name, buffer] of [['music.wav', wav], ['nature.flac', flac]] as const) {
    await page.getByLabel('Recording', {exact: true}).setInputFiles({name, mimeType: 'application/octet-stream', buffer});
    await page.getByRole('button', {name: 'Upload recording', exact: true}).click();
    await expect(page.getByRole('button', {name: `Create profile from ${name}`})).toBeEnabled();
  }
  await page.getByRole('button', {name: 'Create profile from music.wav'}).click();
  await page.getByLabel('Profile name').fill('Acceptance mix');
  await page.getByLabel('Background duration').fill('30');
  await page.getByRole('button', {name: 'Add track', exact: true}).click();
  const tracks = page.locator('.mix-track');
  const assets = await (await request.get('/v1/audio/assets', {headers})).json();
  const nature = assets.find((asset: {filename: string}) => asset.filename === 'nature.flac');
  await tracks.nth(1).getByLabel('Source recording', {exact: true}).selectOption(nature.id);
  await tracks.nth(1).getByLabel('Track gain').fill('0.5');
  await page.getByRole('button', {name: 'Render background', exact: true}).click();
  await expect(page.getByRole('button', {name: 'Preview rendered background'})).toBeEnabled();
  await page.getByRole('button', {name: 'Preview rendered background'}).click();
  await expect(page.locator('audio')).toBeVisible();
  await expect.poll(() => page.locator('audio').evaluate((audio: HTMLAudioElement) => audio.readyState)).toBeGreaterThanOrEqual(2);
  await page.getByRole('button', {name: 'Save profile', exact: true}).click();
  await expect(page.getByText('Acceptance mix · version 1', {exact: true})).toBeVisible();
  await page.getByRole('button', {name: 'Edit Acceptance mix version 1'}).click();
  await page.getByLabel('Profile name').fill('Acceptance revised');
  await page.getByLabel('Carrier frequency').fill('300');
  await page.getByRole('button', {name: 'Render background', exact: true}).click();
  await expect(page.getByRole('button', {name: 'Save new version'})).toBeEnabled();
  await page.getByRole('button', {name: 'Save new version'}).click();
  await expect(page.getByText('Acceptance revised · version 2', {exact: true})).toBeVisible();
  await expect(page.getByText('Acceptance mix · version 1', {exact: true})).toBeVisible();

  const profiles = await (await request.get('/v1/audio/profiles', {headers})).json();
  expect(profiles).toHaveLength(2);
  const original = profiles.find((profile: {version: number}) => profile.version === 1);
  const revised = profiles.find((profile: {version: number}) => profile.version === 2);
  expect(original.carrier_hz).toBe(220);
  expect(revised.carrier_hz).toBe(300);
  expect(original.recipe.tracks).toHaveLength(2);
  const downloaded = await request.get(`/v1/audio/profiles/versions/${original.id}/download`, {headers});
  expect(downloaded.status()).toBe(200);
  const bytes = await downloaded.body();
  expect(createHash('sha256').update(bytes).digest('hex')).toBe(original.checksum_sha256);
  expect(bytes.subarray(0, 4).toString()).toBe('RIFF');
  expect(original).toMatchObject({sample_rate_hz: 48000, channels: 2, sample_width_bytes: 2});
  const preview = await (await request.get(`/v1/audio/profiles/versions/${original.id}/preview`, {headers})).body();
  expect(pcmData(bytes).length).toBe(30 * 48000 * 4);
  // Container metadata can differ; the full 30-second PCM preview must agree.
  expect(createHash('sha256').update(pcmData(preview)).digest('hex')).toBe(createHash('sha256').update(pcmData(bytes)).digest('hex'));

  const stranger = await request.post('/v1/auth/register', {data: {email: `other-${randomUUID()}@example.com`, password}});
  const other = await stranger.json();
  expect((await request.get(`/v1/audio/profiles/versions/${original.id}/download`, {headers: {Authorization: `Bearer ${other.access_token}`}})).status()).toBe(404);
  await page.getByRole('button', {name: 'Sign out', exact: true}).click();
  await expect(page.getByRole('button', {name: 'Sign in', exact: true})).toBeVisible();
  await expect(page.getByText('Acceptance mix · version 1', {exact: true})).toBeHidden();
});
