-- ═══════════════════════════════════════════════════════════════════════════
-- V229 — reports are evidence: a catalogue with due dates, kept snapshots,
--        and the due register
--
--   Until now every return was a screen read off the register at the moment
--   it was opened. A return filed with NUC, JAMB, the State treasury or
--   Council has to be reproducible afterwards, and the register moves on. So:
--
--   · reports.catalogue — every return the portal takes, with its owner, its
--     frequency and the rule that fixes when it is due (a day of the month for
--     a monthly return; one or two dates in the year for a per-session or
--     per-semester one). Seeded from the returns desk; the desk reads it back.
--   · reports.snapshot — a copy kept when a return is run: the parameters,
--     the headers, the rows and totals as they were, who took it and when, the
--     due date it answers, and a verification code the printed footing carries
--     so anyone can check the figures against what was filed. Filing is a
--     second act (filed_to, filed_at, filed_by) on the same row.
--   · reports.due_register(today) — for each return, the last due date and
--     the next, whether a snapshot answers each, and a state the desk shows:
--     FILED · TAKEN · DUE · OVERDUE.
--
--   Both tables are state and sit on the audit spine — in their own schema,
--   `reports`, because `reporting` is exempt from the spine wholesale as the
--   home of derived read models, and a kept return is not derived: it is the
--   record of what was filed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'Report catalogue and snapshots (V229)', true);

CREATE SCHEMA IF NOT EXISTS reports;

-- ── 1 · the catalogue ────────────────────────────────────────────────────────
CREATE TABLE reports.catalogue (
    slug          text PRIMARY KEY,
    title         text NOT NULL,
    owner_office  text NOT NULL,                       -- the office answerable for it (ref.office code)
    owner_label   text NOT NULL,                       -- as the desk prints it: Registry, Bursary, HR …
    frequency     text NOT NULL,                       -- MONTHLY · PER_SEMESTER · PER_SESSION · ON_DEMAND
    purpose       text NOT NULL,                       -- who it is for, in their own words
    -- when it is due: MONTHLY → due_day of the following month; PER_SESSION / PER_SEMESTER → the
    -- month-day(s) in the year it must be filed by (e.g. {'12-31'} or {'03-31','08-31'})
    due_day       int  NULL,
    due_dates     text[] NULL,
    sort_order    int  NOT NULL DEFAULT 100,
    active        boolean NOT NULL DEFAULT true,
    tracked_from  date NOT NULL DEFAULT current_date,   -- due dates before this are not the portal's to chase
    CONSTRAINT ck_cat_frequency CHECK (frequency IN ('MONTHLY','PER_SEMESTER','PER_SESSION','ON_DEMAND')),
    CONSTRAINT ck_cat_due CHECK (
        (frequency = 'MONTHLY'   AND due_day BETWEEN 1 AND 28 AND due_dates IS NULL) OR
        (frequency IN ('PER_SEMESTER','PER_SESSION') AND due_dates IS NOT NULL AND cardinality(due_dates) BETWEEN 1 AND 3 AND due_day IS NULL) OR
        (frequency = 'ON_DEMAND' AND due_day IS NULL AND due_dates IS NULL))
);
SELECT audit.attach('reports.catalogue');

INSERT INTO reports.catalogue (slug, title, owner_office, owner_label, frequency, purpose, due_day, due_dates, sort_order) VALUES
    ('admissions',         'Admissions return',                          'registrar', 'Registry',            'PER_SESSION',  'JAMB / CAPS and Council',       NULL, '{12-31}',       10),
    ('enrolment',          'Enrolment by programme, level and sex',      'registrar', 'Registry',            'PER_SESSION',  'NUC statutory return',          NULL, '{12-31}',       20),
    ('registration',       'Registration & fees return',                 'registrar', 'Registry',            'PER_SEMESTER', 'Management',                    NULL, '{03-31,08-31}', 30),
    ('carryovers',         'Carryover return',                           'records',   'Exams & Records',     'PER_SESSION',  'Senate',                        NULL, '{10-31}',       40),
    ('staff-ratio',        'Staff/student ratio by department',          'hrm',       'HR',                  'PER_SESSION',  'NUC accreditation',             NULL, '{12-31}',       50),
    ('postgraduate',       'Postgraduate return',                        'pgschool',  'Postgraduate School', 'PER_SESSION',  'School Board and Senate',       NULL, '{11-30}',       60),
    ('revenue',            'IGR collections by revenue head',            'bursar',    'Bursary',             'MONTHLY',      'State treasury return',         10,   NULL,            70),
    ('funding',            'Funding return',                             'bursar',    'Bursary',             'PER_SESSION',  'Management',                    NULL, '{12-31}',       80),
    ('expenditure',        'Expenditure by cost centre',                 'bursar',    'Bursary',             'MONTHLY',      'Council finance committee',     10,   NULL,            90),
    ('income-expenditure', 'Income & expenditure statement',             'bursar',    'Bursary',             'MONTHLY',      'Council and management',        10,   NULL,           100),
    ('students',           'Student register',                           'registrar', 'Registry',            'ON_DEMAND',    'Any office that reads it whole', NULL, NULL,          110),
    ('staff',              'Staff register',                             'hrm',       'HR',                  'ON_DEMAND',    'Any office that reads it whole', NULL, NULL,          120);

