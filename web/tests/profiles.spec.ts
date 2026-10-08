import {test, expect} from '@playwright/test';

test('render, audition, save, and revise a named profile without replacing its earlier version', async ({page})=> {
  const recipe={schema_version:1,duration_seconds:45,tracks:[{asset_id:'a1',trim_start_seconds:0,trim_end_seconds:10,gain:1,loop:true}]};
  const versions:any[]=[];
  const render={id:'r1',status:'ready',progress:1,recipe,normalization_factor:1};
  await page.route('**/v1/auth/login',route=>route.fulfill({json:{access_token:'access',refresh_token:'refresh'}}));
  await page.route('**/v1/audio/assets',route=>route.fulfill({json:[{id:'a1',filename:'rain.wav',status:'ready',duration_seconds:10}]}));
  await page.route('**/v1/audio/renders',async route=> {
    expect(route.request().postDataJSON()).toEqual(recipe);
    await route.fulfill({status:202,json:render});
  });
  await page.route('**/v1/audio/renders/r1',route=>route.fulfill({json:render}));
  await page.route('**/v1/audio/renders/r1/preview',route=>route.fulfill({contentType:'audio/wav',body:Buffer.alloc(44)}));
  await page.route('**/v1/audio/profiles**',async route=> {
    if(route.request().method()==='GET') await route.fulfill({json:versions});
    else {
      const data=route.request().postDataJSON();
      const version={...data,id:`v${versions.length+1}`,profile_id:'p1',version:versions.length+1,recipe,background_asset_id:'r1',duration_seconds:45};
      versions.unshift(version); await route.fulfill({status:201,json:version});
    }
  });
  await page.goto('/editor/');
  await page.getByLabel('Email').fill('person@example.com');await page.getByLabel('Password').fill('correct-horse');
  await page.getByRole('button',{name:'Sign in',exact:true}).click();
  await page.getByRole('button',{name:'Create profile from rain.wav'}).click();
  await page.getByLabel('Profile name').fill('Rain');
  await page.getByLabel('Background duration').fill('45');
  await page.getByRole('button',{name:'Render background',exact:true}).click();
  await expect(page.getByRole('button',{name:'Preview rendered background'})).toBeEnabled();
  await page.getByRole('button',{name:'Preview rendered background'}).click();
  await expect(page.locator('audio')).toBeVisible();
  await page.getByRole('button',{name:'Save profile',exact:true}).click();
  await expect(page.getByText('Rain · version 1',{exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Edit Rain version 1'}).click();
  await page.getByLabel('Profile name').fill('Soft rain');
  await page.getByLabel('Carrier frequency').fill('300');
  await page.getByRole('button',{name:'Render background',exact:true}).click();
  await expect(page.getByRole('button',{name:'Save new version'})).toBeEnabled();
  await page.getByRole('button',{name:'Save new version'}).click();
  await expect(page.getByText('Soft rain · version 2',{exact:true})).toBeVisible();
  await expect(page.getByText('Rain · version 1',{exact:true})).toBeVisible();
  expect(versions[1].carrier_hz).toBe(220);
  expect(versions[0].carrier_hz).toBe(300);
});
