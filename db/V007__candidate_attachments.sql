-- ════════════════════════════════════════════════════════════════════════
--  V007  ·  What arrives ATTACHED to a candidate
--           passports · dates of birth · O'Level results
--
--  Written 7 September 2026, against the real files.
--
--  The admission list creates candidates. These three do not: they attach
--  to a candidate who already exists, and each is matched on the JAMB
--  registration number and never on a name.
--
--  ── The two ways a match silently fails ─────────────────────────────────
--
--  1. THE KEY IS NOT THE KEY IT LOOKS LIKE.
--     Every registration number in the date-of-birth file ends with a
--     space: '202440000065EA '. Joined raw it matches nothing at all, and
--     the report reads "0 of 4,000 matched", which looks like a broken
--     import rather than one stray character.
--
--  2. THE KEY IS WRAPPED IN SOMETHING ELSE.
--     JAMB does not send 202660168863AH.jpg. It sends
--
--         202660168863AH_Face.jpg
--
--     Strip only the extension and the key is '202660168863AH_FACE',
--     which matches nobody -- so EVERY photograph arrives as an orphan.
--
--  Both are the same failure: a key that has been handled by another
--  system before it reached us. Neither is fixed by remembering to trim,
--  because remembering is not a mechanism. They are fixed here by making
--  the raw value unjoinable:
--
--    · every table that carries a registration number also carries
--      jamb_key, GENERATED ALWAYS -- upper(btrim(...)) -- and every join
--      and every unique constraint is on jamb_key. There is no way to
--      write the join wrongly, because the wrong column is not a key.
--
--    · a filename is not trusted to BE the number. The number is FOUND
--      inside it, by shape: twelve digits then two or three letters,
--      which is every registration number JAMB has ever sent
--      (202660176777GF is 14 characters, 202660307120BGU is 15). That
--      survives _Face, _face, ' (1)', 'Copy of ', a folder path, and
--      whatever JAMB appends next year. The suffix is deliberately NOT
--      stripped by name: '_Face' is JAMB's decision and JAMB can change
--      it without telling anybody.
--
--  ── What is not guessed at ──────────────────────────────────────────────
--  A filename with no number in it is not matched on the name of the
--  candidate, not matched on position in the folder, and not thrown away.
--  It is recorded, with the filename exactly as it arrived, as something
--  a person has to look at. A photograph attached to the wrong candidate
--  is worse than a photograph attached to nobody: it survives into the
--  identity card, the examination hall and the certificate.
--
--  ── Held, not discarded ────────────────────────────────────────────────
--  JAMB sends the passports, the dates of birth and the lists on
--  different days and in a different order. A file that matches nobody
--  this morning matches somebody the moment the next tranche of the
--  admission list is uploaded. Every arrival is kept in the intake table
--  whether it matched or not, and admissions.attach_pending() re-runs the
--  match after every list commit. Discarding an unmatched file means
--  downloading it again and being unable to say whether it ever arrived.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the join key, made impossible to get wrong ──────────────────────────
ALTER TABLE admissions.candidate
    ADD COLUMN IF NOT EXISTS jamb_key text
    GENERATED ALWAYS AS (upper(btrim(jamb_reg_no))) STORED;

ALTER TABLE admissions.caps_row
    ADD COLUMN IF NOT EXISTS jamb_key text
    GENERATED ALWAYS AS (upper(btrim(jamb_reg_no))) STORED;

-- The unique constraints in V006 are on the raw column, which would let
-- '202440000065EA' and '202440000065EA ' both exist as two candidates.
CREATE UNIQUE INDEX IF NOT EXISTS uq_candidate_key_per_session
    ON admissions.candidate (session, jamb_key);
CREATE UNIQUE INDEX IF NOT EXISTS uq_caps_row_key_per_session
    ON admissions.caps_row (session, jamb_key);

