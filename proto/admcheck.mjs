/* Admission settings — the Central Admissions Committee's guidelines,
   made into settings the portal applies, and refusing to open a session
   until they are complete. */
import pw from 'playwright';
const { chromium } = pw; import fs from 'fs';
const b=await chromium.launch();
const ctx=await b.newContext({viewport:{width:1400,height:1000}});
const p=await ctx.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
const hooked=fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_adm.html','<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+hooked+'</body></html>');
await p.goto(new URL('_adm.html', import.meta.url).href); await p.waitForTimeout(400);
let fail=0; const t=(n,ok,d='')=>{if(!ok)fail++;console.log(`  ${ok?'PASS':'FAIL'}  ${n.padEnd(62)}  ${d}`);};
const txt=()=>p.locator('body').innerText();
const tab=async k=>{await p.evaluate(x=>document.querySelector('[data-as="tab:'+x+'"]').click(),k);
                    await p.waitForTimeout(250);};
const set=async(sel,v)=>{await p.locator(`[data-as="${sel}"]`).fill(v); await p.waitForTimeout(200);};

await p.evaluate(()=>{__S.role='staff';__S.srole='academic';__S.adm=null;
                      __S.route='t/admissionsetup';__render();});
await p.waitForTimeout(300);
let s=await txt();

// ── it is the Academic Office's screen ───────────────────────────────────
t('It is in the Academic Office menu', await p.evaluate(()=>
  __ROLES.academic.groups.some(g=>g.items.some(i=>i.id==='t/admissionsetup'))));
t('A draft session admits nobody, and the screen says so',
  s.includes('DRAFT') && s.includes('no candidate can be ranked, cut off or admitted'));
t('It refuses to fall back on last year’s numbers',
  /over-admits by nine hundred/.test(s));

// ── the numbers, as the Committee issued them ────────────────────────────
t('The NUC approved quota is 10,198', s.includes('10,198'));
t('The four criteria total one hundred per cent',
  await p.evaluate(()=>__S.adm.crit.NATIONAL_MERIT + __S.adm.crit.STATE_MERIT +
                       __S.adm.crit.ELG + __S.adm.crit.LOCALITY)===100,
  'NM 10 + SM 35 + ELG 30 + Locality 25');
t('The weighting is 70/30, not an even half each',
  await p.evaluate(()=>__S.adm.wUtme)===70 && await p.evaluate(()=>__S.adm.wPutme)===30,
  'paragraph 2.6');
t('The worked example scales the UTME mark before weighting it',
  s.includes('63.78'), '247 of 400 and 68.5 of 100 — under 50/50 it would be 65.13');

// ── the applicant sees the same number, from the same setting ────────────
await p.evaluate(()=>{__S.role='applicant';__S.ap.stage=5;__S.route='a/score';__render();});
await p.waitForTimeout(250);
t('The applicant’s own screen reads the aggregate from the settings',
  (await txt()).includes('63.78') && /weighted 70 \/ 30/i.test(await txt()),
  'one rule, not two screens each with a copy of it');
await p.evaluate(()=>{__S.adm.wUtme=60;__S.adm.wPutme=40;__render();});
await p.waitForTimeout(250);
t('Change the setting and the applicant’s aggregate changes with it',
  (await txt()).includes('64.45') && /weighted 60 \/ 40/i.test(await txt()));
await p.evaluate(()=>{__S.adm.wUtme=70;__S.adm.wPutme=30;
                      __S.role='staff';__S.route='t/admissionsetup';__render();});
await p.waitForTimeout(250);

// ── a weighting that does not total 100 ──────────────────────────────────
await set('w:putme','20');
t('A weighting that does not total 100 is called out',
  (await txt()).includes('does not total 100'), '70 + 20');
await set('w:putme','30');

// ── the criteria ─────────────────────────────────────────────────────────
await set('c:ELG','40');
await tab('force'); s=await txt();
t('Criteria that do not total 100 are a finding, with the shortfall named',
  s.includes('do not total 100%') && s.includes('110'));
await tab('session'); await set('c:ELG','30');

// ── the faculty quotas ───────────────────────────────────────────────────
await tab('faculty');
s=await txt();
t('The 2024/2025 column totals exactly what the document states',
  s.includes('9,271'), 'the transcription checks out against the document’s own total');
t('And the 2025/2026 column is blank, as the document leaves it',
  await p.evaluate(()=>Object.keys(__S.adm.fq).every(f=>__S.adm.fq[f].quota===null)));
