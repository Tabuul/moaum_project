#!/usr/bin/env node
/* A load test of the CBT engine (V322) against a running API and a scratch database.

   It seeds a session, a GST course and its offering, a bank of questions, an examination with a fixed 50-question
   paper, and N students registered on the offering with the GST fee stated and paid on the ledger (so eligibility
   runs the real path). Then every candidate, concurrently: starts, reads the paper, saves answers in batches,
   sends two heartbeats and submits — while an office screen polls the live monitor every two seconds. It reports
   the latency of each call kind (p50, p95, p99, max, errors), the throughput, the monitor's latency, and the
   database's connection count as the run peaked. Nothing here touches the real portal: point it at a scratch
   database and a local API.

   V374 adds --mode hall: a full CBT hall as it is sat. The candidates are seated in one sitting with an invigilator; all of them
   start within --ramp seconds (default 5), then each saves an answer every --every seconds (default 5 — several times a real
   candidate's pace, which the room debounces to one save per answer) and sends the room's heartbeat every 30 seconds, for
   --minutes minutes (default 3); then time is up and every screen submits within a second and a half, as the room's own clock
   does. Meanwhile the office's live monitor is read every 2 seconds and the invigilator's board every 15. The default mode,
   burst, is the stress test: every candidate answers the whole paper as fast as the network allows.
   The questions seeded are approved by a moderator (V374), as a paper requires.

   Usage:
     DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54329/fresh4 \
     API=http://localhost:8099 SECRET=test-only-secret-of-at-least-thirty-two-bytes \
     node api/scripts/cbt-load.mjs --n 500 [--questions 50] [--waves 1] [--mode burst|hall] [--minutes 3] [--every 5] [--ramp 5] [--teardown]

   psql must be on PATH (or PSQL=... given). The seed is idempotent per --n; --teardown removes everything it made. */
import { createHmac, randomUUID } from "node:crypto";
import { execFile, execFileSync } from "node:child_process";
import { promisify } from "node:util";

const args = process.argv.slice(2).reduce((acc, a, i, all) => { if (a.startsWith("--")) acc[a.slice(2)] = all[i + 1] && !all[i + 1].startsWith("--") ? all[i + 1] : "true"; return acc; }, {});
const N = Number(args.n ?? 100);
const QUESTIONS = Number(args.questions ?? 50);
const WAVES = Number(args.waves ?? 1);
const MODE = args.mode === "hall" ? "hall" : "burst";
const MINUTES = Number(args.minutes ?? 3);
const EVERY = Number(args.every ?? 5);
const RAMP = Number(args.ramp ?? 5);
/* the invigilator of the hall (V374): a member of staff the seed makes and the teardown removes */
const INVIGILATOR = "00000000-0000-4000-8000-00000000c0b1";
const API = process.env.API ?? "http://localhost:8099";
const SECRET = process.env.SECRET ?? "test-only-secret-of-at-least-thirty-two-bytes";
const DB = process.env.DATABASE_URL;
const PSQL = process.env.PSQL ?? "psql";
const SESSION = "2199/2200";
const COURSE = "GST 999";
if (!DB) { console.error("DATABASE_URL is required (a scratch database)"); process.exit(2); }

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
function token(sub, offices) {
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: "HS256", typ: "JWT" }), body = b64({ sub, iat: now, exp: now + 7200, offices });
  return `${head}.${body}.${createHmac("sha256", SECRET).update(`${head}.${body}`).digest("base64url")}`;
}
function sql(text) {
  return execFileSync(PSQL, [DB, "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", text], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).replace(/\r/g, "").trim();
}
/* while the run is on, the database is read without blocking the event loop, so no candidate's call waits on it */
const execAsync = promisify(execFile);
async function sqlAsync(text) {
  const { stdout } = await execAsync(PSQL, [DB, "-X", "-q", "-At", "-c", text], { encoding: "utf8" });
  return stdout.replace(/\r/g, "").trim();
}

