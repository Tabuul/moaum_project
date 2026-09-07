/* Post-UTME registration: the number first, and nothing else until it is
   found on the list the Academic Office uploaded. */
import pw from '/opt/node-tools/node_modules/playwright/index.js';
const { chromium } = pw; import fs from 'fs';
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1280,height:900}});
const p=await ctx.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
const hooked=fs.readFileSync('_hooks.html','utf8');
fs.writeFileSync('_rg.html','<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{box-sizing:border-box}body{margin:0}</style></head><body>'+hooked+'</body></html>');
await p.goto('file://'+process.cwd()+'/_rg.html'); await p.waitForTimeout(400);
let fail=0; const t=(n,ok,d='')=>{if(!ok)fail++;console.log(`  ${ok?'PASS':'FAIL'}  ${n.padEnd(60)}  ${d}`);};
const txt=()=>p.locator('body').innerText();
const shown=id=>p.evaluate(i=>!!document.getElementById(i), id);
const reg=async()=>{await p.evaluate(()=>{__S.role=null;__S.route='a/register';
  __S.reg={num:"",state:"idle",cand:null,email:"",phone:"",pw:"",pw2:"",show:false,
           err:{email:"",phone:"",pw:"",pw2:""}};
  __S.capsData={utme:null,de:null};__render();});await p.waitForTimeout(200);};

// ── nothing but the number, before anything is typed ─────────────────────
await reg();
t('Only the registration number is asked for at first',
  await shown('rj') && !(await shown('re')) && !(await shown('rw')),
  'no name, no email, no password');
t('Continue is not available yet',
  await p.evaluate(()=>{const b=[...document.querySelectorAll('button')]
    .find(x=>x.textContent.trim()==='Continue'); return !!b && b.disabled;}));

// ── the roll must exist before anybody can be verified ───────────────────
await p.locator('#rj').fill('202661018342CJ'); await p.waitForTimeout(300);
t('With no list uploaded, NOBODY is verified and the screen says so',
  (await txt()).includes('Nobody can be verified yet'),
  'fails closed — a roll anybody may join is not a roll');
t('And no personal fields have appeared', !(await shown('re')));

// ── the Academic Office uploads, from this very screen ───────────────────
await p.evaluate(()=>document.querySelector('[data-reg="loadlist"]').click());
await p.waitForTimeout(400);
let s=await txt();
t('Once the list is uploaded, the candidate is found',
  s.includes('Found on the UTME list'));
t('The name is READ from JAMB, not typed',
  s.includes('Ochanya Faith Aondoaseer') && !(await shown('rn')),
  'shown as a readout, with no input to correct it here');
t('The programme JAMB recorded is shown too', /computer science/i.test(s));
t('Now, and only now, email/phone/password appear',
  await shown('re') && await shown('rp') && await shown('rw') && await shown('rw2'));

// ── a number that is on no list ──────────────────────────────────────────
await p.locator('#rj').fill('202699999999ZZ'); await p.waitForTimeout(350);
s=await txt();
t('An unknown number is refused, and the refusal names all three causes',
  s.includes('not on the list JAMB sent') && s.includes('a digit is wrong') &&
  s.includes('change your institution with JAMB') && s.includes('tranches'));
t('It tells the candidate NOT to travel to the campus over it',
  /Do not travel to the campus/i.test(s));
t('The fields disappear again when the number stops matching',
  !(await shown('re')) && !(await shown('rw')));

// ── half a number is not a refusal ───────────────────────────────────────
await p.locator('#rj').fill('2026610'); await p.waitForTimeout(300);
s=await txt();
t('A number half-typed is not called wrong',
  !s.includes('not on the list JAMB sent'),
  'refusing mid-keystroke teaches the candidate the portal is broken');

// ── lower case, as a candidate on a phone types it ───────────────────────
await p.locator('#rj').fill('202661018342cj'); await p.waitForTimeout(350);
t('Typed in lower case, it still matches',
  (await txt()).includes('Found on the UTME list'));

// ── every field is required, and says so ─────────────────────────────────
t('Email, phone and both passwords are marked required',
  await p.evaluate(()=>['re','rp','rw','rw2'].every(i=>document.getElementById(i).required)));
const press=async()=>{await p.evaluate(()=>document.querySelector('[data-reg="create"]').click());
                      await p.waitForTimeout(250); return p.locator('body').innerText();};
s=await press();
t('An empty form is refused field by field, not in one lump',
  s.includes('An email address is required') && s.includes('A phone number is required') &&
  s.includes('Choose a password'));
t('And it stays on the registration screen',
  await p.evaluate(()=>__S.route)==='a/register');

// ── the email ────────────────────────────────────────────────────────────
await p.locator('#re').fill('faith.ochanya'); s=await press();
t('An address with no @ is refused, and the refusal says what is missing',
  s.includes('not a complete address') && s.includes('@'));
