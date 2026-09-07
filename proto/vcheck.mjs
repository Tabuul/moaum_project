import pw from 'playwright';
import fs from 'fs';
const { chromium } = pw;
/* The hooked build, not the clean one: this harness has to enumerate routes
   from the ROUTER and the MENUS, and neither is reachable from the DOM.      */
const body=fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_vc.html','<!doctype html><html><head><meta charset="utf-8">'
 +'<meta name="viewport" content="width=device-width,initial-scale=1">'
 +'<style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+body+'</body></html>');
const b=await chromium.launch();

const ctx=await b.newContext({viewport:{width:1440,height:900}});
const p=await ctx.newPage();
const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
await p.goto(new URL('_vc.html', import.meta.url).href);
await p.waitForTimeout(500);

// the sign-in screen offers a role picker; find the office keys it exposes
const offices=await p.evaluate(()=>[...document.querySelectorAll('[data-role]')].map(e=>e.getAttribute('data-role')));
console.log('sign-in offers:', offices.join(' '));

async function signIn(pg, role, srole) {
  await pg.evaluate(({role,srole})=>{
    const rb=document.querySelector(`[data-role="${role}"]`); if(rb) rb.click();
    if (srole) {
      const sel=document.querySelector('#office');
      if (sel) { sel.value=srole; sel.dispatchEvent(new Event('change',{bubbles:true})); }
    }
    const go=document.createElement('button'); go.setAttribute('data-go','signin');
    document.body.appendChild(go); go.click(); go.remove();
  }, {role,srole});
}

let fails=0, checked=0, officeCount=0;
for (const [w,h,label] of [[1440,900,'desktop'],[390,844,'mobile']]) {
  const c2=await b.newContext({viewport:{width:w,height:h}});
  const pg=await c2.newPage();
  const e2=[]; pg.on('pageerror',e=>e2.push(String(e)));
  await pg.goto(new URL('_vc.html', import.meta.url).href);
  await pg.waitForTimeout(400);

  // "staff" then picks one of the nineteen offices
  const sroles = await pg.evaluate(()=>{
    const rb=document.querySelector('[data-role="staff"]'); if(rb) rb.click();
    const sel=document.querySelector('#office');
    return sel ? [...sel.options].map(o=>o.value) : [];
  });
  const combos = [['student',null],['applicant',null], ...sroles.map(s=>['staff',s])];
  if (label==='desktop') console.log('offices:', sroles.length, '—', sroles.join(' '));

  for (const [role, srole] of combos) {
    await pg.evaluate(()=>{const b=document.createElement('button');b.setAttribute("data-go","logout");
      document.body.appendChild(b);b.click();b.remove();});
    await signIn(pg, role, srole);
    const who = srole || role;
    // walk every route this office's sidebar offers
    /* Enumerating from [data-go] in the rendered page misses every route
       inside a COLLAPSED navigation group, so a screen only ever reachable
       from a folded group was never walked and the count did not move when
       one was added. The identical bug was found and fixed in the College
       harness on 6 September and not carried back here.

       The menu is the promise and the router is the delivery, so both are
       enumerated: every item in every group of this office's menu, open or
       folded, plus the office's home route.                                */
    const routes=await pg.evaluate((sr)=>{
      const s=new Set();
      const m = (sr && window.__ROLES && window.__ROLES[sr]) ? window.__ROLES[sr] : null;
      if (m) {
        s.add(m.home);
        m.groups.forEach(g=>g.items.forEach(i=>s.add(i.id)));
      }
      document.querySelectorAll('[data-go]').forEach(e=>{
        const v=e.getAttribute('data-go').split('|')[0];
        if(v.includes('/')) s.add(v);
      });
      return [...s];
    }, srole);
    if (label==='desktop') { officeCount++; }
    for (const r of routes) {
      e2.length=0;
      const ok=await pg.evaluate(rt=>{
        const b=document.createElement('button'); b.setAttribute('data-go',rt);
        document.body.appendChild(b); b.click(); b.remove();
        const m=document.querySelector('#app');
        return m?m.innerHTML.length:0;
      }, r);
      const ov=await pg.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);
      checked++;
      if(ok<300){console.log(`FAIL ${label}/${who} ${r}: empty (${ok})`);fails++;}
      if(ov>2){console.log(`FAIL ${label}/${who} ${r}: overflow ${ov}px`);fails++;}
      if(e2.length){console.log(`FAIL ${label}/${who} ${r}: ${e2[0]}`);fails++;e2.length=0;}
    }
  }
  await c2.close();
}
await ctx.close(); await b.close();
console.log(`\n${officeCount} offices, ${checked} screen loads, ${fails} failures`);