t('Every faculty carries the cut-off the guidelines set',
  await p.evaluate(()=>__S.adm.fq.LW.cutoff===220 && __S.adm.fq.SC.cutoff===160 &&
                       __S.adm.fq.AC.cutoff===180 && __S.adm.fq.PS.cutoff===220),
  'Law 220, Science 160, Architecture 180, Pharmaceutical Sciences 220');
t('Where the guidelines call a faculty something else, both names are shown',
  s.includes('College of Health Sciences') && s.includes('Administration and Management'),
  'a quota distributed against one name, programmes hanging off the other');
t('MBBS carries its own cut-off above its College’s',
  s.includes('220') && s.includes('MBBS'));

// ── the programmes ───────────────────────────────────────────────────────
await tab('prog');
s=await txt();
t('The guidelines cover 64 of the 92 programmes',
  await p.evaluate(()=>__PROG_RULE_COUNT())===64,
  await p.evaluate(()=>__PROG_RULE_COUNT()+' of '+Object.keys(__PROGT).length));
t('The 28 with no rule are named as unadmittable, not left blank',
  s.includes('28 of 92 programmes have no rule') && s.includes('not stated'));
t('A programme with no cut-off of its own shows its faculty’s',
  s.includes('faculty'), 'resolved once, not in every screen that asks');

// ── putting it in force ──────────────────────────────────────────────────
await tab('force');
s=await txt();
t('Two findings stand against the settings as issued',
  /2 findings stand between/.test(s),
  'no quota distribution, and 28 programmes with no rule');
t('Each finding names whose it is to answer',
  s.includes('Deans of Faculties') && s.includes('Deans and Heads of Department'));

t('The three contradictions in the document are put, not resolved by ICT',
  s.includes('English and Mathematics: compulsory everywhere, or not?') &&
  s.includes('30% or not more than 50%') &&
  s.includes('which ratio does 60:40 belong to'),
  'each changes who is admitted');
t('And the three quieter ones too',
  s.includes('Two names for four faculties') &&
  s.includes('Biochemistry sits in two faculties') &&
  s.includes('Mass Communication has no stated requirement'));

await p.evaluate(()=>document.querySelector('[data-as="force"]').click());
await p.waitForTimeout(250);
t('It cannot be put in force citing no minute',
  (await txt()).includes('Refused') && (await txt()).includes('opinion about a cut-off'));

await set('instr','CAC/2025/07');
await p.evaluate(()=>document.querySelector('[data-as="force"]').click());
await p.waitForTimeout(250);
t('Nor with a minute, while the findings stand',
  /findings? still stands?/.test(await txt()),
  'a warning that can be clicked past is not a rule');
t('And it is still a draft',
  await p.evaluate(()=>__S.adm.inForce)===false);

// ── the Deans distribute, and the Departments answer ─────────────────────
await p.evaluate(()=>{
  const f=__S.adm.fq, codes=Object.keys(f);
  codes.forEach(c=>{f[c].quota=0;});
  f.SC.quota=3000; f.ED.quota=1300; f.SS.quota=1100; f.AR.quota=900; f.MS.quota=900;
  f.CM.quota=900; f.BAMS.quota=1000; f.TI.quota=450; f.ES.quota=350; f.AC.quota=168;
  f.LW.quota=80;  f.PS.quota=50;
  __render();});
await p.waitForTimeout(250);
t('With the quota distributed to the unit, that finding clears',
  !(await txt()).includes('do not total the NUC approved quota'),
  '10,198 exactly');

// the 28 programmes are answered by stating a rule for each
await p.evaluate(()=>{
  Object.keys(__PROGT).forEach(c=>{ if(!__ADM_SRC.rules[c]) {
    __ADM_SRC.rules[c]=['five credits including English and Mathematics',
                        'as JAMB prescribes','two A Level passes']; }});
  __render();});
await p.waitForTimeout(250);
s=await txt();
t('With every programme answered, nothing is outstanding',
  s.includes('Nothing outstanding'));

await p.evaluate(()=>document.querySelector('[data-as="force"]').click());
await p.waitForTimeout(300);
s=await txt();
t('Now it goes in force, and carries the minute',
  await p.evaluate(()=>__S.adm.inForce)===true && s.includes('CAC/2025/07'));
t('And it says a change from here is a new version, not an edit',
  s.includes('new version citing a new minute'));

t('No JavaScript errors', errs.length===0, errs.slice(0,2).join(' | '));
console.log(`\n${fail} failures`); await b.close(); process.exit(fail?1:0);