/* ── seed ── */
function seed() {
  console.log(`seeding ${N} candidates, ${QUESTIONS}-question paper, session ${SESSION}…`);
  sql(`
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true), set_config('moaum.actor_office', 'ict', true), set_config('moaum.reason', 'cbt load test seed', true);
INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), '${SESSION}', date '2199-10-01', date '2200-08-31') ON CONFLICT (name) DO NOTHING;
INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
SELECT '${COURSE}', 'Load General Studies', 2, 1, 100, p.dept_code, 'GST', 'LIVE' FROM ref.programme p WHERE p.code = 'C00023' ON CONFLICT (code) DO NOTHING;
INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('${COURSE}', 'C00023', 100, 'GST') ON CONFLICT DO NOTHING;
INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), '${COURSE}', '${SESSION}', 1) ON CONFLICT (course_code, session, semester) DO NOTHING;
INSERT INTO assessment.question (course_code, topic, stem, options, answer, kind, marks)
SELECT '${COURSE}', 'T' || (g % 5), 'Load question ' || g || ': which option is the key?', '["alpha","beta","gamma","delta"]'::jsonb, g % 4, 'MCQ', 1
  FROM generate_series(1, ${Math.max(QUESTIONS, 100)}) g
 WHERE (SELECT count(*) FROM assessment.question WHERE course_code = '${COURSE}') < ${Math.max(QUESTIONS, 100)};
-- V374: a question goes on a paper once a moderator other than its setter approves it
UPDATE assessment.question SET moderation = 'APPROVED', moderated_version = version, moderated_by = '00000000-0000-4000-8000-00000000c0b2', moderated_at = now()
 WHERE course_code = '${COURSE}' AND moderation <> 'APPROVED';
DO $$
DECLARE i int; sid uuid; reg uuid; off uuid; ref text;
BEGIN
    SELECT id INTO off FROM catalogue.offering WHERE course_code = '${COURSE}' AND session = '${SESSION}' AND semester = 1;
    IF NOT EXISTS (SELECT 1 FROM finance.gst_fee WHERE session = '${SESSION}' AND superseded_at IS NULL) THEN
        PERFORM finance.state_gst_fee('${SESSION}', 5000, NULL, NULL, NULL, NULL, current_date, 'load', NULL, 'bursar');
    END IF;
    FOR i IN 1..${N} LOOP
        SELECT id INTO sid FROM people.student WHERE admission_no = 'MOAUM/ADM/99/' || lpad(i::text, 6, '0');
        IF sid IS NULL THEN
            sid := gen_random_uuid();
            INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
            VALUES (sid, 'MOAUM/ADM/99/' || lpad(i::text, 6, '0'), 'MOAUM/LOAD/99/' || i, 'ZZLOAD' || i, 'Invented', 'C00023', 'UTME', '${SESSION}', 100, 100, 'ACTIVE', now());
        END IF;
        -- paid first: the registration gate (V314) holds a GST course until the fee is confirmed on the ledger
        IF NOT (SELECT entitled FROM finance.gst_entitlement(sid, '${SESSION}')) THEN
            ref := finance.new_gst_reference(sid, '${SESSION}');
            PERFORM finance.confirm_payment(ref, 'CARD', 'load');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM registration.course_registration WHERE student_id = sid AND session = '${SESSION}' AND semester = 1) THEN
            reg := registration.student_draft(sid, '${SESSION}', 1);
            PERFORM registration.student_choose(reg, ARRAY[off]);
            UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = reg;
        END IF;
    END LOOP;
END $$;
COMMIT;`);
  const examId = sql(`
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true), set_config('moaum.actor_office', 'gst', true), set_config('moaum.reason', 'cbt load test exam', true), set_config('moaum.maintenance', 'on', true);
DELETE FROM assessment.cbt_event WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}');
DELETE FROM assessment.cbt_answer WHERE attempt_id IN (SELECT id FROM assessment.cbt_attempt WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}'));
DELETE FROM assessment.cbt_result WHERE attempt_id IN (SELECT id FROM assessment.cbt_attempt WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}'));
DELETE FROM assessment.cbt_attempt WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}');
DELETE FROM assessment.cbt_exam_question WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}');
DELETE FROM assessment.cbt_exam WHERE course_code = '${COURSE}';
WITH e AS (SELECT (assessment.cbt_new_exam('GST', (SELECT id FROM catalogue.offering WHERE course_code = '${COURSE}' AND session = '${SESSION}' AND semester = 1),
                   'Load CBT ${N}', NULL, 60, 0, 'FIXED', true, true, 50, 1, 'STANDARD', 'REMOTE', 2, 'WARN', 'CONTINUE', now() - interval '1 minute', now() + interval '3 hours')).id AS id),
     q AS (INSERT INTO assessment.cbt_exam_question (exam_id, question_id, ordinal)
           SELECT e.id, x.id, row_number() OVER (ORDER BY x.stem) FROM e, (SELECT id, stem FROM assessment.question WHERE course_code = '${COURSE}' AND active ORDER BY stem LIMIT ${QUESTIONS}) x RETURNING exam_id)
SELECT DISTINCT exam_id FROM q;
COMMIT;`).split("\n").filter(Boolean).pop();
  sql(`SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', false), set_config('moaum.actor_office', 'gst', false), set_config('moaum.reason', 'cbt load test publish', false); SELECT (assessment.cbt_exam_action('${examId}', 'publish', NULL)).state;`);
  const students = sql(`SELECT id FROM people.student WHERE surname LIKE 'ZZLOAD%' AND admission_no LIKE 'MOAUM/ADM/99/%' ORDER BY admission_no LIMIT ${N}`).split("\n").filter(Boolean);
  console.log(`exam ${examId} published; ${students.length} candidates`);
  let sittingId = null;
  if (MODE === "hall") {
    // V374: one sitting holding every candidate registered (those of an earlier, larger run too), begun half a minute ago, with an invigilator
    sittingId = sql(`
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true), set_config('moaum.actor_office', 'gst', true), set_config('moaum.reason', 'cbt load test hall', true);
INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES ('${INVIGILATOR}', 'LOAD/INV/1', 'ZZLOADINV', 'Invented') ON CONFLICT (id) DO NOTHING;
INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
SELECT gen_random_uuid(), '${INVIGILATOR}', 'hod', 'department', p.dept_code, 'load test', '00000000-0000-0000-0000-000000000000', current_date FROM ref.programme p
 WHERE p.code = 'C00023' AND NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = '${INVIGILATOR}');
CREATE TEMP TABLE hall ON COMMIT DROP AS SELECT (assessment.cbt_add_sitting('${examId}', 'Load hall', 'Load CBT centre', now() - interval '30 seconds', now() + interval '2 hours', 5000)).id;
SELECT seated FROM assessment.cbt_seat_all('${examId}', 'NUMBER');
SELECT (assessment.cbt_assign_invigilator((SELECT id FROM hall), '${INVIGILATOR}', true)).chief;
SELECT id FROM hall;
COMMIT;`).split("\n").filter(Boolean).pop();
    console.log(`hall ${sittingId}: ${students.length} seated, invigilator ${INVIGILATOR}`);
  }
  return { examId, students, sittingId };
}

