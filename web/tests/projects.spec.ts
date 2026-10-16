import {expect, test as base, type Page, type APIRequestContext} from '@playwright/test';
import {randomUUID, randomBytes} from 'node:crypto';
import {spawn, execFileSync} from 'node:child_process';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {createServer} from 'node:net';

// Real auth, migrations, importer/worker and project API, always in a disposable DB.
const test = base.extend<{}, {backend: string}>({
  backend: [async ({}, use) => {
    const directory = mkdtempSync(resolve(tmpdir(), 'neurotune-projects-'));
    const root = resolve('..');
    const python = process.env.NEUROTUNE_BACKEND_PYTHON ?? resolve(root, 'backend/.venv/bin/python');
    const env = {...process.env, DATABASE_URL:`sqlite:///${directory}/test.sqlite`,
      AUDIO_DATA_DIR:`${directory}/audio`, RAW_DATA_DIR:`${directory}/raw`,
      JWT_SECRET:randomBytes(32).toString('hex'), ENVIRONMENT:'development',
      CONTRACTS_PATH:resolve(root, 'contracts/default_experiment.json')};
    const options = {cwd:resolve(root, 'backend'), env};
    const socket = createServer();
    await new Promise<void>(done => socket.listen(0, '127.0.0.1', done));
    const port = (socket.address() as {port:number}).port;
    await new Promise<void>(done => socket.close(() => done()));
    const processes: ReturnType<typeof spawn>[] = [];
    try {
      execFileSync(python, ['-m', 'alembic', 'upgrade', 'head'], {...options, stdio:'pipe'});
      processes.push(spawn(python, ['-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', String(port)], {...options, stdio:'ignore'}));
      processes.push(spawn(python, ['-m', 'app.worker'], {...options, stdio:'ignore'}));
      const url = `http://127.0.0.1:${port}`;
      await expect.poll(async () => fetch(`${url}/v1/health`).then(r => r.ok).catch(() => false), {timeout:15000}).toBe(true);
      await use(url);
    } finally {
      await Promise.all(processes.map(child => new Promise<void>(done => {
        if(child.exitCode !== null) {done(); return;}
        child.once('exit', () => done()); child.kill('SIGTERM');
        const timer = setTimeout(() => child.kill('SIGKILL'), 5000); timer.unref();
        child.once('exit', () => clearTimeout(timer));
      })));
      rmSync(directory, {recursive:true, force:true});
    }
  }, {scope:'worker'}],
});

function wave(): Buffer {
  const frames = 48001;
  const bytes = Buffer.alloc(44 + frames * 4);
  bytes.write('RIFF'); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVEfmt ', 8);
  bytes.writeUInt32LE(16,16); bytes.writeUInt16LE(1,20); bytes.writeUInt16LE(2,22);
  bytes.writeUInt32LE(48000,24); bytes.writeUInt32LE(192000,28);
  bytes.writeUInt16LE(4,32); bytes.writeUInt16LE(16,34); bytes.write('data',36); bytes.writeUInt32LE(frames * 4,40);
  return bytes;
}
async function signIn(page:Page, email:string) {
  await page.getByLabel('Email', {exact:true}).fill(email);
  await page.getByLabel('Password', {exact:true}).fill('project-test-password');
  await page.getByRole('button', {name:'Sign in', exact:true}).click();
  await expect(page.getByRole('button', {name:'Sign out', exact:true})).toBeVisible();
}

test.beforeEach(async ({page, backend}) => {
  await page.route('**/v1/**', async route => {
    const url = new URL(route.request().url());
    await route.fulfill({response:await route.fetch({url:backend + url.pathname + url.search})});
  });
});

async function account(backend:string, request:APIRequestContext) {
  const email = `projects-${randomUUID()}@example.com`;
  const response = await request.post(`${backend}/v1/auth/register`, {data:{email, password:'project-test-password'}});
  expect(response.ok()).toBe(true);
  const tokens = await response.json();
  return {email, headers:{Authorization:`Bearer ${tokens.access_token}`}};
}
async function recording(backend:string, request:APIRequestContext, headers:Record<string,string>) {
  const uploaded = await request.post(`${backend}/v1/audio/assets`, {headers:{...headers,'X-Audio-Filename':'rain.wav','Content-Type':'application/octet-stream'}, data:wave()});
  expect(uploaded.status()).toBe(202);
  const asset = await uploaded.json();
  await expect.poll(async () => (await (await request.get(`${backend}/v1/audio/assets/${asset.id}`, {headers})).json()).status, {timeout:15000}).toBe('ready');
  return asset;
}
async function draft(page:Page) {
  await page.getByRole('button', {name:'Create project from rain.wav', exact:true}).click();
  await page.getByLabel('Project name', {exact:true}).fill('Rain project');
}

