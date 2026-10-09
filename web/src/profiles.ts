import type {AudioAsset} from './main';

type Track = {asset_id:string;trim_start_seconds:number;trim_end_seconds:number;gain:number;loop:boolean};
type Recipe = {schema_version:1;duration_seconds:number;tracks:Track[]};
export type AudioProfileVersion = {schema_version:1;id:string;owner_account_id:string;profile_id:string;version:number;name:string;background_asset_id:string;recipe:Recipe;carrier_hz:number;tone_gain:number;background_gain:number;loop:boolean;duration_seconds:number;checksum_sha256:string;normalization_factor:number};
type Render = {id:string;status:'pending'|'ready'|'failed';progress:number;error:string|null;recipe:Recipe};
type Hooks = {api:(path:string,init?:RequestInit)=>Promise<Response>;generation:()=>number;audition:(path:string)=>Promise<void>;message:(text:string)=>void};

export function mountProfiles(hooks:Hooks) {
  const container=document.createElement('section');container.id='profiles';
  container.innerHTML=`<h2>Your profiles</h2><ul id="profile-list"></ul>
  <form id="profile-editor" hidden><h2>Profile settings</h2>
  <label>Profile name<input name="name" required maxlength="120"></label>
  <div id="mix-tracks"></div><button type="button" id="add-track">Add track</button>
  <p>Balance up to four recordings. All tracks start together.</p>
  <label>Background duration (seconds)<input name="duration" type="number" min="30" max="600" step="1" value="600" required></label>
  <label>Carrier frequency (Hz)<input name="carrier" type="number" min="100" max="400" step="1" value="220" required></label>
  <label>Tone gain<input name="tone" type="number" min="0" max="0.95" step="any" value="0.2" required></label>
  <label>Background gain<input name="background" type="number" min="0" max="0.95" step="any" value="0.6" required></label>
  <label><input name="background-loop" type="checkbox" checked> Loop saved background during meditation</label>
  <p>Use stereo headphones. Frequency differences are assigned during meditation; this preview contains background only.</p>
  <button type="button" id="render-background">Render background</button>
  <p id="render-status" role="status"></p><button type="button" id="preview-background" disabled>Preview rendered background</button>
  <button id="save-profile" disabled>Save profile</button></form>`;
  document.querySelector('#library')!.append(container);
  const form=container.querySelector<HTMLFormElement>('form')!;
  const list=container.querySelector('#profile-list')!;
  const tracksContainer=container.querySelector<HTMLElement>('#mix-tracks')!;
  const addButton=container.querySelector<HTMLButtonElement>('#add-track')!;
  const renderButton=container.querySelector<HTMLButtonElement>('#render-background')!;
  const previewButton=container.querySelector<HTMLButtonElement>('#preview-background')!;
  const saveButton=container.querySelector<HTMLButtonElement>('#save-profile')!;
  const status=container.querySelector<HTMLElement>('#render-status')!;
  const input=(name:string)=>form.elements.namedItem(name) as HTMLInputElement;
  let assets:AudioAsset[]=[];
  let profileId:string|null=null;
  let render:Render|null=null;
  let timer:number|undefined;
  let revision=0;
  let settingsRevision=0;
  function invalidate() {revision++;clearTimeout(timer);render=null;saveButton.disabled=true;previewButton.disabled=true;status.textContent='';renderButton.disabled=false;}
  function trackFields(row:HTMLElement) {
    return {select:row.querySelector<HTMLSelectElement>('select')!,input:(name:string)=>row.querySelector<HTMLInputElement>(`[name="${name}"]`)!};
  }
  function populate(select:HTMLSelectElement, selected:string) {
    select.replaceChildren();
    for(const asset of assets) {const option=document.createElement('option');option.value=asset.id;option.textContent=asset.filename;select.append(option);}
    if(selected && !assets.some(asset=>asset.id===selected)) {const missing=document.createElement('option');missing.value=selected;missing.textContent='Recording unavailable — choose another source';missing.disabled=true;select.append(missing);}
    if(selected) select.value=selected;
  }
  function updateTrackButtons() {
    const rows=Array.from(tracksContainer.querySelectorAll<HTMLElement>('.mix-track'));
    addButton.disabled=rows.length>=4 || !assets.length;
    rows.forEach((row,index)=> {row.querySelector('legend')!.textContent=`Track ${index+1}`;row.querySelector<HTMLButtonElement>('button')!.disabled=rows.length===1;});
  }
  function appendTrack(track?:Track) {
    const row=document.createElement('fieldset');row.className='mix-track';
    row.innerHTML=`<legend></legend>
      <label>Source recording<select required aria-label="Source recording"></select></label>
      <label>Trim start (seconds)<input name="start" type="number" min="0" step="any" required></label>
      <label>Trim end (seconds)<input name="end" type="number" min="${1 / 48000}" step="any" required></label>
      <label>Track gain<input name="gain" type="number" min="0" max="4" step="any" required></label>
      <label><input name="track-loop" type="checkbox"> Loop source recording</label>
      <button type="button">Remove track</button>`;
    const fields=trackFields(row);
    const selected=track?.asset_id??assets[0]?.id??'';
    populate(fields.select,selected);
    fields.input('start').value=String(track?.trim_start_seconds??0);
    fields.input('end').value=String(track?.trim_end_seconds??assets.find(a=>a.id===selected)?.duration_seconds??0);
    fields.input('gain').value=String(track?.gain??1);
    fields.input('track-loop').checked=track?.loop??true;
    fields.select.onchange=()=> {invalidate();fields.input('start').value='0';fields.input('end').value=String(assets.find(a=>a.id===fields.select.value)?.duration_seconds??0);};
    row.oninput=invalidate;
    row.querySelector<HTMLButtonElement>('button')!.onclick=()=> {invalidate();row.remove();updateTrackButtons();};
    tracksContainer.append(row);updateTrackButtons();
  }
  addButton.onclick=()=> {invalidate();appendTrack();};
  function clear() {invalidate();profileId=null;assets=[];tracksContainer.replaceChildren();list.replaceChildren();form.reset();form.hidden=true;updateTrackButtons();}
  function choose(asset:AudioAsset) {
    invalidate();profileId=null;form.reset();form.hidden=false;tracksContainer.replaceChildren();
    appendTrack({asset_id:asset.id,trim_start_seconds:0,trim_end_seconds:asset.duration_seconds??0,gain:1,loop:true});saveButton.textContent='Save profile';
    form.scrollIntoView({behavior:'smooth',block:'start'});
  }
  function edit(version:AudioProfileVersion) {
    invalidate();profileId=version.profile_id;form.hidden=false;
    tracksContainer.replaceChildren();version.recipe.tracks.forEach(appendTrack);
    for(const [name,value] of Object.entries({name:version.name,duration:version.duration_seconds,carrier:version.carrier_hz,tone:version.tone_gain,background:version.background_gain})) input(name).value=String(value);
    input('background-loop').checked=version.loop;
    saveButton.textContent='Save new version';
  }
  async function refresh(currentAssets:AudioAsset[]) {
    assets=currentAssets.filter(asset=>asset.status==='ready');
    for(const select of Array.from(tracksContainer.querySelectorAll('select'))) populate(select,select.value);
    updateTrackButtons();
    const epoch=hooks.generation();
    const versions:AudioProfileVersion[]=await (await hooks.api('/audio/profiles')).json();
    if(epoch!==hooks.generation()) return;
    list.replaceChildren();
    for(const version of versions) {
      const item=document.createElement('li');const name=document.createElement('strong');name.textContent=`${version.name} · version ${version.version}`;
      const preview=document.createElement('button');preview.textContent=`Preview ${version.name} version ${version.version}`;
      preview.onclick=()=>hooks.audition(`/audio/profiles/versions/${version.id}/preview`).catch(error=>hooks.message(error.message));
      const button=document.createElement('button');button.textContent=`Edit ${version.name} version ${version.version}`;button.onclick=()=>edit(version);
      item.append(name,document.createElement('br'),preview,button);list.append(item);
    }
  }
  async function follow(renderId:string, epoch:number, currentRevision:number) {
    try {
      const next:Render=await (await hooks.api(`/audio/renders/${renderId}`)).json();
      if(epoch!==hooks.generation() || currentRevision!==revision) return;
      render=next;status.textContent=next.status==='failed'?next.error:`${next.status} · ${Math.round(next.progress*100)}%`;
      previewButton.disabled=saveButton.disabled=next.status!=='ready';renderButton.disabled=next.status==='pending';
      if(next.status==='pending') timer=window.setTimeout(()=>follow(renderId,epoch,currentRevision),1000);
    } catch(error) {if(epoch===hooks.generation() && currentRevision===revision) {status.textContent=(error as Error).message;renderButton.disabled=false;}}
  }
  input('duration').oninput=invalidate;
  const settingsChanged=()=>{settingsRevision++;saveButton.disabled=render?.status!=='ready';};
  for(const name of ['name','carrier','tone','background']) input(name).oninput=settingsChanged;
  input('background-loop').onchange=settingsChanged;
  renderButton.onclick=async()=> {
    if(!form.reportValidity()) return;
    invalidate();renderButton.disabled=true;
    const epoch=hooks.generation(), currentRevision=revision;
    const recipe:Recipe={schema_version:1,duration_seconds:Number(input('duration').value),tracks:Array.from(tracksContainer.querySelectorAll<HTMLElement>('.mix-track')).map(row=> {const fields=trackFields(row);return {asset_id:fields.select.value,trim_start_seconds:Number(fields.input('start').value),trim_end_seconds:Number(fields.input('end').value),gain:Number(fields.input('gain').value),loop:fields.input('track-loop').checked};})};
    try {
      const created:Render=await (await hooks.api('/audio/renders',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(recipe)})).json();
      if(epoch!==hooks.generation() || currentRevision!==revision) return;
      render=created;await follow(created.id,epoch,currentRevision);
    } catch(error) {if(epoch===hooks.generation() && currentRevision===revision) {status.textContent=(error as Error).message;renderButton.disabled=false;}}
  };
  previewButton.onclick=()=>{if(render?.status==='ready') hooks.audition(`/audio/renders/${render.id}/preview`).catch(error=>hooks.message(error.message));};
  form.onsubmit=async event=> {
    event.preventDefault();if(render?.status!=='ready') return;
    const body={name:input('name').value,render_id:render.id,carrier_hz:Number(input('carrier').value),tone_gain:Number(input('tone').value),background_gain:Number(input('background').value),loop:input('background-loop').checked};
    // Allow only binary addition error at the decimal boundary; the API compares exact decimal values.
    if(body.tone_gain+body.background_gain>.95+Number.EPSILON) {hooks.message('Tone and background gains must total at most 0.95.');return;}
    const epoch=hooks.generation(), currentRevision=revision, currentSettings=settingsRevision;
    const current=()=>epoch===hooks.generation() && currentRevision===revision && currentSettings===settingsRevision;
    saveButton.disabled=true;
    try {
      await hooks.api(profileId?`/audio/profiles/${profileId}/versions`:'/audio/profiles',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
      if(!current()) return;
      hooks.message('Profile version saved. Earlier versions remain available.');form.hidden=true;await refresh(assets);
    } catch(error) {if(current()) hooks.message((error as Error).message);}
    finally {if(current()) saveButton.disabled=render?.status!=='ready';}
  };
  return {refresh,clear,choose};
}
