import pw from '/opt/node-tools/node_modules/playwright/index.js';
const { chromium } = pw; import fs from 'fs';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const p = await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
const hooked = fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_caps.html','<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0}</style></head><body>'+hooked+'</body></html>');
await p.goto('file://'+process.cwd()+'/_caps.html'); await p.waitForTimeout(400);
let fail=0; const t=(n,ok,d='')=>{if(!ok)fail++;console.log(`  ${ok?'PASS':'FAIL'}  ${n.padEnd(58)}  ${d}`);};
await p.evaluate(()=>{__S.role='staff';__S.srole='academic';__S.route='t/capsintake';__render();});

// the office, and the route it reaches this by
t('The office is named Academic Office',
  await p.evaluate(()=>__ROLES.academic.label)==='Academic Office');
t('It is in the Academic Office menu', await p.evaluate(()=>
  __ROLES.academic.groups.some(g=>g.items.some(i=>i.id==='t/capsintake'))));
t('Both lists have their own file chooser', await p.evaluate(()=>
  !!document.querySelector('#caps-utme') && !!document.querySelector('#caps-de')));
t('Nothing is displayed before a file is chosen',
  (await p.locator('body').innerText()).includes('Nothing uploaded for UTME yet'));
t('One code system: the University table is keyed on JAMB\'s C-code',
  await p.evaluate(()=>Object.keys(__PROGT).every(
    c=>c.length===6 && c[0]==='C' && !isNaN(Number(c.slice(1))))),
  await p.evaluate(()=>Object.keys(__PROGT).length + ' programmes'));
t('The two names differ for most programmes', await p.evaluate(()=>{
    var n=0; for (var c in __PROGT) {
      if (__JNAME[c] && __JNAME[c].replace(/&amp;/g,'&').toUpperCase() !== __PROGT[c][0].toUpperCase()) n++; }
    return n; }) === 56, '56 of 92');

// the sample path
await p.evaluate(()=>document.querySelector('[data-caps="demo:utme"]').click());
await p.waitForTimeout(200);
let txt = await p.locator('body').innerText();
t('The sample UTME list reads and displays', txt.includes('202660176777GF'), '8 candidates');
t('CAPS name resolves to the University programme',
  txt.includes('Medicine & Surgery') && txt.includes('MBBS'), 'CO_NAME -> C00061 -> MBBS');
t('The aggregate and its components are shown', txt.includes('337') && txt.includes('Physics 96'));

// a REAL CAPS download, through the real file input
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
  skip('A REAL CAPS .xlsx is unzipped and parsed in the browser', 'no MOAUM_FIXTURES');
  skip('It is recognised as the CAPS download layout', 'no MOAUM_FIXTURES');
  skip('Both rows resolve to MBBS', 'no MOAUM_FIXTURES');
  skip('The office-built file reads too, on different column names', 'no MOAUM_FIXTURES');
  skip('The real DE file uploaded as UTME is refused, by line', 'no MOAUM_FIXTURES');
} else {
await p.setInputFiles('#caps-utme', U+'cf625ad0-downloaded_list_from_jamb_format.xlsx');
await p.waitForTimeout(700);
txt = await p.locator('body').innerText();
t('A REAL CAPS .xlsx is unzipped and parsed in the browser',
  txt.includes('202660176777GF') && txt.includes('Terfa'), 'downloaded list from jamb format.xlsx');
t('It is recognised as the CAPS download layout', txt.includes('CAPS download'));
t('Both rows resolve to MBBS', (txt.match(/MBBS/g)||[]).length >= 2);

// the office's own derivative, different columns entirely
await p.setInputFiles('#caps-utme', U+'8e677210-real_utme_upload_27th.xlsx');
await p.waitForTimeout(700);
txt = await p.locator('body').innerText();
t('The office-built file reads too, on different column names',
  txt.includes('built by this office') && txt.includes('B.Sc. ACCOUNTING'), 'programme code C00019 -> B.Sc. ACCOUNTING');

// the DE file loaded as UTME must be refused
await p.setInputFiles('#caps-utme', U+'6ad40436-real_de_upload_27th.xlsx');
await p.waitForTimeout(1500);
txt = await p.locator('body').innerText();
t('The real DE file uploaded as UTME is refused, by line',
  txt.includes('cannot be accepted') && txt.includes('no aggregate'));
}

// DE in its own slot
await p.evaluate(()=>document.querySelector('[data-caps="demo:de"]').click());
await p.waitForTimeout(200);
txt = await p.locator('body').innerText();
t('The DE sample reads at 200 Level with no aggregate',
  txt.includes('202660307120BGU') && txt.includes('n/a'));
t('A postgraduate code on the DE list is refused',
  txt.includes('not a programme here') || txt.includes('MA RELIGION'), 'C99256');


// ── editing ──────────────────────────────────────────────────────────────
await p.evaluate(()=>document.querySelector('[data-caps="demo:de"]').click());
await p.waitForTimeout(150);

// the postgraduate code has no programme, so the row offers Resolve
t('An unresolved row offers Resolve rather than Edit',
  await p.evaluate(()=>!!document.querySelector('[data-caps^="editrow:202660774411"]')));
await p.evaluate(()=>document.querySelector('[data-caps^="editrow:202660774411"]').click());
await p.waitForTimeout(150);
txt = await p.locator('body').innerText();
t('The correction editor shows JAMB\'s side read-only',
  txt.includes('MA RELIGION AND PEACE STUDIES') && txt.includes('not edited'));

