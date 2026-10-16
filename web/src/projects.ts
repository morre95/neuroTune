import type {AudioAsset} from './main';

type Source = {id:string;kind:'asset'|'profile_background';asset_id:string;frame_count:number;checksum_sha256:string;profile_version_id?:string};
type Clip = {id:string;source_id:string;start_frame:number;end_frame:number;gain:number;transition_after:{kind:'cut'|'crossfade';frames:number;curve?:'linear'}};
type Recipe = {schema_version:1;kind:'audio_sequence';sample_rate_hz:48000;channels:2;sample_width_bytes:2;sources:Source[];clips:Clip[];frame_count:number};
type Settings = {carrier_hz:number;tone_gain:number;background_gain:number;playback_policy:{mode:'fixed'|'selectable';default?:'full_file';minimum_minutes?:number;maximum_minutes?:number;step_minutes?:number}};
type Contents = {name:string;recipe:Recipe;settings:Settings};
type Project = Contents & {id:string;revision:number};
type Page = {items:Project[];next_cursor:string|null};
type Hooks = {api:(path:string,init?:RequestInit)=>Promise<Response>;generation:()=>number};
const RATE = 48000;

export function mountProjects(hooks:Hooks) {
  const section = document.createElement('section'); section.id='projects';
  section.innerHTML = `<h2>Editing projects</h2><p>Save a recording interval to your account. No rendering is needed.</p>
    <button type="button" id="refresh-projects">Refresh projects</button>
    <p id="project-list-status" role="status" aria-live="polite"></p><ul id="project-list"></ul>
    <button type="button" id="more-projects" hidden>Load more projects</button>
    <form id="project-form" hidden><h3>Project</h3>
      <fieldset><legend>Project details</legend>
      <label>Project name<input name="project-name" maxlength="120" required></label>
      <p id="project-source"></p>
      <label>Clip start (seconds)<input name="clip-start" type="number" min="0" step="any" required></label>
      <label>Clip end (seconds)<input name="clip-end" type="number" min="0" step="any" required></label>
      </fieldset><p id="project-length"></p>
      <p id="project-status" role="status" aria-live="polite"></p>
      <button type="submit">Save project</button> <button type="button" id="close-project">Close project</button>
    </form>`;
  document.querySelector('#library')!.append(section);
  const form = section.querySelector<HTMLFormElement>('#project-form')!;
  const fields = form.querySelector<HTMLFieldSetElement>('fieldset')!;
  const input = (name:string) => form.querySelector<HTMLInputElement>(`[name="${name}"]`)!;
  const name = input('project-name'), start = input('clip-start'), end = input('clip-end');
  const status = section.querySelector<HTMLElement>('#project-status')!;
  const listStatus = section.querySelector<HTMLElement>('#project-list-status')!;
  const list = section.querySelector<HTMLUListElement>('#project-list')!;
  const more = section.querySelector<HTMLButtonElement>('#more-projects')!;
  const saveButton = form.querySelector<HTMLButtonElement>('[type="submit"]')!;
  const close = section.querySelector<HTMLButtonElement>('#close-project')!;
  const refresh = section.querySelector<HTMLButtonElement>('#refresh-projects')!;
  let assets:AudioAsset[] = [], project:Project|null = null;
  let timer:number|undefined, dirty=false, saving=false, loading=false, version=0;
  let cursor:string|null = null, listVersion=0;
  let controller = new AbortController();
  // Keep the complete request for retries after a response might have been lost.
  let pending:{path:string;method:string;body:string}|null = null;

  function busyButtons() {
    fields.disabled=saving; close.disabled=saving;
    saveButton.disabled=saving || !dirty || !valid();
    for(const button of Array.from(list.querySelectorAll('button'))) button.disabled=saving || dirty || loading;
  }
  function valid() {
    if(!project) return false;
    end.setCustomValidity('');
    const source = project.recipe.sources.find(source => source.id===project!.recipe.clips[0]?.source_id);
    const a=Math.round(start.valueAsNumber*RATE), b=Math.round(end.valueAsNumber*RATE);
    if(!source || !Number.isSafeInteger(a) || !Number.isSafeInteger(b) || a<0 || b<=a || b>source.frame_count) {
      end.setCustomValidity('Choose a non-empty interval within the source recording.');
    }
    return !!name.value.trim() && form.checkValidity();
  }
  function resetEditor() {
    version++; clearTimeout(timer);
    project=null; pending=null; dirty=false; saving=false; loading=false;
    form.reset(); form.hidden=true; fields.disabled=false; status.textContent='';
    end.setCustomValidity('');
    section.querySelector('#project-source')!.textContent='';
    section.querySelector('#project-length')!.textContent=''; busyButtons();
  }
  function clear() {
    controller.abort(); controller=new AbortController(); listVersion++;
    refresh.disabled=more.disabled=false;
    resetEditor(); assets=[]; cursor=null; list.replaceChildren(); listStatus.textContent=''; more.hidden=true;
  }
  function updateAssets(current:AudioAsset[]) {assets=current;}
  function show(value:Project, saved:boolean) {
    project=value; form.hidden=false;
    name.value=value.name;
    const clip=value.recipe.clips[0];
    start.value=String(clip.start_frame/RATE); end.value=String(clip.end_frame/RATE);
    const source=value.recipe.sources.find(source => source.id===clip.source_id)!;
    const asset=assets.find(asset => asset.id===source.asset_id);
    section.querySelector('#project-source')!.textContent=`Source: ${asset?.filename??source.asset_id}`;
    start.max=end.max=String(source.frame_count/RATE);
    dirty=!saved; status.textContent=saved?'Saved':'Give the project a name to save it.';
    section.querySelector('#project-length')!.textContent=`Clip length: ${(clip.end_frame-clip.start_frame)/RATE} seconds`;
    busyButtons(); name.focus();
  }
  function choose(asset:AudioAsset) {
    if(dirty || saving || loading) {status.textContent='Save or close the current project before choosing another recording.'; return;}
    if(asset.status!=='ready' || !asset.duration_seconds || !asset.checksum_sha256) return;
    const frames=Math.round(asset.duration_seconds*RATE);
    if(frames<1 || frames>172800000) return;
    resetEditor();
    const source:Source={id:crypto.randomUUID(),kind:'asset',asset_id:asset.id,frame_count:frames,checksum_sha256:asset.checksum_sha256};
    show({id:crypto.randomUUID(),revision:0,name:'',
      recipe:{schema_version:1,kind:'audio_sequence',sample_rate_hz:48000,channels:2,sample_width_bytes:2,sources:[source],
        clips:[{id:crypto.randomUUID(),source_id:source.id,start_frame:0,end_frame:frames,gain:1,transition_after:{kind:'cut',frames:0}}],frame_count:frames},
      settings:{carrier_hz:220,tone_gain:0.1,background_gain:0.5,playback_policy:{mode:'fixed'}}},false);
    form.scrollIntoView({block:'nearest'});
  }
  function edited() {
    clearTimeout(timer); dirty=true;
    const correct=valid();
    status.textContent=correct?'Unsaved changes':end.validationMessage || 'Give the project a name to save it.';
    if(correct) {
      section.querySelector('#project-length')!.textContent=`Clip length: ${(Math.round(end.valueAsNumber*RATE)-Math.round(start.valueAsNumber*RATE))/RATE} seconds`;
      timer=window.setTimeout(() => void save(),1000);
    }
    busyButtons();
  }
  async function save() {
    clearTimeout(timer);
    if(!project || saving || !dirty || !valid()) return;
    const epoch=hooks.generation(), local=version;
    if(!pending) {
      const recipe=structuredClone(project.recipe), clip=recipe.clips[0];
      clip.start_frame=Math.round(start.valueAsNumber*RATE); clip.end_frame=Math.round(end.valueAsNumber*RATE);
      recipe.frame_count=clip.end_frame-clip.start_frame;
      const contents:Contents={name:name.value.trim(),recipe,settings:project.settings};
      pending={path:project.revision?`/audio/projects/${project.id}`:'/audio/projects',method:project.revision?'PUT':'POST',
        body:JSON.stringify({...contents,request_id:crypto.randomUUID(),...(project.revision?{expected_revision:project.revision}:{project_id:project.id})})};
    }
    let acknowledged=false;
    saving=true; status.textContent='Saving…'; busyButtons();
    try {
      const saved:Project=await (await hooks.api(pending.path,{method:pending.method,headers:{'Content-Type':'application/json'},body:pending.body,signal:controller.signal})).json();
      if(epoch!==hooks.generation() || local!==version) return;
      // A retry can acknowledge the earlier draft after the user has corrected it.
      const clip=saved.recipe.clips[0];
      dirty=name.value.trim()!==saved.name || Math.round(start.valueAsNumber*RATE)!==clip.start_frame || Math.round(end.valueAsNumber*RATE)!==clip.end_frame;
      acknowledged=true; project=saved; pending=null; status.textContent=dirty?'Unsaved changes':'Saved';
      if(!dirty) name.value=saved.name;
      await refreshList();
    } catch(error) {
      if(epoch!==hooks.generation() || local!==version) return;
      const failure=error as Error & {status?:number};
      if(failure.status && failure.status>=400 && failure.status<500 && failure.status!==409) pending=null;
      status.textContent=`Not saved. ${failure.message} Retry Save project. Close and reopen to load the server version if there is a conflict.`;
    } finally {
      if(epoch===hooks.generation() && local===version) {
        saving=false; busyButtons();
        if(acknowledged && dirty && valid()) timer=window.setTimeout(() => void save(),1000);
      }
    }
  }
  async function open(id:string) {
    if(dirty || saving || loading) return;
    const epoch=hooks.generation(), local=version;
    loading=true; busyButtons(); listStatus.textContent='Opening project…';
    try {
      const value:Project=await (await hooks.api(`/audio/projects/${id}`,{signal:controller.signal})).json();
      if(epoch!==hooks.generation() || local!==version) return;
      // This first slice edits one asset clip. Never flatten a later, richer project.
      if(value.recipe.clips.length!==1 || value.recipe.sources.find(s=>s.id===value.recipe.clips[0].source_id)?.kind!=='asset') {
        listStatus.textContent='This project needs the full timeline editor. Its saved contents have been preserved.'; return;
      }
      resetEditor(); show(value,true); listStatus.textContent='';
    } catch(error) {
      if(epoch===hooks.generation() && local===version) listStatus.textContent=(error as Error).message;
    } finally {if(epoch===hooks.generation() && local===version) {loading=false;busyButtons();}}
  }
  function appendProjects(items:Project[]) {
    for(const value of items) {
      const item=document.createElement('li'), label=document.createElement('p'), button=document.createElement('button');
      label.textContent=`${value.name} · revision ${value.revision}`;
      button.type='button'; button.textContent=`Open ${value.name}`; button.onclick=()=>void open(value.id);
      item.append(label,button); list.append(item);
    }
    busyButtons();
  }
  async function refreshList(append=false) {
    const epoch=hooks.generation(), local=++listVersion;
    refresh.disabled=more.disabled=true;
    listStatus.textContent='Loading projects…';
    try {
      const page:Page=await (await hooks.api(`/audio/projects${append && cursor?`?cursor=${encodeURIComponent(cursor)}`:''}`,{signal:controller.signal})).json();
      if(epoch!==hooks.generation() || local!==listVersion) return;
      if(!append) list.replaceChildren();
      appendProjects(page.items); cursor=page.next_cursor; more.hidden=!cursor;
      listStatus.textContent=list.children.length?'':'No saved projects yet.';
    } catch(error) {
      if(epoch===hooks.generation() && local===listVersion) listStatus.textContent=`Could not load projects. ${(error as Error).message} Use Refresh projects to retry.`;
    } finally {if(epoch===hooks.generation() && local===listVersion) refresh.disabled=more.disabled=false;}
  }
  form.oninput=edited;
  form.onsubmit=event=>{event.preventDefault();void save();};
  close.onclick=()=>{if(!dirty || window.confirm('Close this project and discard unsaved changes?')) resetEditor();};
  refresh.onclick=()=>void refreshList(); more.onclick=()=>void refreshList(true);
  return {choose,clear,updateAssets,refresh:refreshList};
}