await p.locator('#re').fill('faith@gmail'); s=await press();
t('A domain with no dot is refused', s.includes('not a complete address'));
await p.locator('#re').fill('faith.ochanya@gmial.com'); await p.waitForTimeout(300);
s=await txt();
t('A one-letter provider typo is QUERIED, not refused',
  s.includes('Did you mean gmail.com?') && s.includes('carry on'),
  'gmial.com is a valid address that belongs to nobody');
await p.locator('#re').fill('faith.ochanya@gmail.com'); await p.waitForTimeout(250);
t('A good address clears the query', !(await txt()).includes('Did you mean'));

// ── the phone number: eleven digits ──────────────────────────────────────
await p.locator('#rp').fill('0803411'); s=await press();
t('Seven digits is refused, and counted out',
  /That is <?b?>?7<?\/?b?>? digits/.test(s.replace(/<[^>]+>/g,'')) || s.includes('7 digits'),
  'eleven are needed');
await p.locator('#rp').fill('080341177251'); s=await press();
t('Twelve digits is refused too', s.includes('12 digits'));
await p.locator('#rp').fill('1803 411 7725'); s=await press();
t('Eleven digits not beginning with zero is refused, by name',
  s.includes('begins with a zero'));
t('Letters are simply not accepted into the field',
  await p.evaluate(async()=>{const f=document.getElementById('rp');
    f.value='0803abc4117'; f.dispatchEvent(new Event('input',{bubbles:true}));
    return document.getElementById('rp').value;})==='08034117',
  'a slip of the thumb, not an error message');

await p.locator('#rp').fill('+234 803 411 7725'); await p.waitForTimeout(300);
t('The +234 form is READ, not refused',
  (await txt()).includes('read from the +234 form'), 'converted to 08034117725');
await p.locator('#rp').fill('803 411 7725'); await p.waitForTimeout(300);
t('A number missing its leading zero is read too',
  (await txt()).includes('leading zero was added'));
await p.locator('#rp').fill('0803 411 7725'); await p.waitForTimeout(300);

// ── the password, and seeing it ──────────────────────────────────────────
await p.locator('#rw').fill('short'); s=await press();
t('A password under eight characters is refused', s.includes('Eight characters'));
await p.locator('#rw').fill('a-strong-one'); await p.locator('#rw2').fill('a-strong-onr');
s=await press();
t('Two different passwords are refused, and nothing is lost',
  s.includes('do not match') && s.includes('nothing is lost'));
t('Both boxes keep what was typed',
  await p.evaluate(()=>document.getElementById('rw').value)==='a-strong-one' &&
  await p.evaluate(()=>document.getElementById('rw2').value)==='a-strong-onr');
t('The candidate is still on the registration screen',
  await p.evaluate(()=>__S.route)==='a/register');

t('Both password boxes are hidden by default',
  await p.evaluate(()=>document.getElementById('rw').type)==='password' &&
  await p.evaluate(()=>document.getElementById('rw2').type)==='password');
await p.evaluate(()=>document.querySelector('[data-reg="show"]').click());
await p.waitForTimeout(250);
t('Show reveals BOTH, so the difference can actually be seen',
  await p.evaluate(()=>document.getElementById('rw').type)==='text' &&
  await p.evaluate(()=>document.getElementById('rw2').type)==='text');
t('And it warns about who else can read them',
  (await txt()).includes('standing behind you'));
await p.evaluate(()=>document.querySelector('[data-reg="show"]').click());
await p.waitForTimeout(250);
t('And hides them again',
  await p.evaluate(()=>document.getElementById('rw').type)==='password');

await p.locator('#rw').fill('a-strong-one'); await p.locator('#rw2').fill('a-strong-one');
await p.evaluate(()=>document.querySelector('[data-reg="create"]').click());
await p.waitForTimeout(400);
t('The phone number is stored in the one form it is dialled in',
  await p.evaluate(()=>__S.reg.phone)==='08034117725',
  'not "+234 803 411 7725", not "0803 411 7725"');
t('A complete, valid form carries the candidate into the application',
  await p.evaluate(()=>__S.route)==='a/dashboard' &&
  await p.evaluate(()=>__S.role)==='applicant');
t('And the dashboard shows the same JAMB number',
  (await txt()).includes('202661018342CJ'), 'one candidate, carried through');

// ── the sign-in page names the step ──────────────────────────────────────
await p.evaluate(()=>{__S.role=null;__S.route='login';__render();}); await p.waitForTimeout(200);
await p.evaluate(()=>document.querySelector('[data-role="applicant"]').click());
await p.waitForTimeout(250);
t('The sign-in page offers Post UTME Registration',
  (await txt()).includes('Post UTME Registration'));

t('No JavaScript errors', errs.length===0, errs.slice(0,2).join(' | '));
console.log(`\n${fail} failures`); await b.close(); process.exit(fail?1:0);