-- ── the number, found inside whatever it arrived wrapped in ─────────────
-- The same rule as the portal's jambNumFromName(). Written once here so
-- the database and the screen cannot drift apart on what a key is.
CREATE OR REPLACE FUNCTION admissions.reg_no_in(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    -- basename first: a folder can contain digits too
    SELECT upper(substring(
        regexp_replace(coalesce(p_text, ''), '^.*[/\\]', '')
        from '([0-9]{12}[A-Za-z]{2,3})'))
$$;

COMMENT ON FUNCTION admissions.reg_no_in(text) IS
'Finds a JAMB registration number inside a filename or cell. NULL when there '
'is none -- which is an answer, not a failure, and is recorded as such.';

-- ── everything that arrived, matched or not ────────────────────────────
CREATE TABLE IF NOT EXISTS admissions.attachment (
    id            uuid PRIMARY KEY,
    session       text NOT NULL,
    kind          text NOT NULL,
    -- exactly as the file was named, before anything was done to it. This
    -- is what a person is shown when the match fails, and it is the only
    -- way to find the file again in the download folder.
    source_name   text NOT NULL,
    -- what was read out of it, and HOW. 'how' is shown on the screen: a
    -- derived key that is never displayed is a key nobody can dispute.
    jamb_key      text NULL,
    read_as       text NOT NULL,
    -- the candidate this attached to, once one exists. NULL is the normal
    -- state of a file that arrived before its admission list did.
    candidate_id  uuid NULL REFERENCES admissions.candidate(id),
    matched_at    timestamptz NULL,
    payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
    bytes         bigint NULL,
    width_px      int NULL,
    height_px     int NULL,
    -- where the file itself lives; the database holds the fact, not the JPEG
    object_key    text NULL,
    arrived_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_att_kind CHECK (kind IN ('PASSPORT','DATE_OF_BIRTH','OLEVEL')),
    CONSTRAINT ck_att_read CHECK (read_as IN (
        'EXACT',        -- the name WAS the number
        'EMBEDDED',     -- the number was found inside the name (_Face.jpg)
        'COLUMN',       -- a spreadsheet column, trimmed
        'UNREADABLE')), -- no number anywhere: a person must look at it
    -- A key and 'UNREADABLE' cannot both be true, and 'UNREADABLE' with a
    -- key is exactly how a wrong photograph gets onto a right candidate.
    CONSTRAINT ck_att_read_key CHECK (
        (read_as = 'UNREADABLE' AND jamb_key IS NULL) OR
        (read_as <> 'UNREADABLE' AND jamb_key IS NOT NULL)),
    -- nothing matches without a key
    CONSTRAINT ck_att_matched CHECK (
        candidate_id IS NULL OR (jamb_key IS NOT NULL AND matched_at IS NOT NULL)),
    -- the same file twice is the same file, not two arrivals
    CONSTRAINT uq_att_source UNIQUE (session, kind, source_name)
);

CREATE INDEX IF NOT EXISTS ix_att_pending
    ON admissions.attachment (session, kind, jamb_key)
    WHERE candidate_id IS NULL AND jamb_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_att_candidate
    ON admissions.attachment (candidate_id, kind);

-- ── the current photograph ─────────────────────────────────────────────
-- One per candidate at a time, and superseded rather than overwritten: a
-- photograph replaced in November is still the photograph that screened
-- the candidate in October, and somebody will ask.
CREATE TABLE IF NOT EXISTS admissions.candidate_photo (
    id            uuid PRIMARY KEY,
    candidate_id  uuid NOT NULL REFERENCES admissions.candidate(id),
    attachment_id uuid NOT NULL REFERENCES admissions.attachment(id),
    -- JAMB's passports arrive at about 132 x 151 px -- 11 x 13 mm printed.
    -- Ample for screening a face against a record at a desk, nowhere near
    -- enough for an identity card, which is why the card photograph is
    -- captured at the counter. Recording the purpose stops a 132 px image
    -- reaching the card printer by default.
    purpose       text NOT NULL DEFAULT 'SCREENING',
    in_force      tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
    CONSTRAINT ck_photo_purpose CHECK (purpose IN ('SCREENING','CARD','CERTIFICATE')),
    CONSTRAINT ex_photo_one_at_a_time
        EXCLUDE USING gist (candidate_id WITH =, purpose WITH =, in_force WITH &&)
);

-- ── the sweep, run after every list commit ─────────────────────────────
CREATE OR REPLACE FUNCTION admissions.attach_pending(p_session text)
RETURNS TABLE (kind text, newly_attached bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH hit AS (
        UPDATE admissions.attachment a
           SET candidate_id = c.id,
               matched_at   = now()
          FROM admissions.candidate c
         WHERE a.session      = p_session
           AND c.session      = p_session
           AND a.candidate_id IS NULL
           AND a.jamb_key IS NOT NULL
           AND a.jamb_key     = c.jamb_key
        RETURNING a.kind AS k
    )
    SELECT h.k::text, count(*)::bigint FROM hit h GROUP BY h.k;
END;
$$;

COMMENT ON FUNCTION admissions.attach_pending(text) IS
'Re-matches everything held. Called after every caps batch commit, because '
'a file that matched nobody this morning matches somebody this afternoon.';

-- ── counted in both directions, always ─────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.attachment_state(p_session text)
RETURNS TABLE (finding text, n bigint, owner text, what_it_means text)
LANGUAGE sql
STABLE
AS $$
    SELECT 'Files with no readable registration number'::text,
           count(*)::bigint, 'Academic Office'::text,
           'Nothing in the filename has the shape of a JAMB number. Not '
           'guessed at, not discarded, not matched on a name.'::text
      FROM admissions.attachment
     WHERE session = p_session AND read_as = 'UNREADABLE'
  UNION ALL
    SELECT 'Arrived for nobody on any list'::text,
           count(*)::bigint, 'Academic Office'::text,
           'A readable number that is on no admission list yet. Held: the '
           'next tranche usually claims them.'::text
      FROM admissions.attachment
     WHERE session = p_session AND candidate_id IS NULL AND jamb_key IS NOT NULL
  UNION ALL
    SELECT 'Candidates with no photograph'::text,
           count(*)::bigint, 'Academic Office'::text,
           'Admitted, and nothing to show at screening.'::text
      FROM admissions.candidate c
     WHERE c.session = p_session
       AND NOT EXISTS (SELECT 1 FROM admissions.attachment a
                        WHERE a.candidate_id = c.id AND a.kind = 'PASSPORT')
  UNION ALL
    SELECT 'Numbers that only matched after trimming or extraction'::text,
           count(*)::bigint, 'ICT'::text,
           'Would have matched nothing had the raw value been joined. Kept '
           'as a count so the day it jumps, somebody asks why.'::text
      FROM admissions.attachment
     WHERE session = p_session AND read_as IN ('EMBEDDED','COLUMN')
       AND candidate_id IS NOT NULL
$$;

SELECT audit.attach('admissions.candidate_photo');

-- The intake table is machine-written, one row per file in a folder of
-- four thousand, and is itself the record of what arrived and when.
SELECT audit.exempt('admissions.attachment',
    'Arrival record for bulk files from JAMB: one row per file, written by '
    'the importer, carrying its own arrived_at and the filename as it came. '
    'The batch is audited; the four thousand rows inside it are the evidence, '
    'not the decision.');

GRANT SELECT, INSERT, UPDATE ON admissions.attachment,
      admissions.candidate_photo TO app_admissions;
GRANT SELECT ON admissions.attachment, admissions.candidate_photo TO app_auditor;

COMMIT;
