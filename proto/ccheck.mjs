import pw from '/opt/node-tools/node_modules/playwright/index.js';
const { chromium } = pw;
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
import fs from 'fs';
const hooked=fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_cc.html','<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+hooked+'</body></html>');
const c=await b.newContext({viewport:{width:1440,height:900}});
const p=await c.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
await p.goto('file://'+process.cwd()+'/_cc.html'); await p.waitForTimeout(400);
const URL='https://claude.ai/code/artifact/5e0d3dc3-386f-4666-99d9-c08929569431';
let fails=0;
for (const office of ['academic','records','registrar','super']) {
  await p.evaluate(o=>{const x=document.createElement('button');x.setAttribute('data-go','logout');
    document.body.appendChild(x);x.click();x.remove();
    document.querySelector('[data-role="staff"]').click();
    const s=document.querySelector('#office'); s.value=o; s.dispatchEvent(new Event('change',{bubbles:true}));
    const g=document.createElement('button');g.setAttribute('data-go','signin');
    document.body.appendChild(g);g.click();g.remove();}, office);
  const inNav = await p.evaluate(()=>!!document.querySelector('.nav [data-go="t/college"]'));
  const r = await p.evaluate(()=>{const x=document.createElement('button');x.setAttribute('data-go','t/college');
    document.body.appendChild(x);x.click();x.remove();
    const app=document.querySelector('#app');
    const links=[...app.querySelectorAll('a[href]')].map(a=>a.getAttribute('href'));
    return {len:app.innerHTML.length, links};});
  const ok = inNav && r.len>2000 && r.links.filter(l=>l===URL).length>=2;
  console.log(`${office}: nav=${inNav} len=${r.len} chs-links=${r.links.filter(l=>l===URL).length} ${ok?'ok':'FAIL'}`);
  if(!ok) fails++;
}
// the structure screen link
await p.evaluate(()=>{const x=document.createElement('button');x.setAttribute('data-go','logout');
  document.body.appendChild(x);x.click();x.remove();
  document.querySelector('[data-role="staff"]').click();
  const s=document.querySelector('#office'); s.value='super'; s.dispatchEvent(new Event('change',{bubbles:true}));
  const g=document.createElement('button');g.setAttribute('data-go','signin');
  document.body.appendChild(g);g.click();g.remove();
  const t=document.createElement('button');t.setAttribute('data-go','t/setup');
  document.body.appendChild(t);t.click();t.remove();
  document.querySelector('[data-cfg="go:structure"]')?.click();});
const st = await p.evaluate(()=>{const app=document.querySelector('#app');
  return {links:[...app.querySelectorAll('a[href]')].map(a=>a.getAttribute('href')),
          hasBtn:!!app.querySelector('[data-go="t/college"]')};});
const stOk = st.links.includes(URL) && st.hasBtn;
console.log(`structure screen: chs-link=${st.links.includes(URL)} boundary-button=${st.hasBtn} ${stOk?'ok':'FAIL'}`);
if(!stOk) fails++;
console.log('page errors:', errs.length?errs[0]:'none');
console.log(`\n${fails} failures`);
await b.close();