function teardown() {
  console.log("tearing down the load data…");
  sql(`
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true), set_config('moaum.actor_office', 'ict', true), set_config('moaum.reason', 'cbt load test teardown', true), set_config('moaum.maintenance', 'on', true);
DELETE FROM assessment.cbt_event WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}');
DELETE FROM assessment.cbt_answer WHERE attempt_id IN (SELECT id FROM assessment.cbt_attempt WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}'));
DELETE FROM assessment.cbt_result WHERE attempt_id IN (SELECT id FROM assessment.cbt_attempt WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}'));
DELETE FROM assessment.cbt_attempt WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}');
DELETE FROM assessment.cbt_exam_question WHERE exam_id IN (SELECT id FROM assessment.cbt_exam WHERE course_code = '${COURSE}');
DELETE FROM assessment.cbt_exam WHERE course_code = '${COURSE}';
DELETE FROM iam.office_assignment WHERE person_id = '${INVIGILATOR}';
DELETE FROM iam.person WHERE id = '${INVIGILATOR}';
DELETE FROM platform.notice WHERE about_kind = 'student' AND about_id IN (SELECT id FROM people.student WHERE surname LIKE 'ZZLOAD%');
DELETE FROM registration.entry WHERE registration_id IN (SELECT id FROM registration.course_registration WHERE student_id IN (SELECT id FROM people.student WHERE surname LIKE 'ZZLOAD%'));
DELETE FROM registration.course_registration WHERE student_id IN (SELECT id FROM people.student WHERE surname LIKE 'ZZLOAD%');
DELETE FROM finance.payment_reference WHERE student_id IN (SELECT id FROM people.student WHERE surname LIKE 'ZZLOAD%');
DELETE FROM people.student_contact WHERE student_id IN (SELECT id FROM people.student WHERE surname LIKE 'ZZLOAD%');
DELETE FROM people.student WHERE surname LIKE 'ZZLOAD%';
DELETE FROM assessment.question WHERE course_code = '${COURSE}';
DELETE FROM catalogue.offering WHERE course_code = '${COURSE}';
DELETE FROM catalogue.course_offer WHERE course_code = '${COURSE}';
DELETE FROM catalogue.course WHERE code = '${COURSE}';
UPDATE finance.gst_fee SET superseded_at = now() WHERE session = '${SESSION}' AND superseded_at IS NULL;
COMMIT;`);
  console.log("done");
}

