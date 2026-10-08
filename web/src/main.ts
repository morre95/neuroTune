import './style.css';

type Tokens = {access_token:string;refresh_token:string};
export type AudioAsset = {id:string;schema_version:number;filename:string;status:'pending'|'ready'|'failed';error:string|null;duration_seconds:number|null;checksum_sha256:string|null};
let tokens: Tokens | null = null;
let generation = 0;
type Refresh = { generation: number; promise: Promise<Tokens> };
let refreshing: Refresh | null = null;
let poll: number | undefined;
let previewUrl: string | null = null;
const app = document.querySelector<HTMLElement>('#app')!;

app.innerHTML = `<h1>Personal audio library</h1><p>Upload music or nature recordings for your meditation backgrounds.</p>
<form id="login"><label>Email<input name="email" type="email" autocomplete="username" required></label><label>Password<input name="password" type="password" autocomplete="current-password" minlength="8" required></label><button>Sign in</button></form>
<section id="library" hidden><button id="logout">Sign out</button><form id="upload"><label>Recording<input name="recording" type="file" accept=".wav,.mp3,.m4a,.aac,.flac" required></label><p>Mono or stereo WAV, MP3, M4A/AAC, or FLAC. Up to 100 MiB and ten minutes.</p><button>Upload recording</button></form><h2>Your recordings</h2><ul id="assets"></ul><audio controls hidden></audio></section><p id="message" role="status" aria-live="polite"></p>`;
const login = document.querySelector<HTMLFormElement>('#login')!;
const library = document.querySelector<HTMLElement>('#library')!;
const upload = document.querySelector<HTMLFormElement>('#upload')!;
const message = document.querySelector<HTMLElement>('#message')!;
const audio = document.querySelector<HTMLAudioElement>('audio')!;

function clearPreview() {
  audio.pause(); audio.removeAttribute('src'); audio.load(); audio.hidden=true;
  if(previewUrl) URL.revokeObjectURL(previewUrl);
  previewUrl=null;
}
function signedOut() {
  generation++; tokens=null; refreshing=null; clearTimeout(poll); clearPreview();
  login.hidden=false; library.hidden=true; document.querySelector('#assets')!.replaceChildren();
}
export async function api(path:string, init:RequestInit = {}):Promise<Response> {
  const current = tokens;
  const epoch = generation;
  const request = ()=>fetch(`/v1${path}`,{...init,headers:{...init.headers,Authorization:`Bearer ${tokens?.access_token}`}});
  let response=await request();
  if(generation!==epoch) throw new Error('Account changed.');
  if(response.status===401 && current) {
    if(!refreshing || refreshing.generation!==epoch) {
      const state: Refresh = {generation:epoch,promise:(async()=> {
      const refreshed=await fetch('/v1/auth/refresh',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({refresh_token:current.refresh_token})});
      if(!refreshed.ok) throw new Error('Please sign in again.');
      return await refreshed.json() as Tokens;
      })()};
      refreshing=state;
      state.promise=state.promise.finally(()=>{if(refreshing===state) refreshing=null;});
    }
    const state=refreshing;
    try {
      const pair=await state.promise;
      if(generation!==epoch) throw new Error('Account changed.');
      tokens=pair; response=await request();
    } catch(error) {if(generation===epoch) signedOut(); throw error;}
  }
  if(generation!==epoch) throw new Error('Account changed.');
  if(!response.ok) {
    const body=await response.json().catch(()=>({}));
    throw new Error(typeof body.detail==='string'?body.detail:`Request failed (${response.status}). Please try again.`);
  }
  return response;
}
async function refreshLibrary() {
  clearTimeout(poll);
  try {
    const epoch=generation;
    const assets:AudioAsset[]=await (await api('/audio/assets')).json();
    if(epoch!==generation) return;
    const list=document.querySelector('#assets')!;
    list.replaceChildren();
    for(const asset of assets) {
      const item=document.createElement('li');
      const name=document.createElement('strong'); name.textContent=asset.filename;
      const status=document.createElement('p'); status.textContent=asset.status==='failed'?asset.error:`${asset.status}${asset.duration_seconds ? ` · ${asset.duration_seconds.toFixed(1)} seconds`:''}`;
      const button=document.createElement('button'); button.textContent=`Preview ${asset.filename}`; button.disabled=asset.status!=='ready';
      button.onclick=async()=> {
        clearPreview(); button.disabled=true;
        try {
          // The click initiates audition; controls remain available if autoplay policy defers it.
          const epoch=generation;
          const response=await api(`/audio/assets/${asset.id}/download`);
          const blob=await response.blob();
          if(!tokens || epoch!==generation) return;
          previewUrl=URL.createObjectURL(blob); audio.src=previewUrl; audio.hidden=false;
          await audio.play().catch(()=>{message.textContent='Press Play to audition your recording.';});
        } catch(error) {message.textContent=(error as Error).message;}
        finally {button.disabled=false;}
      };
      item.append(name,status,button); list.append(item);
    }
    if(assets.some(asset=>asset.status==='pending')) poll=window.setTimeout(refreshLibrary,1500);
  } catch(error) {message.textContent=(error as Error).message;}
}
login.onsubmit=async event=> {
  event.preventDefault(); message.textContent='Signing in…';
  try {
    const data=new FormData(login);
    const response=await fetch('/v1/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:data.get('email'),password:data.get('password')})});
    if(!response.ok) throw new Error('Sign in failed. Check your email and password.');
    tokens=await response.json(); generation++; login.reset(); login.hidden=true; library.hidden=false; message.textContent='';
    await refreshLibrary();
  } catch(error) {message.textContent=(error as Error).message;}
};
upload.onsubmit=async event=> {
  event.preventDefault(); const file=(new FormData(upload)).get('recording') as File;
  if(!file || !file.size) {message.textContent='Choose a non-empty recording.';return;}
  if(file.size>100*1024*1024) {message.textContent='Recording must be no larger than 100 MiB.';return;}
  const button=upload.querySelector('button')!;button.disabled=true;message.textContent='Uploading recording…';
  try {
    await api('/audio/assets',{method:'POST',headers:{'X-Audio-Filename':encodeURIComponent(file.name),'Content-Type':'application/octet-stream'},body:file});
    upload.reset();message.textContent='Upload saved. Processing continues even if you close this page.';await refreshLibrary();
  } catch(error) {message.textContent=(error as Error).message;}
  finally {button.disabled=false;}
};
document.querySelector<HTMLButtonElement>('#logout')!.onclick=async()=> {
  const current=tokens;
  signedOut();message.textContent='Signed out.';
  if(current) await fetch('/v1/auth/logout',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${current.access_token}`},body:JSON.stringify({refresh_token:current.refresh_token})}).catch(()=>{});
};
