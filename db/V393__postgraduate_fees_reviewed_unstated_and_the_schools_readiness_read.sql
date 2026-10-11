-- V393 — What V391 left for the Bursary and the Directorate to see, read only.
--
--   V391 stopped a full-time fee line from reaching a postgraduate student. What a PG student paid before against such a
--   line stays paid; the student may now hold more than they owe. And a PG student owes nothing until the Bursary states
--   the School's lines, so registration waits on that. Nothing here changes a fee, a payment or a reference:
--
--   1 · finance.pg_fee_review(session)  the PG students whose confirmed school-fee payments of the session exceed what they
--                                       owe under the School's lines, with the references paid, for the Bursary to decide
--                                       each case by its own refund process (a refund is never made here).
--   2 · finance.pg_unstated(session)    the live PG students (admitted, active, on probation) with no fee line stated for
--                                       the session, by level and programme: the lines the Bursary has still to state.
--   3 · admissions.pg_readiness()       whether PG course registration can open in the School's session: a current
--                                       session on the School's calendar, a semester open within its dates, the School's
--                                       classes set up, and a fee line stated for every live PG student.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V393: postgraduate fees reviewed, the unstated listed, and the School''s readiness read', true);

-- ── the one test of who is a postgraduate student, as V391 reads it ─────────────────────────────────────────────────
CREATE FUNCTION people.is_postgraduate(p_entry_mode text, p_category text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
    SELECT coalesce(p_entry_mode = 'POSTGRADUATE' OR p_category = 'POST GRADUATE', false)
$fn$;
COMMENT ON FUNCTION people.is_postgraduate(text, text) IS
  'V393: a postgraduate student — entry mode POSTGRADUATE, or a programme of category POST GRADUATE (V391''s test).';

-- ── 1 · PG students who paid more than they owe ─────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.pg_fee_review(p_session text)
RETURNS TABLE (student_id uuid, admission_no text, matric_no text, surname text, other_names text, status text,
               programme_code text, programme text, level integer, due numeric, paid numeric, excess numeric, payments jsonb)
LANGUAGE sql STABLE AS $fn$
    WITH pg AS (
        SELECT s.id, s.admission_no, s.matric_no, s.surname, s.other_names, s.status, s.programme_code, p.name AS programme, s.current_level
          FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE people.is_postgraduate(s.entry_mode, p.category)
           AND EXISTS (SELECT 1 FROM finance.payment_reference r
                        WHERE r.student_id = s.id AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'))
    SELECT pg.id, pg.admission_no, pg.matric_no, pg.surname, pg.other_names, pg.status, pg.programme_code, pg.programme, pg.current_level,
           fp.due, fp.paid, fp.paid - fp.due,
           (SELECT jsonb_agg(jsonb_build_object('reference', r.reference, 'amount', r.amount, 'purpose', r.purpose, 'confirmedAt', r.confirmed_at,
                                                'channel', r.channel, 'receiptNo', r.receipt_no) ORDER BY r.confirmed_at)
              FROM finance.payment_reference r
             WHERE r.student_id = pg.id AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%')
      FROM pg CROSS JOIN LATERAL finance.position(pg.id, p_session) fp
     WHERE fp.paid > fp.due
     ORDER BY fp.paid - fp.due DESC, pg.surname, pg.other_names;
$fn$;
COMMENT ON FUNCTION finance.pg_fee_review(text) IS
  'V393: the PG students whose confirmed school-fee payments of a session exceed what they owe under the School''s lines (V391), with the references paid. Read only: the Bursary decides each case; nothing is refunded here.';

-- ── 2 · live PG students with no fee line stated ────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.pg_unstated(p_session text)
RETURNS TABLE (level integer, programme_code text, programme text, students bigint)
LANGUAGE sql STABLE AS $fn$
    SELECT s.current_level, s.programme_code, p.name, count(*)
      FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
     WHERE people.is_postgraduate(s.entry_mode, p.category)
       AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
       AND NOT finance.fee_stated(s.id, p_session)
     GROUP BY s.current_level, s.programme_code, p.name
     ORDER BY s.current_level, s.programme_code;
$fn$;
COMMENT ON FUNCTION finance.pg_unstated(text) IS
  'V393: the live PG students (admitted, active, on probation) with no fee line stated for a session, by level and programme — the lines the Bursary has still to state (V391).';

-- ── 3 · whether PG course registration can open ─────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.pg_readiness()
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT admissions.pg_current_session() AS name),
         cur AS (SELECT EXISTS (SELECT 1 FROM admissions.pg_academic_session WHERE state = 'CURRENT') AS yes),
         sem AS (SELECT min(m.number) AS number FROM admissions.pg_semester m, s
                  WHERE m.session = s.name AND m.state = 'OPEN'
                    AND (m.registration_opens IS NULL OR m.registration_opens <= current_date)
                    AND (m.registration_closes IS NULL OR m.registration_closes >= current_date)),
         cls AS (SELECT count(*) AS n FROM catalogue.offering o, s WHERE o.session = s.name AND o.stream = 'PG'),
         live AS (SELECT count(*) AS n FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                   WHERE people.is_postgraduate(st.entry_mode, p.category) AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
         uns AS (SELECT coalesce(sum(u.students), 0) AS n FROM s, finance.pg_unstated(s.name) u)
    SELECT jsonb_build_object(
             'session', s.name, 'current', cur.yes, 'semester', sem.number, 'classes', cls.n,
             'students', live.n, 'unstated', uns.n, 'feesStated', live.n > 0 AND uns.n = 0,
             'ready', cur.yes AND sem.number IS NOT NULL AND cls.n > 0 AND live.n > 0 AND uns.n = 0)
      FROM s, cur, sem, cls, live, uns;
$fn$;
COMMENT ON FUNCTION admissions.pg_readiness() IS
  'V393: whether PG course registration can open in the School''s session — a current session on its calendar, a semester open within its dates, its classes set up, and a fee line stated for every live PG student. Read only.';

COMMIT;
