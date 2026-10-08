import { test, expect } from '@playwright/test';

// HTTP is the system boundary. API/worker tests separately exercise real decoding.
test('sign in, upload, follow durable status, and explicitly preview', async ({page}) => {
  const asset = {id:'a1',filename:'rain.wav',status:'pending',error:null};
  let ready = false;
  await page.route('**/v1/auth/logout', route=>route.fulfill({json:{ok:true}}));
  await page.route('**/v1/auth/login', route=>route.fulfill({json:{access_token:'access',refresh_token:'refresh'}}));
  await page.route('**/v1/audio/assets', async route=> {
    if(route.request().method()==='POST') {ready=true; await route.fulfill({status:202,json:asset});}
    else await route.fulfill({json:ready?[{...asset,status:'ready'}]:[]});
  });
  const wav=Buffer.alloc(44+48000*4); wav.write('RIFF'); wav.writeUInt32LE(wav.length-8,4); wav.write('WAVEfmt ',8); wav.writeUInt32LE(16,16); wav.writeUInt16LE(1,20); wav.writeUInt16LE(2,22); wav.writeUInt32LE(48000,24); wav.writeUInt32LE(192000,28); wav.writeUInt16LE(4,32); wav.writeUInt16LE(16,34); wav.write('data',36); wav.writeUInt32LE(wav.length-44,40);
  await page.route('**/v1/audio/assets/a1/download', route=>route.fulfill({body:wav,contentType:'audio/wav'}));
  await page.goto('/editor/');
  await page.getByLabel('Email').fill('person@example.com');
  await page.getByLabel('Password').fill('correct-horse');
  await page.getByRole('button',{name:'Sign in',exact:true}).click();
  await page.getByLabel('Recording').setInputFiles({name:'rain.wav',mimeType:'audio/wav',buffer:Buffer.from('fixture')});
  await page.getByRole('button',{name:'Upload recording'}).click();
  await expect(page.getByText('rain.wav',{exact:true})).toBeVisible();
  await expect(page.getByRole('button',{name:'Preview rain.wav'})).toBeEnabled();
  await page.getByRole('button',{name:'Preview rain.wav'}).click();
  await expect(page.locator('audio')).toBeVisible();
  await expect.poll(()=>page.locator('audio').evaluate((element:HTMLAudioElement)=>element.currentTime)).toBeGreaterThan(0);
  await page.getByRole('button',{name:'Sign out'}).click();
  await expect(page.getByRole('button',{name:'Sign in',exact:true})).toBeVisible();
  expect(await page.evaluate(()=>[localStorage.length,sessionStorage.length])).toEqual([0,0]);
});

test('failed import displays a corrective action', async ({page})=> {
  await page.route('**/v1/auth/login',route=>route.fulfill({json:{access_token:'access',refresh_token:'refresh'}}));
  await page.route('**/v1/audio/assets',route=>route.fulfill({json:[{id:'broken',filename:'bad.wav',status:'failed',error:'Export a valid WAV and upload again.'}]}));
  await page.goto('/editor/');
  await page.getByLabel('Email').fill('person@example.com');
  await page.getByLabel('Password').fill('correct-horse');
  await page.getByRole('button',{name:'Sign in',exact:true}).click();
  await expect(page.getByText('Export a valid WAV and upload again.')).toBeVisible();
  await expect(page.getByRole('button',{name:'Preview bad.wav'})).toBeDisabled();
});

test('upload refusal is actionable without losing the signed in library', async ({page})=> {
  await page.route('**/v1/auth/login',route=>route.fulfill({json:{access_token:'access',refresh_token:'refresh'}}));
  await page.route('**/v1/audio/assets',route=>route.request().method()==='POST'?route.fulfill({status:400,json:{detail:'Choose a WAV, MP3, M4A/AAC, or FLAC recording.'}}):route.fulfill({json:[]}));
  await page.goto('/editor/');
  await page.getByLabel('Email').fill('person@example.com');await page.getByLabel('Password').fill('correct-horse');
  await page.getByRole('button',{name:'Sign in',exact:true}).click();
  await page.getByLabel('Recording').setInputFiles({name:'wrong.txt',mimeType:'text/plain',buffer:Buffer.from('text')});
  await page.getByRole('button',{name:'Upload recording'}).click();
  await expect(page.getByRole('status')).toHaveText('Choose a WAV, MP3, M4A/AAC, or FLAC recording.');
  await expect(page.getByRole('button',{name:'Upload recording'})).toBeEnabled();
});
