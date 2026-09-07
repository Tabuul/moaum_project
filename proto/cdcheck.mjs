import pw from 'playwright';
import { fileURLToPath } from 'node:url';
const { chromium } = pw; import fs from 'fs';
const b=await chromium.launch();
const ctx=await b.newContext({viewport:{width:1280,height:900}});
const p=await ctx.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
const hooked=fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_cd.html','<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+hooked+'</body></html>');
await p.goto(new URL('_cd.html', import.meta.url).href); await p.waitForTimeout(400);
let fail=0; const t=(n,ok,d='')=>{if(!ok)fail++;console.log(`  ${ok?'PASS':'FAIL'}  ${n.padEnd(58)}  ${d}`);};
const go=async r=>{await p.evaluate(rt=>{__S.role='staff';__S.srole='academic';__S.route=rt;__render();},r);await p.waitForTimeout(250);};

await go('t/candidatedata');
let txt=await p.locator('body').innerText();
t('The screen refuses to match against nothing',
  txt.includes('No admission list has been uploaded yet'));

// load a list first, then the three attachments
await go('t/capsintake');
await p.evaluate(()=>document.querySelector('[data-caps="demo:utme"]').click());
await p.waitForTimeout(250);
await p.evaluate(()=>document.querySelector('[data-caps="demo:de"]').click());
await p.waitForTimeout(250);
await go('t/candidatedata');

// passports
await p.evaluate(()=>document.querySelector('[data-caps="demopas"], [data-cd="demopas"]').click());
await p.waitForTimeout(300);
txt=await p.locator('body').innerText();
t('Passports match on the JAMB number in the filename',
  txt.includes('202699176777GF') && txt.includes('132×151'));
t('The number is read out of JAMB’s real "_Face.jpg" name',
  /read out of \d+ filenames/.test(txt) && txt.includes('202699168863AH_Face.jpg'),
  'not stripped by name — found by shape');
t('A file with no number in its name is named, not held as an orphan',
  txt.includes('no registration number in the name') &&
  txt.includes('IMG-20260904-WA0031.jpg'));
t('A passport matching nobody is held, not discarded',
  txt.includes('202499999999ZZ') && txt.includes('held, not discarded'.replace('held','Held')) ||
  txt.includes('match no candidate'));
t('It says the photo is too small for an identity card',
  txt.includes('too small for an identity card'));
t('An image actually renders', await p.evaluate(()=>{
  const i=document.querySelector('.content img[src^="data:image/jpeg"]');
  return !!i && i.naturalWidth===132; }), '132px wide, as JAMB sends it');

// ── the REAL filenames, through the real upload path ─────────────────────
const P=fileURLToPath(new URL('_pas/', import.meta.url));
await p.evaluate(()=>{__S.pas=null; __render();}); await p.waitForTimeout(150);
await p.setInputFiles('#cd-pas', [P+'202699168863AH_Face.jpg', P+'202699176777GF_Face.jpg',
                                  P+'Copy of 202699711714BJ_Face (1).jpg',
                                  P+'IMG-20260904-WA0031.jpg']);
await p.waitForTimeout(800);
txt=await p.locator('body').innerText();
const matchedTile = async () => p.evaluate(()=>{
  const t=[...document.querySelectorAll('.tile')].map(x=>x.innerText.toUpperCase());
  const r=t.find(x=>x.indexOf('MATCHED TO A CANDIDATE')===0);
  return r?parseInt(r.split('\n')[1],10):-1;});
t('REAL files named 202699168863AH_Face.jpg match three candidates',
  await matchedTile()===3, 'the fourth has no number in its name');
t('“Copy of … (1)” survives too', txt.includes('202699711714BJ'),
  'the number is found, not the wrapper stripped');
t('And the nameless one is listed by its filename',
  txt.includes('IMG-20260904-WA0031.jpg') && txt.includes('no registration number in the name'));