-- ── 2 · the snapshot ─────────────────────────────────────────────────────────
CREATE TABLE reports.snapshot (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report            text NOT NULL REFERENCES reports.catalogue(slug),
    title             text NOT NULL,
    subtitle          text NULL,
    period            text NOT NULL,                     -- as printed: a session, a month, "as at 2026-09-23"
    parameters        jsonb NOT NULL DEFAULT '{}'::jsonb,   -- the query the return was run with
    due_on            date NULL,                         -- the due date this copy answers (NULL: on demand)
    headers           jsonb NOT NULL,                    -- text[] as JSON
    rows              jsonb NOT NULL,                    -- the rows, each an array of cells
    totals            jsonb NULL,
    row_count         int  NOT NULL,
    note              text NULL,
    taken_at          timestamptz NOT NULL DEFAULT now(),
    taken_by          uuid NULL REFERENCES iam.person(id),
    taken_office      text NULL,
    verification_code text NOT NULL UNIQUE DEFAULT upper(encode(gen_random_bytes(6), 'hex')),
    filed_to          text NULL,                         -- NUC, JAMB, Council, the State treasury …
    filed_at          timestamptz NULL,
    filed_by          uuid NULL REFERENCES iam.person(id),
    filed_note        text NULL,
    CONSTRAINT ck_snap_rows CHECK (jsonb_typeof(rows) = 'array' AND jsonb_typeof(headers) = 'array'),
    CONSTRAINT ck_snap_filed CHECK ((filed_at IS NULL) = (filed_to IS NULL))
);
CREATE INDEX ix_snapshot_report ON reports.snapshot (report, taken_at DESC);
CREATE INDEX ix_snapshot_due    ON reports.snapshot (report, due_on) WHERE due_on IS NOT NULL;
SELECT audit.attach('reports.snapshot');

-- ── 3 · when is each return due? ─────────────────────────────────────────────
-- The due dates of a catalogue row around a day: the last one on or before it
-- and the next one after it. MONTHLY: day N of each month. PER_SESSION /
-- PER_SEMESTER: the month-days listed, in any year. ON_DEMAND: none.
CREATE OR REPLACE FUNCTION reports.due_around(p_slug text, p_today date,
                                                OUT last_due date, OUT next_due date)
LANGUAGE plpgsql STABLE AS $$
DECLARE c reports.catalogue; d date; md text; y int;
        cands date[] := '{}';
BEGIN
    SELECT * INTO c FROM reports.catalogue WHERE slug = p_slug;
    IF c.slug IS NULL OR c.frequency = 'ON_DEMAND' THEN RETURN; END IF;
    IF c.frequency = 'MONTHLY' THEN
        FOR y IN -2..2 LOOP
            d := (date_trunc('month', p_today) + (y || ' month')::interval)::date + (c.due_day - 1);
            cands := cands || d;
        END LOOP;
    ELSE
        FOREACH md IN ARRAY c.due_dates LOOP
            FOR y IN -1..1 LOOP
                d := to_date((extract(year FROM p_today)::int + y) || '-' || md, 'YYYY-MM-DD');
                cands := cands || d;
            END LOOP;
        END LOOP;
    END IF;
    SELECT max(x) INTO last_due FROM unnest(cands) x WHERE x <= p_today AND x >= c.tracked_from;
    SELECT min(x) INTO next_due FROM unnest(cands) x WHERE x >  p_today;
