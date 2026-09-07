import pw from 'playwright';
const b=await pw.chromium.launch();
import fs from 'fs';
const hooked=fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_pm.html','<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+hooked+'</body></html>');
const pg=await (await b.newContext({viewport:{width:360,height:780}})).newPage();
await pg.goto(new URL('_pm.html', import.meta.url).href); await pg.waitForTimeout(400);
const offices=await pg.evaluate(()=>window.__ROLE_KEYS);
const small={},tiny={}; let ov=0,n=0;
for(const [role,srole] of [['student',null],['applicant',null],...offices.map(o=>['staff',o])]){
  await pg.evaluate(({role,srole})=>{
    const o=document.createElement('button');o.setAttribute('data-go','logout');document.body.appendChild(o);o.click();o.remove();
    if(srole){const s=document.querySelector('#office');if(s)s.value=srole;}
    document.querySelector(`[data-role="${role}"]`).click();},{role,srole});
  const routes=await pg.evaluate(()=>Object.keys(window.__SCREENS));
  for(const rt of routes){
    const r=await pg.evaluate(rt=>{
      const n=document.createElement('button');n.setAttribute('data-go',rt);document.body.appendChild(n);n.click();n.remove();
      const small=[],tiny=[];
      document.querySelectorAll('button,a,select,input,[role="button"]').forEach(e=>{
        const b=e.getBoundingClientRect(); if(!b.height) return;
        if(b.height<44) small.push(e.tagName+'.'+(e.className||'-')+' h'+Math.round(b.height));});
      document.querySelectorAll('.content *, .nav *, .topbar *').forEach(e=>{
        if(!e.childNodes.length||![...e.childNodes].some(x=>x.nodeType===3&&x.textContent.trim()))return;
        const cs=getComputedStyle(e);
        if(cs.display==='none'||cs.visibility==='hidden'||!e.getClientRects().length)return;
        const f=parseFloat(cs.fontSize);
        if(f<11.5) tiny.push(e.tagName+'.'+(e.className||'-')+' @'+f);});
      return {small,tiny,ov:document.documentElement.scrollWidth-document.documentElement.clientWidth};},rt);
    n++;
    r.small.forEach(k=>small[k]=(small[k]||0)+1);
    r.tiny.forEach(k=>tiny[k]=(tiny[k]||0)+1);
    if(r.ov>2){console.log('OVERFLOW',srole||role,rt,r.ov);ov++;}
  }
}
const p=(t,o)=>{const k=Object.keys(o);console.log(t+':',k.length?'':'none');
  k.sort((a,b)=>o[b]-o[a]).slice(0,14).forEach(x=>console.log('  ',String(o[x]).padStart(4),x));};
p('touch targets under 44px',small); p('text under 11.5px',tiny);
console.log(n+' screen loads, horizontal overflow:',ov);
await b.close();