// dates of birth
await p.evaluate(()=>document.querySelector('[data-cd="tab:dob"]').click()); await p.waitForTimeout(150);
await p.evaluate(()=>document.querySelector('[data-cd="demodob"]').click()); await p.waitForTimeout(250);
txt=await p.locator('body').innerText();
t('The trailing space is trimmed, and the screen says so',
  txt.includes('trailing space') && txt.includes('trimmed'));
t('An ambiguous date is flagged rather than parsed',
  txt.includes('ambiguous') && txt.includes('05-07-2002'), '5 July or 7 May');
t('An unambiguous date is read out in words', txt.includes('31 August 2005'));

// the real DOB file
/* The real JAMB files are NOT in the repository and never will be: they
   carry real candidates' names, registration numbers, scores and local
   governments. Point MOAUM_FIXTURES at a directory holding them to run
   these checks; without it they are SKIPPED and said to be skipped, which
   is the honest report — a check that silently does not run is worse than
   one that fails. */
const U = process.env.MOAUM_FIXTURES ? process.env.MOAUM_FIXTURES.replace(/\/?$/, '/') : null;
let skipped = 0;
const skip = (n, why) => { skipped++; console.log(`  SKIP  ${n.padEnd(58)}  ${why}`); };
if (!U) {
  skip('The REAL date-of-birth file reads', 'no MOAUM_FIXTURES');
  skip('The REAL O’Level file reads and collapses per candidate', 'no MOAUM_FIXTURES');
  await p.evaluate(()=>document.querySelector('[data-cd="tab:ol"]').click());
  await p.waitForTimeout(150);
} else {
await p.setInputFiles('#cd-dob', U+'a5397646-DOB_from_jamb_sample.xlsx'); await p.waitForTimeout(700);
txt=await p.locator('body').innerText();
t('The REAL date-of-birth file reads', txt.includes('202440000065EA'), 'all three rows trimmed');

// o'level
await p.evaluate(()=>document.querySelector('[data-cd="tab:ol"]').click()); await p.waitForTimeout(150);
await p.setInputFiles('#cd-ol', U+'3f95827c-olevel_sample.xlsx'); await p.waitForTimeout(700);
txt=await p.locator('body').innerText();
t('The REAL O’Level file reads and collapses per candidate',
  txt.includes('collapsed to') && txt.includes('2 candidates'), '18 rows -> 2 candidates');
}
await p.evaluate(()=>document.querySelector('[data-cd="demool"]').click()); await p.waitForTimeout(250);
txt=await p.locator('body').innerText();
t('Credits, English and Mathematics are computed', await p.evaluate(()=>{
    const tr=[...document.querySelectorAll('tbody tr')].find(r=>r.textContent.includes('202699711714BJ'));
    if (!tr) return false;
    const cells=[...tr.cells].map(td=>td.getAttribute('data-l')+'='+td.textContent.trim());
    return cells.some(x=>/^Credits=7$/.test(x)) && cells.some(x=>/^English=B3$/.test(x))
        && cells.some(x=>/^Maths=C5$/.test(x)); }),
  '7 credits, English B3, Maths C5');
t('A candidate short of the minimum is named',
  txt.includes('do not meet five credits') || txt.includes('does not meet five credits'),
  'English D7 is not a credit');

// ── the three samples against the seventeen sample applicants ────────────
const counts = async () => p.evaluate(()=>{
  /* the tile label is uppercased by CSS, so innerText comes back in caps */
  const t=[...document.querySelectorAll('.tile')].map(x=>x.innerText.replace(/\n/g,'|').toUpperCase());
  const n=l=>{const r=t.find(x=>x.indexOf(l.toUpperCase())===0); return r?parseInt(r.split('|')[1],10):-1;};
  return { matched:n('Matched to a candidate'),
           orphan:t.filter(x=>/WITH NO CANDIDATE/.test(x)).map(x=>parseInt(x.split('|')[1],10))[0],
           waiting:n('Candidates still waiting'), total:n('On the admission lists') };});