END $$;

-- The period a due date answers, as the desk labels it: the month before a
-- monthly due day; the session a yearly date falls in (a session runs from the
-- fourth quarter of one year into the next).
CREATE OR REPLACE FUNCTION reports.period_for(p_slug text, p_due date)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE
             WHEN p_due IS NULL THEN NULL
             WHEN (SELECT frequency FROM reports.catalogue WHERE slug = p_slug) = 'MONTHLY'
                  THEN to_char(p_due - interval '1 month', 'FMMonth YYYY')
             WHEN extract(month FROM p_due) >= 9
                  THEN extract(year FROM p_due)::int || '/' || (extract(year FROM p_due)::int + 1)
             ELSE (extract(year FROM p_due)::int - 1) || '/' || extract(year FROM p_due)::int
           END
$$;

-- The due register: one row per active return, with its state as at a day.
CREATE OR REPLACE FUNCTION reports.due_register(p_today date DEFAULT current_date)
RETURNS TABLE (slug text, title text, owner_office text, owner_label text, frequency text, purpose text,
               last_due date, last_period text, last_snapshot uuid, last_taken_at timestamptz, last_filed_at timestamptz, last_filed_to text,
               next_due date, next_period text, next_snapshot uuid, next_taken_at timestamptz, next_filed_at timestamptz,
               latest_snapshot uuid, latest_taken_at timestamptz,
               state text, days int)
LANGUAGE sql STABLE AS $$
    WITH c AS (
        SELECT k.*, (reports.due_around(k.slug, p_today)).*
          FROM reports.catalogue k WHERE k.active
    ),
    sn AS (
        SELECT c.slug,
               (SELECT s.id FROM reports.snapshot s WHERE s.report = c.slug AND s.due_on = c.last_due ORDER BY s.taken_at DESC LIMIT 1) AS last_snapshot,
               (SELECT s.id FROM reports.snapshot s WHERE s.report = c.slug AND s.due_on = c.next_due ORDER BY s.taken_at DESC LIMIT 1) AS next_snapshot,
               (SELECT s.id FROM reports.snapshot s WHERE s.report = c.slug ORDER BY s.taken_at DESC LIMIT 1) AS latest_snapshot
          FROM c
    )
    SELECT c.slug, c.title, c.owner_office, c.owner_label, c.frequency, c.purpose,
           c.last_due, reports.period_for(c.slug, c.last_due), ls.id, ls.taken_at, ls.filed_at, ls.filed_to,
           c.next_due, reports.period_for(c.slug, c.next_due), ns.id, ns.taken_at, ns.filed_at,
           lt.id, lt.taken_at,
           CASE
             WHEN c.frequency = 'ON_DEMAND' THEN 'ON_DEMAND'
             WHEN ls.id IS NOT NULL AND ls.filed_at IS NOT NULL THEN 'FILED'
             WHEN ls.id IS NOT NULL THEN 'TAKEN'
             WHEN c.last_due IS NOT NULL AND c.last_due < p_today - 14 THEN 'OVERDUE'   -- a fortnight's grace after the due date
             WHEN c.last_due IS NOT NULL AND c.last_due >= p_today - 14 AND ns.id IS NULL THEN 'DUE'
             WHEN ns.id IS NOT NULL AND ns.filed_at IS NOT NULL THEN 'FILED'
             WHEN ns.id IS NOT NULL THEN 'TAKEN'
             ELSE 'DUE'
           END,
           CASE WHEN c.frequency = 'ON_DEMAND' THEN NULL
                WHEN ls.id IS NULL AND c.last_due IS NOT NULL THEN (p_today - c.last_due)   -- days late
                ELSE (c.next_due - p_today) END                                            -- days to the next
      FROM c
      LEFT JOIN sn ON sn.slug = c.slug
      LEFT JOIN reports.snapshot ls ON ls.id = sn.last_snapshot
      LEFT JOIN reports.snapshot ns ON ns.id = sn.next_snapshot
      LEFT JOIN reports.snapshot lt ON lt.id = sn.latest_snapshot
     ORDER BY CASE WHEN c.frequency = 'ON_DEMAND' THEN 1 ELSE 0 END, c.sort_order;
$$;

COMMIT;