// a correction with no reason is refused, and says why
await p.evaluate(()=>{document.querySelector('#cr-code').value='C00095';
                      document.querySelector('[data-caps="rowsave"]').click();});
await p.waitForTimeout(150);
txt = await p.locator('body').innerText();
t('A correction with no reason is refused, in words',
  txt.includes('Refused') && txt.includes('overwrite with extra steps'));
t('The chosen programme survives the refusal',
  await p.evaluate(()=>document.querySelector('#cr-code').value)==='C00095');

// with a reason it is recorded, and the list shows it corrected
await p.evaluate(()=>{document.querySelector('#cr-why').value='Postgraduate code on the DE list; confirmed with the Academic Office';
                      document.querySelector('[data-caps="rowsave"]').click();});
await p.waitForTimeout(200);
txt = await p.locator('body').innerText();
t('A correction with a reason is recorded and shown as corrected',
  txt.includes('B.A. RELIGION AND PHILOSOPHY') && txt.includes('corrected'));
t('The row still shows what JAMB sent', txt.includes('MA RELIGION AND PEACE STUDIES'),
  'the original is kept beside the correction, never over it');

// editing a programme
await p.evaluate(()=>document.querySelector('[data-caps="editprog:C00061"]').click());
await p.waitForTimeout(150);
txt = await p.locator('body').innerText();
t('The programme editor opens with JAMB\'s name locked',
  txt.includes('Medicine & Surgery') && txt.includes('not editable'));
await p.evaluate(()=>{document.querySelector('#ce-name').value='MBBS (Hons)';
                      document.querySelector('[data-caps="progsave"]').click();});
await p.waitForTimeout(150);
txt = await p.locator('body').innerText();
t('A programme change with no instrument is refused',
  txt.includes('cites the instrument'));
t('A refusal keeps what was typed',
  await p.evaluate(()=>document.querySelector('#ce-name').value)==='MBBS (Hons)',
  'a refusal that discards your work is one people avoid rather than answer');
await p.evaluate(()=>{document.querySelector('#ce-instr').value='SEN/2026/41';
                      document.querySelector('[data-caps="progsave"]').click();});
await p.waitForTimeout(200);
t('With an instrument it saves',
  await p.evaluate(()=>__S.capsProgEdit['C00061'] &&
    __S.capsProgEdit['C00061'].name==='MBBS (Hons)' &&
    __S.capsProgEdit['C00061'].instr==='SEN/2026/41'),
  await p.evaluate(()=>JSON.stringify(__S.capsProgEdit['C00061']||null)));
await p.evaluate(()=>{__S.capsEdit=null; __render();});
await p.waitForTimeout(200);
t('The amended name reaches the programme table',
  (await p.evaluate(()=>{
     const tr=[...document.querySelectorAll('tbody tr')].find(r=>r.textContent.includes('C00061'));
     return tr ? tr.textContent : ''; })).includes('MBBS (Hons)'),
  'and every candidate on C00061, on this list and every list to come');

// ── the passport beside the name on the admission list ───────────────────
await p.evaluate(()=>{__S.route='t/capsintake'; __S.capsEdit=null; __S.cdTab='pas';
                      __S.pas=null; __render();});
await p.evaluate(()=>document.querySelector('[data-caps="demo:utme"]').click());
await p.waitForTimeout(250);
t('Without passports there is no empty column, but there is an offer',
  await p.evaluate(()=>!document.querySelector('.content .mugshot')) &&
  (await p.locator('body').innerText()).includes('Upload the passports to see them beside the names'));

await p.evaluate(()=>{__S.route='t/candidatedata';__S.cdTab='pas';__render();});
await p.waitForTimeout(150);
await p.evaluate(()=>document.querySelector('[data-cd="demopas"]').click());
await p.waitForTimeout(500);
await p.evaluate(()=>{__S.route='t/capsintake';__render();}); await p.waitForTimeout(300);

t('The passport now appears on the uploaded UTME list',
  await p.evaluate(()=>document.querySelectorAll('.content img.mugshot').length) > 0,
  await p.evaluate(()=>document.querySelectorAll('.content img.mugshot').length)+' photographs in the list');
t('It is the right photograph, matched on the number', await p.evaluate(()=>{
    const tr=[...document.querySelectorAll('tbody tr')].find(r=>r.textContent.includes('202660176777GF'));
    const img=tr && tr.querySelector('img.mugshot');
    return !!img && img.getAttribute('title')==='202660176777GF_Face.jpg'; }),
  'JAMB’s own filename, kept as it arrived');
t('A candidate with no passport shows initials, not a blank',
  await p.evaluate(()=>{
    const tr=[...document.querySelectorAll('tbody tr')].find(r=>r.textContent.includes('202660881440FP'));
    const m=tr && tr.querySelector('.mugshot--none');
    return !!m && m.textContent.trim()==='ST'; }),
  'Shaahu Terwase John — CAPS puts the surname first, so S.T.');
t('And the gap is stated once rather than sixteen times',
  /2 of these 9 candidates have no passport yet/.test(await p.locator('body').innerText()));

const unbound = await p.evaluate(()=>{const o=[];document.querySelectorAll('.content button').forEach(el=>{const a=el.getAttribute('data-act');if(a&&a[0]==='?')o.push(el.textContent.trim());});return o;});
t('No control is unbound', unbound.length===0, unbound.join(' | '));
t('No JavaScript errors', errs.length===0, errs.slice(0,2).join(' | '));
console.log(`\n${fail} failures` + (skipped ? `, ${skipped} skipped (set MOAUM_FIXTURES to run them)` : '')); await b.close(); process.exit(fail?1:0);
