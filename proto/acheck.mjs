import pw from 'playwright';
const { chromium } = pw;
const b=await chromium.launch();
import fs from 'fs';
const hooked=fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_ac.html','<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+hooked+'</body></html>');
let fails=0;
async function signIn(pg, role, srole){
  await pg.evaluate(({role,srole})=>{
    const o=document.createElement('button');o.setAttribute('data-go','logout');
    document.body.appendChild(o);o.click();o.remove();
    document.querySelector(`[data-role="${role}"]`)?.click();
    if(srole){const s=document.querySelector('#office'); if(s){s.value=srole;s.dispatchEvent(new Event('change',{bubbles:true}));}}
    const g=document.createElement('button');g.setAttribute('data-go','signin');
    document.body.appendChild(g);g.click();g.remove();},{role,srole});
}
async function go(pg,rt){return pg.evaluate(r=>{const b=document.createElement('button');b.setAttribute('data-go',r);
  document.body.appendChild(b);b.click();b.remove();window.scrollTo(0,0);
  return document.querySelector('#app').innerHTML;},rt);}

for (const [w,h,label] of [[1440,900,'desktop'],[390,844,'mobile']]) {
  const c=await b.newContext({viewport:{width:w,height:h}});
  const pg=await c.newPage(); const errs=[]; pg.on('pageerror',e=>errs.push(String(e)));
  await pg.goto(new URL('_ac.html', import.meta.url).href); await pg.waitForTimeout(400);
  for (const [role,srole,routes] of [
    ['staff','audit',['t/prepayment','t/auditrevenue','t/auditpayroll','t/auditstaff','t/auditassets','t/ledger','t/reconcile']],
    ['staff','academic',['t/matriculation','t/admissions']],
    ['staff','facultyofficer',['t/matlist']],
  ]) {
    await signIn(pg, role, srole);
    for (const rt of routes) {
      errs.length=0;
      const html=await go(pg,rt);
      const ov=await pg.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);
      const bad=[]; if(html.length<300) bad.push('empty'); if(ov>2) bad.push('overflow '+ov); if(errs.length) bad.push(errs[0]);
      if(bad.length){console.log(`FAIL ${label}/${srole} ${rt}: ${bad.join('; ')}`);fails++;}
      else if(label==='desktop') console.log(`ok ${srole} ${rt}  ${html.length} chars`);
    }
  }
  // the matriculation run and the faculty confirm
  if(label==='desktop'){
    await signIn(pg,'staff','academic');
    await go(pg,'t/matriculation');
    const before=await pg.evaluate(()=>{const b=[...document.querySelectorAll('[data-mat]')].find(x=>x.getAttribute('data-mat')==='run');
      return {found:!!b, disabled: b? b.disabled : null};});
    console.log('MATRIC run button:', JSON.stringify(before), '(disabled is correct — Clinical Sciences outstanding)');
    await signIn(pg,'staff','facultyofficer');
    await go(pg,'t/matlist');
    const conf=await pg.evaluate(()=>{const b=document.querySelector('[data-mat="confirm"]'); if(!b) return 'no button';
      b.click(); return document.querySelector('#app').textContent.includes('Confirmed 12 October')?'confirmed':'clicked, no change';});
    console.log('FACULTY confirm:', conf);
    // applicant journey to stage 10
    await pg.evaluate(()=>{const o=document.createElement('button');o.setAttribute('data-go','logout');
      document.body.appendChild(o);o.click();o.remove();
      document.querySelector('[data-role="applicant"]')?.click();
      const g=document.createElement('button');g.setAttribute('data-go','signin');
      document.body.appendChild(g);g.click();g.remove();});
    for(const st of [8,9]){
      const html=await pg.evaluate(async (target)=>{
        // advance to target stage
        for(let i=0;i<12;i++){const f=document.querySelector('[data-ap="fwd"]'); if(f) f.click();}
        const m=document.createElement('button');m.setAttribute('data-go','a/matric');
        document.body.appendChild(m);m.click();m.remove();
        return document.querySelector('#app').innerHTML;}, st);
      if(st===9){
        console.log('APPLICANT stage 10: matric number shown =', html.includes('MOAUM/CSC/26/1874'),
                    '| admission number retired =', html.includes('MOAUM/ADM/26/018342'),
                    '| Library card step =', html.includes('At the Library'));
        if(!html.includes('MOAUM/CSC/26/1874')) fails++;
      }
    }
  }
  await c.close();
}
await b.close();
console.log(`\n${fails} failures`);