await p.evaluate(()=>{__S.cdTab='pas'; __S.pas=null; __render();}); await p.waitForTimeout(200);
await p.evaluate(()=>document.querySelector('[data-cd="demopas"]').click()); await p.waitForTimeout(500);
let c1 = await counts();
t('Passports: seventeen applicants, thirteen matched, one orphan, four waiting',
  c1.total===17 && c1.matched===13 && c1.orphan===1 && c1.waiting===4,
  JSON.stringify(c1));

await p.evaluate(()=>{__S.cdTab='dob'; __render();}); await p.waitForTimeout(200);
await p.evaluate(()=>document.querySelector('[data-cd="demodob"]').click()); await p.waitForTimeout(300);
let c2 = await counts();
t('Dates of birth: fifteen matched, one orphan, two waiting',
  c2.total===17 && c2.matched===15 && c2.orphan===1 && c2.waiting===2, JSON.stringify(c2));
txt = await p.locator('body').innerText();
t('Every row needed trimming', /16 registration numbers had a trailing space/i.test(txt));
t('The ambiguous dates are counted, not guessed at',
  /6 dates of birth are ambiguous/i.test(txt), '6 of 16 — two in five, as expected');
t('And the screen states the real rate', /144 of the 365/.test(txt),
  'not a rare edge: 39.5% of dates in a year');

await p.evaluate(()=>{__S.cdTab='ol'; __render();}); await p.waitForTimeout(200);
await p.evaluate(()=>document.querySelector('[data-cd="demool"]').click()); await p.waitForTimeout(300);
let c3 = await counts();
t('O’Level: sixteen matched, one orphan, one waiting',
  c3.total===17 && c3.matched===16 && c3.orphan===1 && c3.waiting===1, JSON.stringify(c3));
txt = await p.locator('body').innerText();
t('Two candidates fall short of five credits with English and Maths',
  /2 candidates do not meet five credits/i.test(txt),
  'one on English D7, one with only three credits');
t('Direct Entry candidates carry O’Level too', await p.evaluate(()=>{
    const tr=[...document.querySelectorAll('tbody tr')].find(r=>r.textContent.includes('202660201774AF'));
    return !!tr; }),
  'a prior qualification is in addition to the credits, not instead of them');

// ── the sidebar ──
await p.evaluate(()=>document.querySelector('[data-go="slimnav"]').click()); await p.waitForTimeout(250);
t('The sidebar collapses to a rail',
  await p.evaluate(()=>document.querySelector('.nav').getBoundingClientRect().width) < 80,
  await p.evaluate(()=>Math.round(document.querySelector('.nav').getBoundingClientRect().width))+'px');
t('The icons and the current item survive the collapse',
  await p.evaluate(()=>!!document.querySelector('.nav__item[aria-current="page"] svg')));
await p.evaluate(()=>document.querySelector('[data-go="slimnav"]').click()); await p.waitForTimeout(250);
t('And it expands again',
  await p.evaluate(()=>document.querySelector('.nav').getBoundingClientRect().width) > 200);

// ── tables ──
for (const [w,h] of [[1280,900],[1100,900],[900,900],[760,900],[390,844]]) {
  await p.setViewportSize({width:w,height:h}); await p.waitForTimeout(350);
  const over = await p.evaluate(()=>{
    let n=0; document.querySelectorAll('.tablewrap').forEach(wr=>{
      if (wr.scrollWidth > wr.clientWidth + 1) n++; });
    return n; });
  t(`No table scrolls sideways at ${w}px`, over===0, over? over+' still overflow':'');
}
await p.setViewportSize({width:1280,height:900});
t('No JavaScript errors', errs.length===0, errs.slice(0,2).join(' | '));
console.log(`\n${fail} failures` + (skipped ? `, ${skipped} skipped (set MOAUM_FIXTURES to run them)` : '')); await b.close(); process.exit(fail?1:0);
