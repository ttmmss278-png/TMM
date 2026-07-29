const BIOSEQ_API='http://127.0.0.1:8765';
async function checkEngine(){
 const el=document.getElementById('engineStatus');
 if(!el)return;
 try{await fetch(BIOSEQ_API+'/status');el.innerHTML='● BioSeq Engine Connected';}
 catch(e){el.innerHTML='○ BioSeq Engine Offline';}
}
checkEngine();
async function runAnalysis(module,path){
 const box=document.querySelector('.result');
 if(box)box.innerHTML='分析运行中...';
 try{
 let r=await fetch(BIOSEQ_API+'/run',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({module,path})});
 let d=await r.json();
 if(box)box.innerHTML='状态：'+d.status;
 }catch(e){if(box)box.innerHTML='请启动本地BioSeq服务';}
}