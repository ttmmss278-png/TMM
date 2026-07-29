const BIOSEQ_API='http://127.0.0.1:8765';

let BIOSEQ_CURRENT_PATH='uploads';

function setEngineStatus(text, ok=false){
 const el=document.getElementById('engineStatus');
 if(!el)return;
 el.innerHTML=text;
 el.style.color=ok?'#059669':'#dc2626';
}

async function checkEngine(){
 try{
  let r=await fetch(BIOSEQ_API+'/status');
  if(r.ok){
   setEngineStatus('● BioSeq Engine Connected',true);
   return;
  }
  throw new Error();
 }catch(e){
  setEngineStatus('○ BioSeq Engine Offline，请启动 BioSeq_Start.bat');
 }
}

checkEngine();

async function uploadFiles(files){
 const form=new FormData();
 for(const f of files){
  form.append('files',f);
 }
 const r=await fetch(BIOSEQ_API+'/upload',{method:'POST',body:form});
 const data=await r.json();
 if(data.files && data.files.length){
  BIOSEQ_CURRENT_PATH='uploads';
 }
 return data;
}

async function scanFiles(path='uploads'){
 const r=await fetch(BIOSEQ_API+'/scan',{
  method:'POST',
  headers:{'Content-Type':'application/json'},
  body:JSON.stringify({path:path})
 });
 return await r.json();
}

async function runAnalysis(module,path='uploads'){
 const box=document.querySelector('.result');
 if(box)box.innerHTML='⏳ 正在上传数据并运行分析...';
 try{
  let r=await fetch(BIOSEQ_API+'/run',{
   method:'POST',
   headers:{'Content-Type':'application/json'},
   body:JSON.stringify({module:module,path:path})
  });
  let d=await r.json();
  if(box){
   box.innerHTML='✅ 分析完成<br>状态：'+(d.status||'完成');
   if(d.output){
    box.innerHTML += '<br><a href="'+d.output+'" target="_blank">查看结果</a>';
   }
  }
  return d;
 }catch(e){
  if(box)box.innerHTML='❌ 无法连接 BioSeq Engine，请启动本地服务';
 }
}

async function runRNA(module){
 return runAnalysis(module,BIOSEQ_CURRENT_PATH);
}

async function runViolin(){
 return runAnalysis('violin',BIOSEQ_CURRENT_PATH);
}

async function runWGS(){
 return runAnalysis('wgs',BIOSEQ_CURRENT_PATH);
}

function downloadResult(module){
 window.open(BIOSEQ_API+'/download/'+encodeURIComponent(module));
}