/* ── the run ── */
const samples = {};
const errors = {};
function record(kind, ms, ok) {
  (samples[kind] ??= []).push(ms);
  if (!ok) errors[kind] = (errors[kind] ?? 0) + 1;
}
async function call(kind, method, path, body, tok, extra = {}) {
  const t0 = performance.now();
  let ok = false, json = null;
  try {
    const r = await fetch(API + path, { method, headers: { "Content-Type": "application/json", Authorization: `Bearer ${tok}`, "X-Reason": "load test", ...extra }, body: body == null ? undefined : JSON.stringify(body) });
    json = await r.json().catch(() => null);
    ok = r.ok;
    if (!ok && (errors[`${kind}:detail`] ?? 0) < 3) { errors[`${kind}:detail`] = (errors[`${kind}:detail`] ?? 0) + 1; console.error(`${kind} ${r.status}`, JSON.stringify(json).slice(0, 200)); }
  } catch (e) {
    if ((errors[`${kind}:detail`] ?? 0) < 3) { errors[`${kind}:detail`] = (errors[`${kind}:detail`] ?? 0) + 1; console.error(`${kind} failed`, e.message); }
  }
  record(kind, performance.now() - t0, ok);
  return ok ? json : null;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function candidate(examId, studentId) {
  const tok = token(studentId, ["student"]);
  await sleep(Math.random() * 2000);
  const started = await call("start", "POST", `/api/v1/me/cbt/exams/${examId}/start`, {}, tok);
  if (!started) return;
  const hdr = { "X-Attempt-Token": started.token };
  const room = await call("paper", "GET", `/api/v1/me/cbt/attempts/${started.attemptId}`, null, tok, hdr);
  if (!room) return;
  const qs = room.questions;
  for (let i = 0; i < qs.length; i += 5) {
    const batch = qs.slice(i, i + 5).map((q) => ({ q: q.id, a: [Math.floor(Math.random() * q.options.length)] }));
    await call("save", "PUT", `/api/v1/me/cbt/attempts/${started.attemptId}/answers`, { answers: batch }, tok, hdr);
    await sleep(50 + Math.random() * 150);
    if (i === 10 || i === 30) await call("ping", "POST", `/api/v1/me/cbt/attempts/${started.attemptId}/ping`, {}, tok, hdr);
    if (i === 20) await call("event", "POST", `/api/v1/me/cbt/attempts/${started.attemptId}/events`, { events: [{ kind: "TAB_SWITCH", detail: "load" }] }, tok, hdr);
  }
  await call("submit", "POST", `/api/v1/me/cbt/attempts/${started.attemptId}/submit`, {}, tok, hdr);
}

/* V374: a candidate in a full hall — start with everyone, save at the hall's pace with the room's heartbeat, submit when time is up */
async function hallCandidate(examId, studentId, endAt) {
  const tok = token(studentId, ["student"]);
  await sleep(Math.random() * RAMP * 1000);
  const started = await call("start", "POST", `/api/v1/me/cbt/exams/${examId}/start`, {}, tok);
  if (!started) return;
  const hdr = { "X-Attempt-Token": started.token };
  const room = await call("paper", "GET", `/api/v1/me/cbt/attempts/${started.attemptId}`, null, tok, hdr);
  if (!room) return;
  const qs = room.questions;
  let i = 0;
  let nextPing = Date.now() + 30000;
  await sleep(Math.random() * EVERY * 1000);
  while (Date.now() < endAt) {
    const q = qs[i % qs.length];
    i++;
    await call("save", "PUT", `/api/v1/me/cbt/attempts/${started.attemptId}/answers`, { answers: [{ q: q.id, a: [Math.floor(Math.random() * q.options.length)] }] }, tok, hdr);
    if (Date.now() >= nextPing) { await call("ping", "POST", `/api/v1/me/cbt/attempts/${started.attemptId}/ping`, {}, tok, hdr); nextPing += 30000; }
    await sleep(Math.min(EVERY * 1000 * (0.5 + Math.random()), Math.max(0, endAt - Date.now())));
  }
  // time is up: every screen's own clock submits it, all within a second or two of each other
  await sleep(Math.random() * 1500);
  await call("submit", "POST", `/api/v1/me/cbt/attempts/${started.attemptId}/submit`, {}, tok, hdr);
}

async function boardLoop(sittingId, stop) {
  const tok = token(INVIGILATOR, ["hod"]);
  while (!stop.done) {
    await call("board", "GET", `/api/v1/cbt/sittings/${sittingId}/board`, null, tok);
    await sleep(15000);
  }
}

async function monitorLoop(examId, stop) {
  const tok = token(randomUUID(), ["gst"]);
  let cursor = null;
  while (!stop.done) {
    const j = await call("monitor", "GET", `/api/v1/cbt/exams/${examId}/monitor${cursor ? `?since=${encodeURIComponent(cursor)}` : ""}`, null, tok);
    if (j) cursor = j.cursor;
    const conns = Number(await sqlAsync("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND backend_type = 'client backend'"));
    stop.maxConns = Math.max(stop.maxConns ?? 0, conns);
    await sleep(2000);
  }
}

function pct(arr, p) { const s = [...arr].sort((a, b) => a - b); return s.length ? s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))] : 0; }

