-- ═══════════════════════════════════════════════════════════════════════════
-- V038 — a candidate's passport, date of birth and O'Level attach only once
--        the admission list they are on is committed
--
--   The three JAMB downloads (V007) are recorded as they arrive and held,
--   not discarded, until a candidate on a committed list claims them. So far
--   attach_pending matched on the JAMB number alone, which let a file attach
--   to a candidate record that existed before its admission list reconciled
--   and committed. The gate is now the commit: a file attaches only when a
--   NOT-withdrawn caps_row for that number sits in a batch with committed_at
--   set. Everything else stays held, and attachment_state names the files
--   waiting on a commit apart from the files waiting on a number.
--
--   Nothing is deleted and nothing is lost: the same file attaches the
--   moment the Academic Office commits the list it belongs to.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- a candidate is committed when a live CAPS row for its number is in a committed batch
CREATE OR REPLACE FUNCTION admissions.candidate_is_committed(p_session text, p_jamb_key text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM admissions.caps_row r JOIN admissions.caps_batch b ON b.id = r.batch_id
         WHERE r.session = p_session AND r.jamb_key = p_jamb_key AND NOT r.withdrawn AND b.committed_at IS NOT NULL)
$$;

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
           AND admissions.candidate_is_committed(c.session, c.jamb_key)   -- V038: only a committed candidate
        RETURNING a.kind AS k
    )
    SELECT h.k::text, count(*)::bigint FROM hit h GROUP BY h.k;
END;
$$;
COMMENT ON FUNCTION admissions.attach_pending(text) IS
'Re-matches everything held to candidates on a committed admission list. '
'Called after every caps batch commit, because a file that matched a '
'not-yet-committed candidate this morning attaches the moment the list is '
'committed this afternoon.';

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
    SELECT 'Held for a candidate not yet committed'::text,
           count(*)::bigint, 'Academic Office'::text,
           'The number is on a candidate record, but that candidate''s '
           'admission list has not been committed. Nothing attaches, and '
           'nothing is uploaded onto the record, until the list is committed.'::text
      FROM admissions.attachment a
     WHERE a.session = p_session AND a.candidate_id IS NULL AND a.jamb_key IS NOT NULL
       AND EXISTS (SELECT 1 FROM admissions.candidate c WHERE c.session = a.session AND c.jamb_key = a.jamb_key)
       AND NOT admissions.candidate_is_committed(a.session, a.jamb_key)
  UNION ALL
    SELECT 'Arrived for nobody on any list'::text,
           count(*)::bigint, 'Academic Office'::text,
           'A readable number that is on no admission list yet. Held: the '
           'next tranche usually claims them.'::text
      FROM admissions.attachment a
     WHERE a.session = p_session AND a.candidate_id IS NULL AND a.jamb_key IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM admissions.candidate c WHERE c.session = a.session AND c.jamb_key = a.jamb_key)
  UNION ALL
    SELECT 'Candidates with no photograph'::text,
           count(*)::bigint, 'Academic Office'::text,
           'Committed, and nothing to show at screening.'::text
      FROM admissions.candidate c
     WHERE c.session = p_session
       AND admissions.candidate_is_committed(c.session, c.jamb_key)
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


COMMIT;