test('creates without rendering, autosaves and restores the exact source interval after new login', async ({page, request, backend}, info) => {
  const errors:string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {if(message.type()==='error' || message.type()==='warning') errors.push(message.text());});
  const owner = await account(backend, request);
  const asset = await recording(backend, request, owner.headers);
  const renderRequests:string[] = [];
  page.on('request', r => {if(r.method()==='POST' && /renders|profiles/.test(r.url())) renderRequests.push(r.url());});
  await page.goto('/editor/'); await signIn(page, owner.email); await draft(page);
  await page.getByLabel('Clip start (seconds)', {exact:true}).fill('0.125');
  await page.getByLabel('Clip end (seconds)', {exact:true}).fill('0.875');
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect(page.locator('#project-status')).toHaveText('Saved');
  const saved = (await (await request.get(`${backend}/v1/audio/projects`, {headers:owner.headers})).json()).items[0];
  expect(saved.recipe.sources[0]).toMatchObject({asset_id:asset.id, frame_count:48001});
  expect(saved.recipe.clips[0]).toMatchObject({start_frame:6000, end_frame:42000});
  expect(saved.recipe.frame_count).toBe(36000);
  await page.getByLabel('Project name', {exact:true}).fill('Rain revised');
  await expect(page.locator('#project-status')).toHaveText('Unsaved changes');
  await expect(page.locator('#project-status')).toHaveText('Saved');
  await page.getByRole('button', {name:'Sign out', exact:true}).click();
  await page.reload(); await signIn(page, owner.email);
  await page.getByRole('button', {name:'Open Rain revised', exact:true}).click();
  await expect(page.getByLabel('Project name', {exact:true})).toHaveValue('Rain revised');
  await expect(page.getByLabel('Clip start (seconds)', {exact:true})).toHaveValue('0.125');
  await expect(page.getByLabel('Clip end (seconds)', {exact:true})).toHaveValue('0.875');
  await expect(page.locator('#project-status')).toHaveText('Saved');
  expect(renderRequests).toEqual([]);
  expect(errors).toEqual([]);
  await page.screenshot({path:info.outputPath('project.png'), fullPage:true});
  for(const width of [320,768,1024,1440]) {
    await page.setViewportSize({width,height:900});
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  }
});

test('invalid trim stays unsaved and a project API error gives an actionable message', async ({page, request, backend}) => {
  const owner = await account(backend, request); await recording(backend, request, owner.headers);
  await page.goto('/editor/'); await signIn(page, owner.email); await draft(page);
  await page.getByLabel('Clip start (seconds)', {exact:true}).fill('0.9');
  await page.getByLabel('Clip end (seconds)', {exact:true}).fill('0.1');
  await expect(page.locator('#project-status')).toContainText('Choose a non-empty interval');
  await expect(page.getByRole('button', {name:'Save project', exact:true})).toBeDisabled();
  expect((await (await request.get(`${backend}/v1/audio/projects`, {headers:owner.headers})).json()).items).toEqual([]);
  let refuse=true;
  await page.route('**/v1/audio/projects', async route => {
    if(route.request().method()==='POST' && refuse) {
      refuse=false; await route.fulfill({status:422,json:{detail:{code:'INVALID_SOURCE',message:'Source is not ready. Choose a ready recording.'}}});
    } else await route.fallback();
  });
  await page.getByLabel('Clip start (seconds)', {exact:true}).fill('0');
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect(page.locator('#project-status')).toContainText('Source is not ready. Choose a ready recording.');
  await expect(page.getByLabel('Project name', {exact:true})).toHaveValue('Rain project');
  await page.getByLabel('Project name', {exact:true}).fill('Corrected project');
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect(page.locator('#project-status')).toHaveText('Saved');
  const saved=(await (await request.get(`${backend}/v1/audio/projects`, {headers:owner.headers})).json()).items;
  expect(saved).toHaveLength(1); expect(saved[0].name).toBe('Corrected project');
});

test('sign out clears an unsaved draft and a delayed save cannot repopulate another account', async ({page, request, backend}) => {
  const alice = await account(backend, request), bob = await account(backend, request);
  await recording(backend, request, alice.headers);
  let release!:()=>void;
  const held = new Promise<void>(done => {release=done;});
  let started = false;
  await page.route('**/v1/audio/projects', async route => {
    if(route.request().method()!=='POST') {await route.fallback(); return;}
    started=true; await held;
    await route.fallback();
  });
  await page.goto('/editor/'); await signIn(page, alice.email); await draft(page);
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect.poll(() => started).toBe(true);
  await expect(page.locator('#project-status')).toHaveText('Saving…');
  await page.getByRole('button', {name:'Sign out', exact:true}).click();
  await signIn(page, bob.email); release();
  await expect(page.getByText('No saved projects yet.', {exact:true})).toBeVisible();
  await expect(page.locator('#project-form')).toBeHidden();
  await expect(page.getByRole('button', {name:'Open Rain project', exact:true})).toHaveCount(0);
  expect(await page.evaluate(() => [localStorage.length, sessionStorage.length])).toEqual([0,0]);
});

