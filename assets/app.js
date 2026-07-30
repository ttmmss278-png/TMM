const BIOSEQ_API = localStorage.getItem('bioseq_api') || 'http://127.0.0.1:8765';
const BIOSEQ_START_PROTOCOL = 'bioseq://start';
const BIOSEQ_MIN_ENGINE_VERSION = String(window.BIOSEQ_MIN_ENGINE_VERSION || '').trim();
const BIOSEQ_REQUIRE_WGS = Boolean(window.BIOSEQ_REQUIRE_WGS);
let BIOSEQ_CURRENT_PATH = 'uploads';
let BIOSEQ_ENGINE_ONLINE = false;
let BIOSEQ_ENGINE_STARTING = false;
let BIOSEQ_ENGINE_DATA = null;
let BIOSEQ_ENVIRONMENT_DATA = null;

function byId(id){ return document.getElementById(id); }

function escapeHtml(value=''){
  return String(value).replace(/[&<>"]/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[ch]));
}

function formatBytes(bytes){
  if(!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  const units=['B','KB','MB','GB'];
  const i=Math.min(Math.floor(Math.log(bytes)/Math.log(1024)), units.length-1);
  return `${(bytes/Math.pow(1024,i)).toFixed(i===0?0:1)} ${units[i]}`;
}

function compareVersions(left='',right=''){
  const a=String(left).split(/[.+-]/).map(value=>Number.parseInt(value,10)||0);
  const b=String(right).split(/[.+-]/).map(value=>Number.parseInt(value,10)||0);
  const length=Math.max(a.length,b.length);
  for(let index=0;index<length;index+=1){
    const delta=(a[index]||0)-(b[index]||0);
    if(delta!==0) return delta>0?1:-1;
  }
  return 0;
}

function engineVersionCompatible(data){
  if(!BIOSEQ_MIN_ENGINE_VERSION) return true;
  return compareVersions(data?.version||'0',BIOSEQ_MIN_ENGINE_VERSION)>=0;
}

function setEngineStatus(text,ok=false,options={}){
  BIOSEQ_ENGINE_ONLINE = ok;
  BIOSEQ_ENGINE_STARTING = Boolean(options.starting);
  const canStart=!ok&&!BIOSEQ_ENGINE_STARTING;
  const buttonLabel=options.buttonLabel||'启动/修复';
  document.querySelectorAll('[data-engine-status]').forEach(el => {
    el.innerHTML = `<span class="engine-dot ${ok?'online':BIOSEQ_ENGINE_STARTING?'starting':''}"></span><span class="engine-status-text">${escapeHtml(text)}</span>${canStart?`<button class="engine-start-btn" type="button" onclick="startBioSeqEngine(event)">${escapeHtml(buttonLabel)}</button>`:''}`;
  });
  const legacy=byId('engineStatus');
  if(legacy){
    legacy.textContent=text;
    legacy.style.color=ok?'#059669':'#dc2626';
  }
}

async function fetchJsonWithTimeout(url,timeoutMs=2500){
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),timeoutMs);
  try{
    const response=await fetch(url,{signal:controller.signal,cache:'no-store'});
    if(!response.ok) return null;
    return await response.json();
  }catch(error){
    return null;
  }finally{
    clearTimeout(timer);
  }
}

async function probeEngine(timeoutMs=2500){
  return fetchJsonWithTimeout(`${BIOSEQ_API}/status`,timeoutMs);
}

async function probeEnvironment(timeoutMs=8000){
  return fetchJsonWithTimeout(`${BIOSEQ_API}/environment`,timeoutMs);
}

async function inspectEngine(){
  const status=await probeEngine();
  BIOSEQ_ENGINE_DATA=status;
  BIOSEQ_ENVIRONMENT_DATA=null;
  if(!status) return {ready:false,reason:'offline',status:null,environment:null};
  if(!engineVersionCompatible(status)){
    return {ready:false,reason:'outdated',status,environment:null};
  }
  if(BIOSEQ_REQUIRE_WGS){
    const environment=await probeEnvironment();
    BIOSEQ_ENVIRONMENT_DATA=environment;
    if(!environment?.wgs?.ready){
      return {ready:false,reason:'wgs-unavailable',status,environment};
    }
    return {ready:true,reason:'ready',status,environment};
  }
  return {ready:true,reason:'ready',status,environment:null};
}

function describeInspection(inspection){
  const version=inspection?.status?.version||'未知';
  if(inspection.reason==='outdated'){
    return `引擎版本过旧 · v${version}，WGS 需要 v${BIOSEQ_MIN_ENGINE_VERSION}`;
  }
  if(inspection.reason==='wgs-unavailable'){
    const missing=inspection?.environment?.wgs?.missing_tools||['fastp','bwa','samtools'];
    return `WGS 环境未就绪 · 缺少 ${missing.join('、')}`;
  }
  if(inspection.reason==='ready'){
    const backend=inspection?.environment?.wgs?.backend;
    return `分析引擎已连接 · v${version}${backend?` · ${backend.toUpperCase()}`:''}`;
  }
  return '分析引擎未启动';
}

async function checkEngine(){
  setEngineStatus('正在检测本地分析引擎…',false,{starting:true});
  const inspection=await inspectEngine();
  if(inspection.ready){
    setEngineStatus(describeInspection(inspection),true);
    return true;
  }
  setEngineStatus(describeInspection(inspection),false,{buttonLabel:'升级/修复'});
  return false;
}

function invokeBioSeqProtocol(action='start'){
  const link=document.createElement('a');
  link.href=`bioseq://${action}`;
  link.style.display='none';
  link.setAttribute('aria-hidden','true');
  document.body.appendChild(link);
  link.click();
  setTimeout(()=>link.remove(),1500);
}

async function waitForEngine(maxAttempts=240,intervalMs=1500){
  for(let attempt=1;attempt<=maxAttempts;attempt+=1){
    const inspection=await inspectEngine();
    if(inspection.ready){
      setEngineStatus(describeInspection(inspection),true);
      return true;
    }
    const current=describeInspection(inspection);
    setEngineStatus(`正在修复分析环境… ${attempt}/${maxAttempts} · ${current}`,false,{starting:true});
    await new Promise(resolve=>setTimeout(resolve,intervalMs));
  }
  return false;
}

async function startBioSeqEngine(event){
  event?.preventDefault?.();
  event?.stopPropagation?.();
  if(BIOSEQ_ENGINE_STARTING) return false;

  const inspection=await inspectEngine();
  if(inspection.ready){
    setEngineStatus(describeInspection(inspection),true);
    return true;
  }

  setEngineStatus('正在调用本地一体化启动器…',false,{starting:true});
  invokeBioSeqProtocol(inspection.reason==='offline'?'start':'repair');
  const started=await waitForEngine();
  if(!started){
    setEngineStatus('修复未完成，请运行最新版 BioSeq Engine Manager BAT',false,{buttonLabel:'重试'});
  }
  return started;
}

function renderSelectedFiles(inputOrFiles,targetId){
  const files=inputOrFiles?.files ? Array.from(inputOrFiles.files) : Array.from(inputOrFiles||[]);
  const target=byId(targetId);
  if(!target) return files;
  if(!files.length){
    target.innerHTML='<div class="file-item"><strong>尚未选择文件</strong><span>—</span></div>';
    return files;
  }
  target.innerHTML=files.map(file=>`<div class="file-item"><strong title="${escapeHtml(file.name)}">${escapeHtml(file.name)}</strong><span>${formatBytes(file.size)}</span></div>`).join('');
  return files;
}

function setResult(boxId,message,type='info'){
  const box=byId(boxId)||document.querySelector('.result-box')||document.querySelector('.result');
  if(!box) return;
  box.classList?.add('result-box');
  const prefix=type==='error'?'错误：':type==='success'?'完成：':'';
  box.textContent=prefix+message;
}

async function parseResponse(response){
  const raw=await response.text();
  let data={};
  try{ data=raw?JSON.parse(raw):{}; }
  catch(error){ data={status:'error',message:raw||`请求失败（HTTP ${response.status}）`}; }
  if(!response.ok) throw new Error(data.message||data.log||`请求失败（HTTP ${response.status}）`);
  return data;
}

async function uploadNamedFiles(entries,boxId='resultLog'){
  const valid=(entries||[]).filter(item=>item&&item.file);
  if(!valid.length) throw new Error('请先选择需要上传的文件。');
  setResult(boxId,`正在上传 ${valid.length} 个文件…`);
  const form=new FormData();
  valid.forEach((item,index)=>form.append(item.key||`file_${index}`,item.file,item.file.name));
  try{
    const response=await fetch(`${BIOSEQ_API}/upload`,{method:'POST',body:form});
    const data=await parseResponse(response);
    BIOSEQ_CURRENT_PATH='uploads';
    setResult(boxId,`已上传 ${data.files?.length||0} 个文件。`,'success');
    return data.files||[];
  }catch(error){
    setResult(boxId,`${error.message}\n请先运行最新版 BioSeq Engine Manager。`,'error');
    throw error;
  }
}

async function uploadFiles(files,boxId='resultLog'){
  return uploadNamedFiles(Array.from(files||[]).map((file,index)=>({key:`file_${index}`,file})),boxId);
}

async function scanFiles(path='uploads',boxId='resultLog'){
  setResult(boxId,'正在识别项目文件…');
  try{
    const response=await fetch(`${BIOSEQ_API}/scan`,{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({path})
    });
    const data=await parseResponse(response);
    return data.files||{};
  }catch(error){
    setResult(boxId,error.message,'error');
    throw error;
  }
}

function resultFileUrl(path){
  return `${BIOSEQ_API}/file/${String(path).split('/').map(encodeURIComponent).join('/')}`;
}

function renderResultFiles(files,targetId,module){
  const target=byId(targetId);
  if(!target) return;
  if(!files?.length){
    target.innerHTML='<div class="notice info">分析成功，但当前结果目录中没有可预览文件。</div>';
    return;
  }
  const image=files.find(file=>/\.(png|jpe?g|webp)$/i.test(file));
  target.innerHTML=files.map(file=>{
    const name=String(file).split('/').pop();
    return `<div class="result-file"><span>${escapeHtml(name)}</span><a href="${resultFileUrl(file)}" target="_blank" rel="noopener">打开</a></div>`;
  }).join('')+(image?`<img class="preview-image" src="${resultFileUrl(image)}" alt="分析结果预览">`:'')+
    `<div class="action-row"><button class="btn secondary small" type="button" onclick="downloadResult('${escapeHtml(module)}')">下载全部结果</button></div>`;
}

async function refreshResults(module,targetId='resultFiles'){
  try{
    const response=await fetch(`${BIOSEQ_API}/result/${encodeURIComponent(module)}`,{cache:'no-store'});
    const data=await parseResponse(response);
    renderResultFiles(data.files||[],targetId,module);
    return data.files||[];
  }catch(error){
    const target=byId(targetId);
    if(target) target.innerHTML=`<div class="notice">暂时无法读取结果：${escapeHtml(error.message)}</div>`;
    return [];
  }
}

async function runAnalysis(module,payload={},boxId='resultLog',filesTargetId='resultFiles'){
  setResult(boxId,`正在运行 ${module} 分析，请保持本地服务开启…`);
  const filesTarget=byId(filesTargetId);
  if(filesTarget) filesTarget.innerHTML='';
  try{
    const response=await fetch(`${BIOSEQ_API}/run`,{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({module,path:payload.path||BIOSEQ_CURRENT_PATH,...payload})
    });
    const data=await parseResponse(response);
    const status=data.status||'unknown';
    const details=data.log||data.message||JSON.stringify(data,null,2);
    const success=status==='success';
    setResult(boxId,`状态：${status}\n${details}`,success?'success':'error');
    if(success){
      await refreshResults(module,filesTargetId);
    }else if(filesTarget){
      filesTarget.innerHTML='<div class="notice">任务执行失败，未生成新的结果文件。</div>';
    }
    return data;
  }catch(error){
    setResult(boxId,`${error.message}\n请检查引擎版本、WGS 工具和参考基因组状态。`,'error');
    if(filesTarget) filesTarget.innerHTML='<div class="notice">任务执行失败，未生成新的结果文件。</div>';
    throw error;
  }
}

function downloadResult(module){
  window.open(`${BIOSEQ_API}/download/${encodeURIComponent(module)}`,'_blank','noopener');
}

function clearModuleResult(logId='resultLog',filesId='resultFiles'){
  const log=byId(logId); if(log) log.textContent='等待提交分析任务。';
  const files=byId(filesId); if(files) files.innerHTML='';
}

document.addEventListener('DOMContentLoaded',()=>{
  checkEngine();
  document.querySelectorAll('[data-file-input]').forEach(input=>{
    const target=input.dataset.fileTarget;
    input.addEventListener('change',()=>renderSelectedFiles(input,target));
  });
});
