import pw from 'playwright';
import fs from 'fs';
const { chromium } = pw;
const body=fs.readFileSync('moaum-portal-prototype.html','utf8');
fs.writeFileSync('_ec.html','<!doctype html><html><head><meta charset="utf-8">'
 +'<meta name="viewport" content="width=device-width,initial-scale=1">'
 +'<style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+body+'</body></html>');
const b=await chromium.launch();
let fails=0;
async function go(pg, rt){
  return pg.evaluate(r=>{const b=document.createElement('button');b.setAttribute('data-go',r);
    document.body.appendChild(b);b.click();b.remove();
    const m=document.querySelector('#app'); return m?m.innerHTML:'';},rt);
}
async function signIn(pg, role, srole){
  await pg.evaluate(({role,srole})=>{
    document.querySelector(`[data-role="${role}"]`)?.click();
    if(srole){const s=document.querySelector('#office'); if(s){s.value=srole;s.dispatchEvent(new Event('change',{bubbles:true}));}}
    const g=document.createElement('button');g.setAttribute('data-go','signin');
    document.body.appendChild(g);g.click();g.remove();},{role,srole});
}
for (const [w,h,label] of [[1440,900,'desktop'],[390,844,'mobile']]) {
  const c=await b.newContext({viewport:{width:w,height:h}});
  const pg=await c.newPage();
  const errs=[]; pg.on('pageerror',e=>errs.push(String(e)));
  await pg.goto(new URL('_ec.html', import.meta.url).href); await pg.waitForTimeout(400);

  for (const [role,srole,routes] of [
    ['staff','lecturer',['t/sheet','r/classlist','t/eligibility','t/scores']],
    ['staff','hod',['t/sheet','t/scores','t/eligibility','r/classlist','t/broadsheet','t/resultdesk','t/lms','r/upload']],
    ['staff','dean',['t/sheet','t/scores','t/eligibility','r/classlist','t/broadsheet','t/resultdesk']],
    ['staff','super',['t/setup']],
    ['student',null,['s/register','s/results']],
  ]) {
    await pg.evaluate(()=>{const b=document.createElement('button');b.setAttribute('data-go','logout');
      document.body.appendChild(b);b.click();b.remove();});
    await signIn(pg, role, srole);
    for (const rt of routes) {
      errs.length=0;
      const html=await go(pg,rt);
      const ov=await pg.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);
      const who=srole||role;
      let bad=[];
      if(html.length<300) bad.push('empty');
      if(ov>2) bad.push('overflow '+ov);
      if(errs.length) bad.push(errs[0]);
      if(bad.length){console.log(`FAIL ${label}/${who} ${rt}: ${bad.join('; ')}`);fails++;}
      else if(label==='desktop'){
        const bor = ['Physics','Economics','Mathematics Education','Statistics'].filter(x=>html.includes(x));
        console.log(`ok ${who} ${rt}  ${html.length} chars  borrowed-shown: [${bor.join(', ')}]`);
      }
    }
  }
  // BR-006: the HOD's own set must be blocked at her own desk
  await pg.evaluate(()=>{const b=document.createElement('button');b.setAttribute('data-go','logout');
    document.body.appendChild(b);b.click();b.remove();});
  await signIn(pg,'staff','hod');
  const r1=await pg.evaluate(()=>{const b=document.createElement('button');
    b.setAttribute('data-rp','open:CSC 351');document.body.appendChild(b);b.click();b.remove();
    return document.querySelector('#app').innerHTML;});
  const blockedOwn = /data-rp="approve:CSC 351"[^>]*disabled/.test(r1);
  const r2=await pg.evaluate(()=>{const b=document.createElement('button');
    b.setAttribute('data-rp','open:CSC 311');document.body.appendChild(b);b.click();b.remove();
    return document.querySelector('#app').innerHTML;});
  const openOther = /data-rp="approve:CSC 311"/.test(r2) && !/data-rp="approve:CSC 311"[^>]*disabled/.test(r2);
  if(label==='desktop'){
    console.log(`BR-006 hod own set (CSC 351) blocked: ${blockedOwn}`);
    console.log(`BR-006 hod other set (CSC 311) approvable: ${openOther}`);
    if(!blockedOwn||!openOther) fails++;
  }
  await c.close();
}
await b.close();
console.log(`\n${fails} failures`);
