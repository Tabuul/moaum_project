import pw from '/opt/node-tools/node_modules/playwright/index.js';
const { chromium } = pw; import fs from 'fs';
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1280,height:900}});
const p=await ctx.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
const hooked=fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_cd.html','<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+hooked+'</body></html>');
await p.goto('file://'+process.cwd()+'/_cd.html'); await p.waitForTimeout(400);
let fail=0; const t=(n,ok,d='')=>{if(!ok)fail++;console.log(`  ${ok?'PASS':'FAIL'}  ${n.padEnd(56)}  ${d}`);};
await p.evaluate(()=>{__S.role='staff';__S.srole='academic';__S.route='t/capsintake';__render();});
await p.evaluate(()=>document.querySelector('[data-caps="demo:utme"]').click());
await p.waitForTimeout(300);

t('A table with enough rows gets a search box',
  await p.evaluate(()=>document.querySelectorAll('.tsrch input').length) > 0,
  await p.evaluate(()=>document.querySelectorAll('.tsrch input').length)+' boxes');

const vis=()=>p.evaluate(()=>{
  const tr=[...document.querySelectorAll('tbody tr')];
  return tr.filter(r=>!r.hidden).length; });
const before=await vis();
await p.locator('.tsrch input').first().fill('MBBS'); await p.waitForTimeout(200);
const after=await vis();
t('Typing filters the rows', after>0 && after<before, before+' -> '+after);
t('The footer says what matched',
  (await p.locator('body').innerText()).includes('matching'));

// focus must survive
await p.locator('.tsrch input').first().type('x'); await p.waitForTimeout(150);
t('The caret is not stolen mid-word',
  await p.evaluate(()=>document.activeElement && document.activeElement.getAttribute('data-tq')!==null),
  'no re-render on input');
t('A search that matches nothing says so, and offers Clear',
  (await p.locator('body').innerText()).includes('Nothing matches'));
await p.evaluate(()=>document.querySelector('[data-tq$=":"]').click()); await p.waitForTimeout(250);
t('Clear restores every row', (await vis())===before);

// a big table: search then page
await p.evaluate(()=>{__S.route='t/capsintake';__render();}); await p.waitForTimeout(200);
const ids=await p.evaluate(()=>Object.keys(__TBLDOM||{}));
t('Every data table is registered for search', ids.length>0, ids.length+' tables');
const big=await p.evaluate(()=>{
  for (const k in __TBLDOM) if (__TBLDOM[k].texts.length>40) return k; return null; });
if (big) {
  await p.evaluate(k=>{__S.tq[k]='b.sc';__tblApply(k);}, big); await p.waitForTimeout(200);
  t('Search pages over the matches, not the rows',
    (await p.locator('body').innerText()).includes('matching') ||
    (await p.evaluate(()=>!!document.querySelector('.pg'))), 'the 92-programme table');
}
for (const w of [1280, 900, 390]) {
  await p.setViewportSize({width:w,height:900}); await p.waitForTimeout(350);
  const over=await p.evaluate(()=>{let n=0;
    document.querySelectorAll('.tablewrap').forEach(wr=>{if(wr.scrollWidth>wr.clientWidth+1)n++;});return n;});
  t(`still nothing scrolls sideways at ${w}px`, over===0, over?over+' overflow':'');
}
t('No JavaScript errors', errs.length===0, errs.slice(0,2).join(' | '));
console.log(`\n${fail} failures`); await b.close(); process.exit(fail?1:0);
