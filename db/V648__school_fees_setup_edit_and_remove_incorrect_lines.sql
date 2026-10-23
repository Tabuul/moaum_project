-- V648: school fees setup — edit and remove incorrect lines. The University's master prompt of 23 October 2026 ("SCHOOL FEES SETUP
-- STRUCTURE — EDIT AND REMOVE INCORRECT LEVELS"): some levels were added to faculties and programmes by mistake (Industrial Chemistry
-- 600 Level); the Bursary must edit a line, remove a line never used, archive a line already used, and keep every payment, reference,
-- receipt and ledger entry as it was.
--
-- The fee setup is finance.fee_schedule: one line per item, amount and scope (session, level, entry mode, faculty, programme, group,
-- semester, indigeneship, spillover year). A student's charge is computed from the lines in force (ended_at IS NULL) every time it is
-- read; a payment reference (the invoice) keeps the amount it was generated with, and nothing references a line by key. So editing or
-- ending a line never changes a reference, a payment or the ledger; it changes what is owed from then on.
--
--   · finance.fee_setup_grant: what each office may do with the fee setup — VIEW_FEE_SETUP, CREATE_FEE_STRUCTURE, EDIT_FEE_STRUCTURE,
--     REMOVE_FEE_STRUCTURE, DEACTIVATE_FEE_STRUCTURE, VIEW_FEE_STRUCTURE_HISTORY, EXPORT_FEE_STRUCTURE. The Bursar's office (and the
--     platform) hold all; the Students Account Officer keeps what V520 gave (state, edit, end — deactivate — the lines, read the history)
--     and is not given REMOVE; the offices that read the schedule read it. Checked by the API and by the functions below.
--   · finance.fee_line_usage(lines): whether a line has been used, decided here and nowhere else — the students it charges now (the
--     charge engine's own match, every semester, as if the line stood), and the school-fees references (invoices) and payments of its
--     session, generated or recorded while it stood, by students within its scope at any level the session knows them at (the record,
--     the session's enrolment, its course registration), with the ledger entries posted for them. NONE (never used), STUDENTS (charged
--     now, nothing generated), INVOICE, PAYMENT, LEDGER. Only NONE may be removed permanently.
--   · finance.remove_fee_lines(lines, mode, reason code, reason, apply): REMOVE (a line never used deleted; a used one CANNOT_REMOVE,
--     unchanged), DEACTIVATE (archived: ended, kept, no longer charged), AUTO (each line removed or archived, as its use decides) — a
--     preview without apply, the same answer with it. A reason is required (added in error, wrong level, duplicate, wrong programme,
--     faculty, session or semester, replaced by a corrected line, other with a description). Every removal and archive is kept in
--     finance.fee_line_change with the line as it was, its use, the reason, who and when; the audit trail carries the reason too.
--   · finance.edit_fee_line(line, values, reason): a line never used to generate an invoice or a payment is corrected in place; a line
--     that was is versioned — ended, kept, and the corrected line stated beside it (finance.fee_line_change names both), so the
--     configuration an invoice was generated under stays on record.
--   · finance.fee_line_history(line): every version of a line and the lines it replaced or that replaced it, from the audit trail.
--   · finance.fee_levels_of(programme) and finance.fee_line_level_problem(level, programme, faculty, spillover): the levels a line may
--     name, read from the programme structure (people.programme_levels, as the programme swap reads it; a spillover line names the
--     final level) — a line outside it is flagged, and a new or edited line refused.
-- Nothing deletes or changes a payment reference, a receipt, a gateway transaction, a wallet entry or a ledger entry.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V648: school fees setup — edit and remove incorrect lines (the University, 23 October 2026)', true);

-- ── who may do what with the fee setup, by office ──
CREATE TABLE finance.fee_setup_grant (
    office_code text NOT NULL,
    permission text NOT NULL CHECK (permission IN ('VIEW_FEE_SETUP', 'CREATE_FEE_STRUCTURE', 'EDIT_FEE_STRUCTURE', 'REMOVE_FEE_STRUCTURE',
                                                   'DEACTIVATE_FEE_STRUCTURE', 'VIEW_FEE_STRUCTURE_HISTORY', 'EXPORT_FEE_STRUCTURE')),
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (office_code, permission)
);
SELECT audit.attach('finance.fee_setup_grant');
COMMENT ON TABLE finance.fee_setup_grant IS
  'V648: what each office may do with the school fees setup. REMOVE_FEE_STRUCTURE (a line never used deleted) is the Bursar''s; the Students Account Officer states, edits and deactivates (V520) but does not remove. The API and finance.remove_fee_lines / finance.edit_fee_line check the acting office against it.';

INSERT INTO finance.fee_setup_grant (office_code, permission)
SELECT o, p FROM unnest(ARRAY['bursar', 'super']) o
CROSS JOIN unnest(ARRAY['VIEW_FEE_SETUP', 'CREATE_FEE_STRUCTURE', 'EDIT_FEE_STRUCTURE', 'REMOVE_FEE_STRUCTURE', 'DEACTIVATE_FEE_STRUCTURE',
                        'VIEW_FEE_STRUCTURE_HISTORY', 'EXPORT_FEE_STRUCTURE']) p
UNION ALL
SELECT 'studentaccounts', p FROM unnest(ARRAY['VIEW_FEE_SETUP', 'CREATE_FEE_STRUCTURE', 'EDIT_FEE_STRUCTURE', 'DEACTIVATE_FEE_STRUCTURE',
                                              'VIEW_FEE_STRUCTURE_HISTORY', 'EXPORT_FEE_STRUCTURE']) p
UNION ALL
SELECT o, p FROM unnest(ARRAY['registrar', 'dregistrar', 'academic', 'audit', 'deputyaudit', 'ict', 'admin', 'vc', 'dvc']) o
CROSS JOIN unnest(ARRAY['VIEW_FEE_SETUP', 'VIEW_FEE_STRUCTURE_HISTORY', 'EXPORT_FEE_STRUCTURE']) p
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION finance.fee_setup_permissions(p_office text)
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce((SELECT array_agg(g.permission ORDER BY g.permission) FROM finance.fee_setup_grant g WHERE g.office_code = p_office), '{}')
$$;

CREATE OR REPLACE FUNCTION finance.fee_setup_may(p_office text, p_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (SELECT 1 FROM finance.fee_setup_grant g WHERE g.office_code = coalesce(p_office, '') AND g.permission = p_permission)
$$;

-- the acting office (moaum.actor_office, set for every request) must hold the permission
CREATE OR REPLACE FUNCTION finance.fee_setup_require(p_permission text)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF NOT finance.fee_setup_may(nullif(current_setting('moaum.actor_office', true), ''), p_permission) THEN
        RAISE EXCEPTION 'FEE_SETUP_NOT_PERMITTED: your office does not hold % on the school fees setup', p_permission USING ERRCODE = '42501';
    END IF;
END $$;

-- ── the levels a line may name: the programme structure ──
CREATE OR REPLACE FUNCTION finance.fee_levels_of(p_programme text)
RETURNS integer[]
LANGUAGE sql
STABLE
AS $$
    -- people.programme_levels is the programme structure the programme swap reads (a postgraduate programme 700, 800, 900; another
    -- 100 to its final level); the charge engine's final level (finance.final_level) is read beside it, so the two never disagree
    SELECT CASE WHEN p.category = 'POST GRADUATE' THEN people.programme_levels(p.code)
                ELSE (SELECT array_agg(l ORDER BY l)
                        FROM generate_series(100, greatest(100, coalesce((SELECT max(x) FROM unnest(people.programme_levels(p.code)) x), 100),
                                                         coalesce(finance.final_level(p.code), 100)), 100) l) END
      FROM ref.programme p WHERE p.code = p_programme
$$;
COMMENT ON FUNCTION finance.fee_levels_of(text) IS
  'V648: the levels a fee line for this programme may name — its programme structure (people.programme_levels), up to the final level the charge engine reads.';

CREATE OR REPLACE FUNCTION finance.fee_line_level_problem(p_level integer, p_programme text, p_faculty text, p_spillover boolean)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    WITH progs AS MATERIALIZED (
        SELECT p.code, p.name, p.category, finance.fee_levels_of(p.code) AS levels, finance.final_level(p.code) AS final
          FROM ref.programme p
         WHERE (p_programme IS NOT NULL AND p.code = p_programme)
            OR (p_programme IS NULL AND NOT coalesce(p.archived, false) AND (p_faculty IS NULL OR p.faculty_code = p_faculty))),
    scope AS (SELECT CASE WHEN p_faculty IS NULL THEN 'of the University'
                          ELSE 'of ' || coalesce((SELECT f.name FROM ref.faculty f WHERE f.code = p_faculty), 'the faculty ' || p_faculty) END AS words)
    SELECT CASE
        WHEN p_level IS NULL OR NOT EXISTS (SELECT 1 FROM progs) THEN NULL
        WHEN p_programme IS NOT NULL THEN
            (SELECT CASE WHEN coalesce(p_spillover, false) AND g.category IS DISTINCT FROM 'POST GRADUATE' AND p_level <> g.final
                              THEN format('A spillover line names the programme''s final level: %s ends at %s Level, not %s Level.', g.name, g.final, p_level)
                         WHEN NOT p_level = ANY (coalesce(g.levels, '{}'))
                              THEN format('%s runs %s (its programme structure), not %s Level.', g.name,
                                          coalesce(policy.levels_words(g.levels), 'no level'), p_level)
                    END
               FROM progs g)
        WHEN coalesce(p_spillover, false) THEN
            CASE WHEN NOT EXISTS (SELECT 1 FROM progs g WHERE g.final = p_level)
                 THEN format('No programme %s ends at %s Level: a spillover line names a programme''s final level.', (SELECT words FROM scope), p_level) END
        WHEN NOT EXISTS (SELECT 1 FROM progs g WHERE p_level = ANY (coalesce(g.levels, '{}')))
             THEN format('No programme %s runs to %s Level (the programme structure).', (SELECT words FROM scope), p_level)
    END
$$;
COMMENT ON FUNCTION finance.fee_line_level_problem(integer, text, text, boolean) IS
  'V648: why a fee line''s level is outside the programme structure (NULL when it is within): a programme line at a level the programme does not run, a faculty or University line at a level no programme of it runs, a spillover line not at a final level.';

-- ── whether a line has been used: decided here, never by the screen ──
CREATE OR REPLACE FUNCTION finance.fee_line_usage(p_lines uuid[])
RETURNS TABLE(line_id uuid, session text, active boolean, stated_at timestamptz, students integer, references_generated integer,
              references_open integer, references_paid integer, amount_paid numeric, ledger_entries integer, used_by text, removable boolean,
              message text)
LANGUAGE sql
STABLE
AS $$
    WITH l AS MATERIALIZED (
        SELECT f.id, f.session, f.item, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.fee_group, f.indigene, f.spillover,
               f.spill_year, f.ended_at, g.applies_category,
               (SELECT min(e.occurred_at) FROM audit.entries e
                 WHERE e.subject_type = 'finance.fee_schedule' AND e.subject_id = f.id AND e.action = 'INSERT') AS stated_at
          FROM finance.fee_schedule f
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.id = ANY (p_lines)),
    sess AS MATERIALIZED (SELECT DISTINCT l.session FROM l),
    home AS (SELECT lower(fs.home_state) AS home_state FROM finance.fee_setting fs WHERE fs.id = 1),
    basis AS MATERIALIZED (SELECT finance.spill_basis() AS b),
    fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    src AS MATERIALIZED (SELECT s.session, x.faculty_code, x.source_code FROM sess s CROSS JOIN LATERAL finance.fee_sources(s.session) x),
    -- now: the students each line charges, by the charge engine's own match (finance.fee_sums), every semester, as if it stood
    keys AS MATERIALIZED (
        SELECT s.session, fp.profile_key, fp.programme_code, fp.faculty_code, fp.category, fp.current_level, fp.entry_mode, fp.state,
               fp.is_spill, fp.spill_year, fp.final_level, count(*)::int AS n
          FROM sess s CROSS JOIN LATERAL finance.fee_profiles(s.session) fp
         WHERE fp.status NOT IN ('GRADUATED', 'WITHDRAWN', 'EXPELLED', 'TRANSFERRED_OUT', 'DECEASED', 'VOLUNTARY_WITHDRAWAL')
         GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11),
    now_ AS (
        SELECT l.id, sum(k.n)::int AS n
          FROM l
          JOIN keys k ON k.session = l.session
          LEFT JOIN src ON src.session = l.session AND src.faculty_code = k.faculty_code
                       AND k.entry_mode IS DISTINCT FROM 'CCE' AND NOT people.is_postgraduate(k.entry_mode, k.category)
          CROSS JOIN home
         WHERE l.spillover = k.is_spill
           AND (l.level IS NULL OR l.level = CASE WHEN k.is_spill THEN k.final_level ELSE k.current_level END)
           AND (l.spill_year IS NULL OR l.spill_year = k.spill_year)
           AND ((l.entry_mode IS NULL AND k.entry_mode IS DISTINCT FROM 'CCE') OR l.entry_mode = k.entry_mode)
           AND (l.faculty_code IS NULL OR l.faculty_code = k.faculty_code OR (l.faculty_code = src.source_code AND l.programme_code IS NULL))
           AND (l.programme_code IS NULL OR l.programme_code = k.programme_code)
           AND (l.fee_group IS NULL OR l.applies_category IS NULL OR l.applies_category = k.category)
           AND finance.pg_line(k.entry_mode = 'POSTGRADUATE' OR k.category = 'POST GRADUATE', l.entry_mode, l.level, l.programme_code, l.applies_category)
           AND (l.indigene IS NULL OR (l.indigene = 'INDIGENE') = (k.state = home.home_state))
         GROUP BY l.id),
    -- then: the session's school-fees references and payments (old-portal ones included)
    refs AS MATERIALIZED (
        SELECT r.id, r.student_id, r.session, r.reference, r.amount, r.generated_at, r.confirmed_at, r.expires_at
          FROM finance.payment_reference r
         WHERE r.session IN (SELECT sess.session FROM sess) AND r.purpose LIKE 'School fees%'),
    -- each payer at every level the session knows them at: the record, the session's enrolment, its course registration
    lv AS MATERIALIZED (
        SELECT DISTINCT ps.session, ps.student_id, v.level
          FROM (SELECT DISTINCT refs.session, refs.student_id FROM refs) ps
          JOIN people.student s ON s.id = ps.student_id
          CROSS JOIN LATERAL (SELECT s.current_level AS level
                              UNION SELECT e.level FROM people.enrolment e WHERE e.student_id = ps.student_id AND e.session = ps.session
                              UNION SELECT cr.level FROM registration.course_registration cr WHERE cr.student_id = ps.student_id AND cr.session = ps.session) v
         WHERE v.level IS NOT NULL),
    payer AS MATERIALIZED (
        SELECT lv.session, lv.student_id, lv.level, s.programme_code, p.faculty_code, p.category, s.entry_mode, fl.final,
               CASE WHEN s.entry_mode IS DISTINCT FROM 'CCE' AND NOT people.is_postgraduate(s.entry_mode, p.category) THEN src.source_code END AS source_code,
               concat_ws('|', lv.session, s.programme_code, lv.level, coalesce(s.entry_mode, '-')) AS k
          FROM lv
          JOIN people.student s ON s.id = lv.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN fl ON fl.code = s.programme_code
          LEFT JOIN src ON src.session = lv.session AND src.faculty_code = p.faculty_code),
    -- the payers' distinct profiles (session, programme, level, entry mode): the scope is matched once per profile, not per payer
    pkey AS MATERIALIZED (
        SELECT DISTINCT ON (py.k) py.k, py.session, py.programme_code, py.faculty_code, py.category, py.entry_mode, py.level, py.final, py.source_code
          FROM payer py ORDER BY py.k),
    -- within the line's scope: its programme, faculty (or the faculty charged as), entry mode, group and level; a spillover line's
    -- level is the final level. Read generously: what the line might have charged counts.
    khit AS MATERIALIZED (
        SELECT l.id AS line_id, k.k
          FROM l
          JOIN pkey k ON k.session = l.session
          CROSS JOIN basis
         WHERE ((l.entry_mode IS NULL AND k.entry_mode IS DISTINCT FROM 'CCE') OR l.entry_mode = k.entry_mode)
           AND (l.faculty_code IS NULL OR l.faculty_code = k.faculty_code OR (l.faculty_code = k.source_code AND l.programme_code IS NULL))
           AND (l.programme_code IS NULL OR l.programme_code = k.programme_code)
           AND (l.fee_group IS NULL OR l.applies_category IS NULL OR l.applies_category = k.category)
           AND finance.pg_line(k.entry_mode = 'POSTGRADUATE' OR k.category = 'POST GRADUATE', l.entry_mode, l.level, l.programme_code, l.applies_category)
           AND CASE WHEN l.spillover THEN (l.level IS NULL OR l.level = k.final) AND (basis.b = 'COHORT' OR k.level >= k.final)
                    ELSE (l.level IS NULL OR l.level = k.level) AND (basis.b = 'COHORT' OR k.level <= k.final OR k.category = 'POST GRADUATE') END),
    hit AS MATERIALIZED (
        SELECT DISTINCT kh.line_id, py.student_id FROM khit kh JOIN payer py ON py.k = kh.k),
    -- generated or recorded while the line stood
    used AS MATERIALIZED (
        SELECT h.line_id, r.id, r.reference, r.amount, r.confirmed_at, r.expires_at
          FROM hit h
          JOIN l ON l.id = h.line_id
          JOIN refs r ON r.student_id = h.student_id AND r.session = l.session
         WHERE r.generated_at >= coalesce(l.stated_at, '-infinity'::timestamptz)
           AND (l.ended_at IS NULL OR r.generated_at <= l.ended_at)),
    posted AS MATERIALIZED (
        SELECT split_part(j.source_ref, '#', 1) AS reference, count(*)::int AS n
          FROM finance.gl_journal j
         WHERE j.source_type IN ('PAYMENT', 'PAYMENT_RESET') AND j.source_ref IS NOT NULL
           AND split_part(j.source_ref, '#', 1) IN (SELECT u.reference FROM used u)
         GROUP BY 1),
    tally AS (
        SELECT u.line_id, count(DISTINCT u.id)::int AS generated,
               count(DISTINCT u.id) FILTER (WHERE u.confirmed_at IS NULL AND u.expires_at > now())::int AS open_,
               count(DISTINCT u.id) FILTER (WHERE u.confirmed_at IS NOT NULL)::int AS paid,
               coalesce(sum(u.amount) FILTER (WHERE u.confirmed_at IS NOT NULL), 0) AS amount_paid,
               coalesce(sum(p.n), 0)::int AS ledger
          FROM used u LEFT JOIN posted p ON p.reference = u.reference
         GROUP BY u.line_id),
    out AS (
        SELECT l.id, l.session, l.ended_at IS NULL AS active, l.stated_at, coalesce(n.n, 0) AS students,
               coalesce(t.generated, 0) AS generated, coalesce(t.open_, 0) AS open_, coalesce(t.paid, 0) AS paid,
               coalesce(t.amount_paid, 0) AS amount_paid, coalesce(t.ledger, 0) AS ledger
          FROM l LEFT JOIN now_ n ON n.id = l.id LEFT JOIN tally t ON t.line_id = l.id)
    SELECT o.id, o.session, o.active, o.stated_at, o.students, o.generated, o.open_, o.paid, o.amount_paid, o.ledger,
           x.used_by, x.used_by = 'NONE',
           CASE x.used_by
               WHEN 'NONE' THEN 'Never used: no student is charged by it, and no invoice, payment or ledger entry was made under it.'
               WHEN 'STUDENTS' THEN format('Part of what %s student%s owe now; no invoice or payment has been made under it.', o.students, CASE WHEN o.students = 1 THEN '' ELSE 's' END)
               ELSE format('This fee structure has already been used: %s school-fees invoice%s generated in %s by students within its scope while it stood%s%s.',
                           o.generated, CASE WHEN o.generated = 1 THEN '' ELSE 's' END, o.session,
                           CASE WHEN o.paid > 0 THEN format(', %s paid (₦%s)', o.paid, to_char(o.amount_paid, 'FM999,999,999,990.00')) ELSE '' END,
                           CASE WHEN o.ledger > 0 THEN format(', %s ledger entr%s', o.ledger, CASE WHEN o.ledger = 1 THEN 'y' ELSE 'ies' END) ELSE '' END)
           END
      FROM out o
      CROSS JOIN LATERAL (SELECT CASE WHEN o.ledger > 0 THEN 'LEDGER' WHEN o.paid > 0 THEN 'PAYMENT' WHEN o.generated > 0 THEN 'INVOICE'
                                      WHEN o.students > 0 AND o.active THEN 'STUDENTS' ELSE 'NONE' END AS used_by) x
$$;
COMMENT ON FUNCTION finance.fee_line_usage(uuid[]) IS
  'V648: whether each fee line has been used — the students it charges now; the school-fees invoices (payment references) and payments of its session generated or recorded while it stood by students within its scope (any level the session knows them at); the ledger entries posted for them. used_by NONE / STUDENTS / INVOICE / PAYMENT / LEDGER; only NONE is removable.';

-- ── every edit, removal and archive of a line, kept ──
CREATE TABLE finance.fee_line_change (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    line_id uuid NOT NULL,                -- the line changed; no key: a line removed is gone from the schedule, and kept here
    session text NOT NULL,
    action text NOT NULL CHECK (action IN ('FEE_STRUCTURE_EDITED', 'FEE_STRUCTURE_VERSIONED', 'FEE_STRUCTURE_REMOVED', 'FEE_STRUCTURE_ARCHIVED')),
    reason_code text CHECK (reason_code IN ('ADDED_IN_ERROR', 'WRONG_LEVEL', 'DUPLICATE', 'WRONG_PROGRAMME', 'WRONG_FACULTY', 'WRONG_SESSION',
                                            'WRONG_SEMESTER', 'REPLACED', 'OTHER')),
    reason text,
    before_state jsonb NOT NULL,
    after_state jsonb,
    usage jsonb,
    replaced_by uuid,                     -- a versioned edit: the corrected line stated beside the one ended
    batch uuid,                           -- lines removed together
    actor uuid,
    actor_office text,
    at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_fee_line_change_line ON finance.fee_line_change (line_id, at);
CREATE INDEX ix_fee_line_change_replaced ON finance.fee_line_change (replaced_by) WHERE replaced_by IS NOT NULL;
CREATE INDEX ix_fee_line_change_session ON finance.fee_line_change (session, at DESC);
SELECT audit.attach('finance.fee_line_change');
COMMENT ON TABLE finance.fee_line_change IS
  'V648: every edit, versioned edit, removal and archive of a school fees line — the line before (and after), its use at the time, the reason, who and when. Kept: never changed, removed only by the go-live reset (moaum.maintenance).';

CREATE OR REPLACE FUNCTION finance.fee_line_change_kept()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'FEE_LINE_CHANGE_KEPT: a change to the fee setup is kept as it was made' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_fee_line_change_kept BEFORE UPDATE OR DELETE ON finance.fee_line_change
    FOR EACH ROW EXECUTE FUNCTION finance.fee_line_change_kept();

CREATE OR REPLACE FUNCTION finance.fee_remove_reason_words(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE p_code WHEN 'ADDED_IN_ERROR' THEN 'Added in error' WHEN 'WRONG_LEVEL' THEN 'Wrong level' WHEN 'DUPLICATE' THEN 'Duplicate fee structure'
                       WHEN 'WRONG_PROGRAMME' THEN 'Wrong programme' WHEN 'WRONG_FACULTY' THEN 'Wrong faculty' WHEN 'WRONG_SESSION' THEN 'Wrong session'
                       WHEN 'WRONG_SEMESTER' THEN 'Wrong semester' WHEN 'REPLACED' THEN 'Replaced by corrected structure' WHEN 'OTHER' THEN 'Other' END
$$;

-- ── remove or archive: a line never used is deleted; one used is archived (ended, kept); nothing financial is touched ──
CREATE OR REPLACE FUNCTION finance.remove_fee_lines(p_lines uuid[], p_mode text, p_reason_code text, p_reason text, p_apply boolean)
RETURNS TABLE(line_id uuid, session text, item text, amount numeric, level integer, faculty_code text, programme_code text, semester integer,
              entry_mode text, active boolean, used_by text, students integer, references_generated integer, references_paid integer,
              amount_paid numeric, ledger_entries integer, outcome text, message text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_office text := nullif(current_setting('moaum.actor_office', true), '');
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_batch uuid;
    v_reason text;
    u record;
BEGIN
    IF p_mode IS NULL OR p_mode NOT IN ('REMOVE', 'DEACTIVATE', 'AUTO') THEN
        RAISE EXCEPTION 'FEE_REMOVE_MODE: remove (a line never used), deactivate (archive) or remove-or-archive' USING ERRCODE = '23514';
    END IF;
    IF coalesce(cardinality(p_lines), 0) = 0 THEN
        RAISE EXCEPTION 'FEE_REMOVE_NONE: choose the fee lines to remove' USING ERRCODE = '23514';
    END IF;
    PERFORM finance.fee_setup_require('VIEW_FEE_SETUP');
    IF p_apply THEN
        IF p_mode IN ('REMOVE', 'AUTO') THEN PERFORM finance.fee_setup_require('REMOVE_FEE_STRUCTURE'); END IF;
        IF p_mode IN ('DEACTIVATE', 'AUTO') THEN PERFORM finance.fee_setup_require('DEACTIVATE_FEE_STRUCTURE'); END IF;
        IF finance.fee_remove_reason_words(p_reason_code) IS NULL THEN
            RAISE EXCEPTION 'FEE_REMOVE_REASON: give the reason — added in error, wrong level, duplicate, wrong programme, faculty, session or semester, replaced by a corrected structure, or other' USING ERRCODE = '23514';
        END IF;
        IF p_reason_code = 'OTHER' AND length(btrim(coalesce(p_reason, ''))) < 10 THEN
            RAISE EXCEPTION 'FEE_REMOVE_REASON: describe the reason (ten characters at least) when it is "Other"' USING ERRCODE = '23514';
        END IF;
        v_reason := finance.fee_remove_reason_words(p_reason_code) || coalesce(': ' || nullif(btrim(p_reason), ''), '');
        PERFORM set_config('moaum.reason', v_reason, true);
        IF cardinality(p_lines) > 1 THEN v_batch := gen_random_uuid(); END IF;
        PERFORM 1 FROM finance.fee_schedule f WHERE f.id = ANY (p_lines) ORDER BY f.id FOR UPDATE;
    END IF;

    FOR u IN
        SELECT f.*, x.active AS x_active, x.used_by AS x_used_by, x.students AS x_students, x.references_generated AS x_generated,
               x.references_open AS x_open, x.references_paid AS x_paid, x.amount_paid AS x_amount_paid, x.ledger_entries AS x_ledger,
               x.removable AS x_removable, x.message AS x_message, to_jsonb(x) AS x_usage, to_jsonb(f) AS x_before
          FROM finance.fee_schedule f
          JOIN finance.fee_line_usage(p_lines) x ON x.line_id = f.id
         ORDER BY f.ord, f.item, f.level NULLS FIRST, f.id
    LOOP
        line_id := u.id; session := u.session; item := u.item; amount := u.amount; level := u.level; faculty_code := u.faculty_code;
        programme_code := u.programme_code; semester := u.semester; entry_mode := u.entry_mode; active := u.x_active; used_by := u.x_used_by;
        students := u.x_students; references_generated := u.x_generated; references_paid := u.x_paid; amount_paid := u.x_amount_paid;
        ledger_entries := u.x_ledger;
        outcome := CASE WHEN p_mode = 'REMOVE' THEN CASE WHEN u.x_removable THEN 'REMOVED' ELSE 'CANNOT_REMOVE' END
                        WHEN p_mode = 'DEACTIVATE' THEN CASE WHEN u.ended_at IS NULL THEN 'ARCHIVED' ELSE 'ALREADY_ARCHIVED' END
                        ELSE CASE WHEN u.x_removable THEN 'REMOVED' WHEN u.ended_at IS NULL THEN 'ARCHIVED' ELSE 'ALREADY_ARCHIVED' END END;
        message := CASE outcome
            WHEN 'REMOVED' THEN u.x_message || ' It is removed permanently.'
            WHEN 'CANNOT_REMOVE' THEN u.x_message || ' It cannot be permanently deleted; you may deactivate (archive) it instead.'
            WHEN 'ARCHIVED' THEN u.x_message || ' It is archived: kept on record and no longer charged; every invoice, payment and receipt stays as it is.'
            ELSE 'Already archived: no longer charged. ' || u.x_message END;
        IF p_apply AND outcome = 'REMOVED' THEN
            INSERT INTO finance.fee_line_change (line_id, session, action, reason_code, reason, before_state, usage, batch, actor, actor_office)
            VALUES (u.id, u.session, 'FEE_STRUCTURE_REMOVED', p_reason_code, nullif(btrim(coalesce(p_reason, '')), ''), u.x_before, u.x_usage, v_batch, v_actor, v_office);
            DELETE FROM finance.fee_schedule f WHERE f.id = u.id;
        ELSIF p_apply AND outcome = 'ARCHIVED' THEN
            UPDATE finance.fee_schedule f SET ended_at = now() WHERE f.id = u.id AND f.ended_at IS NULL;
            INSERT INTO finance.fee_line_change (line_id, session, action, reason_code, reason, before_state, after_state, usage, batch, actor, actor_office)
            SELECT u.id, u.session, 'FEE_STRUCTURE_ARCHIVED', p_reason_code, nullif(btrim(coalesce(p_reason, '')), ''), u.x_before, to_jsonb(f), u.x_usage,
                   v_batch, v_actor, v_office
              FROM finance.fee_schedule f WHERE f.id = u.id;
        END IF;
        RETURN NEXT;
    END LOOP;

    -- a line asked for that is not on the schedule (removed already)
    FOR u IN SELECT x AS id FROM unnest(p_lines) x WHERE NOT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.id = x) LOOP
        line_id := u.id; session := NULL; item := NULL; amount := NULL; level := NULL; faculty_code := NULL; programme_code := NULL;
        semester := NULL; entry_mode := NULL; active := false; used_by := NULL; students := NULL; references_generated := NULL;
        references_paid := NULL; amount_paid := NULL; ledger_entries := NULL; outcome := 'NOT_FOUND';
        message := 'That fee line is not on the schedule (removed already).';
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION finance.remove_fee_lines(uuid[], text, text, text, boolean) IS
  'V648: REMOVE (a line never used deleted; a used one CANNOT_REMOVE), DEACTIVATE (archived: ended and kept) or AUTO (each removed or archived as its use decides); a preview without apply. The reason is required to apply; each removal and archive kept in finance.fee_line_change. No payment, reference, receipt or ledger entry is touched.';

-- ── edit: in place for a line never used to generate an invoice or a payment; versioned (ended, kept, corrected beside it) otherwise ──
CREATE OR REPLACE FUNCTION finance.edit_fee_line(p_id uuid, p_line jsonb, p_reason text)
RETURNS TABLE(outcome text, line_id uuid, previous_id uuid, used_by text, message text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_office text := nullif(current_setting('moaum.actor_office', true), '');
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_old finance.fee_schedule;
    v_new_id uuid;
    v_item text := btrim(coalesce(p_line ->> 'item', ''));
    v_amount numeric := (p_line ->> 'amount')::numeric;
    v_level integer := (nullif(p_line ->> 'level', ''))::integer;
    v_mode text := nullif(btrim(coalesce(p_line ->> 'entry_mode', '')), '');
    v_fac text := nullif(btrim(coalesce(p_line ->> 'faculty_code', '')), '');
    v_prog text := nullif(btrim(coalesce(p_line ->> 'programme_code', '')), '');
    v_group text := nullif(btrim(coalesce(p_line ->> 'fee_group', '')), '');
    v_sem integer := (nullif(p_line ->> 'semester', ''))::integer;
    v_ord integer := coalesce((nullif(p_line ->> 'ord', ''))::integer, 0);
    v_kind text;
    v_spill boolean := coalesce((nullif(p_line ->> 'spillover', ''))::boolean, false) OR nullif(p_line ->> 'spill_year', '') IS NOT NULL;
    v_spill_year integer := (nullif(p_line ->> 'spill_year', ''))::integer;
    -- the edit's own reason, else the request's (moaum.reason, the X-Reason the screen sends)
    v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), nullif(current_setting('moaum.reason', true), ''));
    u record;
BEGIN
    PERFORM finance.fee_setup_require('EDIT_FEE_STRUCTURE');
    SELECT * INTO v_old FROM finance.fee_schedule f WHERE f.id = p_id AND f.ended_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'FEE_GONE: that fee line is not on the current schedule' USING ERRCODE = '23514';
    END IF;
    IF v_item = '' OR v_amount IS NULL OR v_amount < 0 THEN
        RAISE EXCEPTION 'FEE_LINE_INCOMPLETE: a fee line has an item and an amount of zero or more' USING ERRCODE = '23514';
    END IF;
    v_kind := coalesce(nullif(btrim(coalesce(p_line ->> 'kind', '')), ''), v_old.kind);
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NOT NULL THEN
        PERFORM set_config('moaum.reason', btrim(p_reason), true);
    END IF;

    IF (v_old.item, v_old.amount, v_old.level, v_old.entry_mode, v_old.faculty_code, v_old.programme_code, v_old.fee_group, v_old.semester,
        v_old.ord, v_old.kind, v_old.spillover, v_old.spill_year)
       IS NOT DISTINCT FROM (v_item, v_amount, v_level, v_mode, v_fac, v_prog, v_group, v_sem, v_ord, v_kind, v_spill, v_spill_year) THEN
        outcome := 'UNCHANGED'; line_id := p_id; previous_id := NULL; used_by := NULL; message := 'Nothing changed.';
        RETURN NEXT;
        RETURN;
    END IF;

    SELECT * INTO u FROM finance.fee_line_usage(ARRAY[p_id]);
    used_by := u.used_by;
    IF u.used_by IN ('INVOICE', 'PAYMENT', 'LEDGER') THEN
        -- the line an invoice or a payment was made under stays on record, ended; the corrected one is stated beside it
        UPDATE finance.fee_schedule f SET ended_at = now() WHERE f.id = p_id;
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, ord, kind,
                                          spillover, spill_year, indigene)
        VALUES (v_old.session, v_item, v_amount, v_level, v_mode, v_fac, v_prog, v_group, v_sem, v_ord, v_kind, v_spill, v_spill_year, v_old.indigene)
        RETURNING id INTO v_new_id;
        INSERT INTO finance.fee_line_change (line_id, session, action, reason_code, reason, before_state, after_state, usage, replaced_by, actor, actor_office)
        SELECT p_id, v_old.session, 'FEE_STRUCTURE_VERSIONED', NULL, v_reason, to_jsonb(v_old), to_jsonb(f), to_jsonb(u),
               v_new_id, v_actor, v_office
          FROM finance.fee_schedule f WHERE f.id = v_new_id;
        outcome := 'VERSIONED'; line_id := v_new_id; previous_id := p_id;
        message := u.message || ' The line it was is kept, ended, and the corrected line is in force from now; every invoice and payment keeps its amount.';
    ELSE
        UPDATE finance.fee_schedule f
           SET item = v_item, amount = v_amount, level = v_level, entry_mode = v_mode, faculty_code = v_fac, programme_code = v_prog,
               fee_group = v_group, semester = v_sem, ord = v_ord, kind = v_kind, spillover = v_spill, spill_year = v_spill_year
         WHERE f.id = p_id;
        INSERT INTO finance.fee_line_change (line_id, session, action, reason_code, reason, before_state, after_state, usage, actor, actor_office)
        SELECT p_id, v_old.session, 'FEE_STRUCTURE_EDITED', NULL, v_reason, to_jsonb(v_old), to_jsonb(f), to_jsonb(u),
               v_actor, v_office
          FROM finance.fee_schedule f WHERE f.id = p_id;
        outcome := 'EDITED'; line_id := p_id; previous_id := NULL;
        message := 'Corrected in place: ' || lower(left(u.message, 1)) || substr(u.message, 2);
    END IF;
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION finance.edit_fee_line(uuid, jsonb, text) IS
  'V648: a fee line corrected — in place when no invoice or payment was made under it (EDITED); otherwise VERSIONED: the line ended and kept, the corrected line stated beside it, both named in finance.fee_line_change. UNCHANGED when nothing differs.';

-- ── a line's versions: itself, the lines it replaced and the lines that replaced it, from the audit trail ──
CREATE OR REPLACE FUNCTION finance.fee_line_history(p_id uuid)
RETURNS TABLE(version integer, line_id uuid, at timestamptz, action text, by_id uuid, by_name text, office text, reason text, item text,
              amount numeric, level integer, entry_mode text, faculty_code text, programme_code text, semester integer, kind text,
              spillover boolean, spill_year integer, ended boolean)
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE chain(id) AS (
        SELECT p_id
        UNION
        SELECT CASE WHEN c.line_id = ch.id THEN c.replaced_by ELSE c.line_id END
          FROM chain ch
          JOIN finance.fee_line_change c ON c.replaced_by IS NOT NULL AND (c.line_id = ch.id OR c.replaced_by = ch.id)),
    ev AS (
        SELECT e.occurred_at, e.id AS entry_id, e.subject_id, e.action AS op, e.actor_id, e.actor_office, e.reason, e.before_state,
               e.after_state, coalesce(e.after_state, e.before_state) AS st
          FROM audit.entries e
         WHERE e.subject_type = 'finance.fee_schedule' AND e.subject_id IN (SELECT chain.id FROM chain))
    SELECT (row_number() OVER (ORDER BY ev.occurred_at, ev.entry_id))::int, ev.subject_id, ev.occurred_at,
           CASE WHEN ev.op = 'INSERT' THEN CASE WHEN EXISTS (SELECT 1 FROM finance.fee_line_change c WHERE c.replaced_by = ev.subject_id)
                                                THEN 'VERSIONED' ELSE 'CREATED' END
                WHEN ev.op = 'DELETE' THEN 'REMOVED'
                WHEN (ev.before_state ->> 'ended_at') IS NULL AND (ev.after_state ->> 'ended_at') IS NOT NULL THEN
                     CASE WHEN EXISTS (SELECT 1 FROM finance.fee_line_change c WHERE c.line_id = ev.subject_id AND c.replaced_by IS NOT NULL)
                          THEN 'REPLACED' ELSE 'DEACTIVATED' END
                WHEN (ev.before_state ->> 'ended_at') IS NOT NULL AND (ev.after_state ->> 'ended_at') IS NULL THEN 'REACTIVATED'
                ELSE 'EDITED' END,
           ev.actor_id,
           (SELECT btrim(pe.surname || ', ' || pe.given_names) FROM iam.person pe WHERE pe.id = ev.actor_id),
           ev.actor_office, ev.reason,
           ev.st ->> 'item', (ev.st ->> 'amount')::numeric, (ev.st ->> 'level')::integer, ev.st ->> 'entry_mode', ev.st ->> 'faculty_code',
           ev.st ->> 'programme_code', (ev.st ->> 'semester')::integer, ev.st ->> 'kind', coalesce((ev.st ->> 'spillover')::boolean, false),
           (ev.st ->> 'spill_year')::integer, ev.op = 'DELETE' OR (ev.st ->> 'ended_at') IS NOT NULL
      FROM ev
     ORDER BY ev.occurred_at, ev.entry_id
$$;
COMMENT ON FUNCTION finance.fee_line_history(uuid) IS
  'V648: every version of a fee line — created, edited, versioned (the corrected line), replaced, deactivated, removed — with who, when and why, across the lines a versioned edit links.';

COMMIT;
