import pw from 'playwright';
import fs from 'fs';
const { chromium } = pw;
const body=fs.readFileSync('moaum-portal-prototype.html','utf8');
fs.writeFileSync('_wc.html','<!doctype html><html><head><meta charset="utf-8">'
 +'<meta name="viewport" content="width=device-width,initial-scale=1">'
 +'<style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+body+'</body></html>');
const b=await chromium.launch();
let fails=0;
for (const [w,h,label] of [[1440,900,'desktop'],[390,844,'mobile']]) {
  const c=await b.newContext({viewport:{width:w,height:h}});
  const p=await c.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
  await p.goto(new URL('_wc.html', import.meta.url).href); await p.waitForTimeout(400);

  // student wallet
  await p.evaluate(()=>{document.querySelector('[data-role="student"]').click();
    const g=document.createElement('button');g.setAttribute('data-go','signin');
    document.body.appendChild(g);g.click();g.remove();});
  for (const r of ['s/fees','s/wallet']) {
    errs.length=0;
    const info=await p.evaluate(rt=>{const b=document.createElement('button');b.setAttribute('data-go',rt);
      document.body.appendChild(b);b.click();b.remove();
      return {len:document.querySelector('#app').innerHTML.length,
              txt:document.body.innerText.slice(0,0)||'',
              hasWallet:document.body.innerText.includes('NELFUND'),
              ov:document.documentElement.scrollWidth-document.documentElement.clientWidth};},r);
    console.log(`${label} ${r}: ${info.len} chars, NELFUND present=${info.hasWallet}, overflow=${info.ov}`);
    if(info.len<500||info.ov>2||errs.length){console.log('  FAIL',errs[0]||'');fails++;}
  }
  // apply from the wallet, then confirm clearance flipped
  const applied=await p.evaluate(()=>{
    const b=document.createElement('button');b.setAttribute('data-go','s/wallet');
    document.body.appendChild(b);b.click();b.remove();
    const btn=document.querySelector('[data-nlf="apply"]');
    if(!btn) return {found:false};
    btn.click();
    return {found:true, text:document.body.innerText.includes('Nothing outstanding'),
            reg:(()=>{const g=document.createElement('button');g.setAttribute('data-go','s/register');
              document.body.appendChild(g);g.click();g.remove();
              return !document.body.innerText.includes('blocked');})()};
  });
  console.log(`${label} apply-from-wallet: button found=${applied.found}, wallet settled=${applied.text}, registration unblocked=${applied.reg}`);
  if(!applied.found||!applied.text){console.log('  FAIL');fails++;}

  // bursary
  await p.evaluate(()=>{const o=document.createElement('button');o.setAttribute("data-go","logout");
    document.body.appendChild(o);o.click();o.remove();});
  await p.waitForTimeout(200);
  await p.evaluate(()=>{
    document.querySelector('[data-role="staff"]').click();
    const s=document.querySelector('#office'); s.value='bursar';
    s.dispatchEvent(new Event('change',{bubbles:true}));
    const g=document.createElement('button');g.setAttribute('data-go','signin');
    document.body.appendChild(g);g.click();g.remove();});
  for (const r of ['t/nelfund','t/nelmatch']) {
    errs.length=0;
    const info=await p.evaluate(rt=>{const b=document.createElement('button');b.setAttribute('data-go',rt);
      document.body.appendChild(b);b.click();b.remove();
      return {len:document.querySelector('#app').innerHTML.length,
              ov:document.documentElement.scrollWidth-document.documentElement.clientWidth};},r);
    console.log(`${label} ${r}: ${info.len} chars, overflow=${info.ov}`);
    if(info.len<500||info.ov>2||errs.length){console.log('  FAIL',errs[0]||'');fails++;}
  }
  await c.close();
}
await b.close();
console.log(`\n${fails} failures`);