async function main() {
  if (args.teardown) { teardown(); return; }
  const { examId, students, sittingId } = seed();
  const stop = { done: false };
  const mon = monitorLoop(examId, stop);
  const board = sittingId ? boardLoop(sittingId, stop) : Promise.resolve();
  const t0 = performance.now();
  if (MODE === "hall") {
    console.log(`a hall of ${students.length}: all start within ${RAMP} s, save every ~${EVERY} s with a heartbeat every 30 s for ${MINUTES} min, then submit together — against ${API}…`);
    const endAt = Date.now() + (RAMP + MINUTES * 60) * 1000;
    await Promise.all(students.map((s) => hallCandidate(examId, s, endAt)));
  } else {
    console.log(`running ${students.length} candidates in ${WAVES} wave(s) against ${API}…`);
    const per = Math.ceil(students.length / WAVES);
    for (let w = 0; w < WAVES; w++) {
      await Promise.all(students.slice(w * per, (w + 1) * per).map((s) => candidate(examId, s)));
    }
  }
  const total = (performance.now() - t0) / 1000;
  stop.done = true;
  await mon;
  await board;
  const counts = sql(`SELECT candidates || ' candidates, ' || submitted || ' submitted, ' || in_progress || ' in progress, ' || scored || ' scored' FROM assessment.cbt_monitor_counts('${examId}')`);
  console.log(`\n${MODE} · ${students.length} candidates · ${QUESTIONS} questions · ${total.toFixed(1)} s wall · ${counts}`);
  console.log("call        n       p50 ms   p95 ms   p99 ms   max ms   errors");
  for (const [k, arr] of Object.entries(samples)) {
    console.log(`${k.padEnd(10)} ${String(arr.length).padStart(6)} ${pct(arr, 50).toFixed(0).padStart(8)} ${pct(arr, 95).toFixed(0).padStart(8)} ${pct(arr, 99).toFixed(0).padStart(8)} ${Math.max(...arr).toFixed(0).padStart(8)} ${String(errors[k] ?? 0).padStart(8)}`);
  }
  const calls = Object.values(samples).reduce((n, a) => n + a.length, 0);
  console.log(`${calls} calls · ${(calls / total).toFixed(0)} calls/s · database client connections at peak: ${stop.maxConns}`);
}
main().catch((e) => { console.error(e); process.exit(1); });