test('retrying a lost save response preserves a subsequent edit without duplicate projects', async ({page, request, backend}) => {
  const owner = await account(backend, request); await recording(backend, request, owner.headers);
  const bodies:string[] = [];
  let loseResponse=true;
  await page.route('**/v1/audio/projects', async route => {
    if(route.request().method()!=='POST') {await route.fallback(); return;}
    bodies.push(route.request().postData()!);
    const response = await route.fetch({url:`${backend}/v1/audio/projects`});
    if(loseResponse) {loseResponse=false; await route.abort('failed');}
    else await route.fulfill({response});
  });
  await page.goto('/editor/'); await signIn(page, owner.email); await draft(page);
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect(page.locator('#project-status')).toContainText('Not saved.');
  await page.getByLabel('Project name', {exact:true}).fill('Retried and revised');
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect(page.locator('#project-status')).toHaveText('Saved');
  const projects = (await (await request.get(`${backend}/v1/audio/projects`, {headers:owner.headers})).json()).items;
  expect(projects).toHaveLength(1); expect(projects[0].name).toBe('Retried and revised');
  expect(bodies).toHaveLength(2); expect(bodies[0]).toBe(bodies[1]);
});

test('shows a revision conflict without overwriting the saved server project', async ({page, request, backend}) => {
  const owner = await account(backend, request); await recording(backend, request, owner.headers);
  await page.goto('/editor/'); await signIn(page, owner.email); await draft(page);
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect(page.locator('#project-status')).toHaveText('Saved');
  const saved = (await (await request.get(`${backend}/v1/audio/projects`, {headers:owner.headers})).json()).items[0];
  const response=await request.put(`${backend}/v1/audio/projects/${saved.id}`, {headers:owner.headers,
    data:{request_id:randomUUID(), expected_revision:saved.revision, name:'Other tab', recipe:saved.recipe, settings:saved.settings}});
  expect(response.ok()).toBe(true);
  await page.getByLabel('Project name', {exact:true}).fill('Local draft');
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect(page.locator('#project-status')).toContainText('A newer project revision has been saved.');
  await expect(page.getByLabel('Project name', {exact:true})).toHaveValue('Local draft');
  const current=await (await request.get(`${backend}/v1/audio/projects/${saved.id}`, {headers:owner.headers})).json();
  expect(current.name).toBe('Other tab'); expect(current.revision).toBe(2);
});

test('paginates project names safely and opens a project with the keyboard', async ({page, request, backend}) => {
  const owner = await account(backend, request); await recording(backend, request, owner.headers);
  await page.goto('/editor/'); await signIn(page, owner.email); await draft(page);
  await page.getByRole('button', {name:'Save project', exact:true}).click();
  await expect(page.locator('#project-status')).toHaveText('Saved');
  const saved=(await (await request.get(`${backend}/v1/audio/projects`, {headers:owner.headers})).json()).items[0];
  for(let index=0;index<20;index++) {
    const response=await request.post(`${backend}/v1/audio/projects`, {headers:owner.headers,
      data:{request_id:randomUUID(),project_id:randomUUID(),name:index===19?'<img src=x onerror=alert(1)>':`Project ${index}`,recipe:saved.recipe,settings:saved.settings}});
    expect(response.status()).toBe(201);
  }
  await page.getByRole('button', {name:'Close project', exact:true}).click();
  await page.getByRole('button', {name:'Refresh projects', exact:true}).click();
  await expect(page.locator('#project-list li')).toHaveCount(20);
  await expect(page.locator('#project-list img')).toHaveCount(0);
  await expect(page.getByText('<img src=x onerror=alert(1)> · revision 1', {exact:true})).toBeVisible();
  await page.getByRole('button', {name:'Load more projects', exact:true}).click();
  await expect(page.locator('#project-list li')).toHaveCount(21);
  const open=page.getByRole('button', {name:'Open Rain project', exact:true});
  await open.focus(); await page.keyboard.press('Enter');
  await expect(page.getByLabel('Project name', {exact:true})).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(page.getByLabel('Clip start (seconds)', {exact:true})).toBeFocused();
  await expect(page.locator('#project-status')).toHaveText('Saved');
});
