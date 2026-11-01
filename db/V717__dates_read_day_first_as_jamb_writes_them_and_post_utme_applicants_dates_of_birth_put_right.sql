-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V717 · Dates are read as Nigeria writes them — day, month, year — and Post-UTME applicants' dates of birth are put right
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 1 November 2026: a Post-UTME applicant's JAMB result slip gives the date of birth 12 September 2003;
--  JAMB's date-of-birth file writes it "12-09-2003"; the portal showed 9 December 2003. "This date of birth should be corrected for
--  all post utme applicants."
--
--  Why it happened. Two readers took "12-09-2003" month first:
--   · PostgreSQL's DateStyle was the default 'ISO, MDY', so every text::date in the schema (the old-portal student, biography and
--     postgraduate imports among them) read an ambiguous day-month-year as month-day-year;
--   · the frontend's day() and the clearance forms' dmy()/longDate()/ageOn() passed the text to JavaScript's Date, which does the same.
--  JAMB, the old portal and every Nigerian document write day, month, year. The explicit readers already in the schema
--  (jupeb.legacy_date, admissions.cce_date, people.restore_date, admissions.pg_mig_date, finance.legacy_date) read day first; the
--  implicit ones did not.
--
--  What V717 does:
--   1. platform.read_date(text): the one reader — ISO (with or without a time), day/month/year in figures with -, /, . or a space and
--      a two- or four-digit year, the month in words on either side (12 Sep 2003, 12-September-2003, September 12, 2003), an Excel
--      day number; month first only when the figures allow nothing else (09-13-2003); NULL when it cannot be read. And
--      platform.date_misread(text): what the old reading made of a day-month-year text (12-09-2003 → 9 December 2003), NULL when
--      the text was never ambiguous — so a misread on record is recognised exactly, never guessed.
--   2. DateStyle 'ISO, DMY': the database's default, every application role's, and every PL/pgSQL function of the schema that
--      casts a JSON text to a date — so text::date reads day first wherever it still stands, and a session that reads an ambiguous
--      date reads it as the University does. (Output stays ISO.) ISO text is unaffected.
--   3. people.biodata_fields_to_record (V553) reads the form's date of birth with platform.read_date, so a date written day first
--      reaches the record.
--   4. The Post-UTME door's date-of-birth factor (admissions.putme_verify_as, V388) accepts the date however it is written —
--      12/09/2003, 12-09-2003 or 2003-09-12 — compared as dates, beside the digit match it had.
--   5. people.jamb_dates_of_birth(session, commit, reason): every student on the register linked to a candidate with a JAMB
--      date-of-birth file, read against the record — AGREES; FILLED (the record held none: JAMB's date written); CORRECTED (the
--      record held exactly the misread of JAMB's text: JAMB's date written); DIFFERS (another date stands: left for the Registry,
--      listed); UNREADABLE (the file's text is no date). The Biodata form's date of birth is set to JAMB's where it was empty or
--      the same misread. Every write is on the audit spine with the reason. Preview with commit false; the Academic Office, the
--      Registry, Records, the Director of ICT and super apply it (DOB_RECONCILE_OFFICE otherwise). This migration applies it to
--      every session once — the correction the University asked for.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V717: dates read day first, as JAMB writes them', true);

-- ── 1 · the one reader, and the recognition of the old misreading ──
CREATE OR REPLACE FUNCTION platform.month_no(p text)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE lower(left(btrim(coalesce(p, '')), 3))
             WHEN 'jan' THEN 1 WHEN 'feb' THEN 2 WHEN 'mar' THEN 3 WHEN 'apr' THEN 4 WHEN 'may' THEN 5 WHEN 'jun' THEN 6
             WHEN 'jul' THEN 7 WHEN 'aug' THEN 8 WHEN 'sep' THEN 9 WHEN 'oct' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12 END
$$;
COMMENT ON FUNCTION platform.month_no(text) IS 'V717: a month written in words (Sep, September, SEPT) as its number; NULL otherwise.';

CREATE OR REPLACE FUNCTION platform.read_date(p text)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE s text := btrim(coalesce(p, '')); m text[]; d int; mo int; y int;
BEGIN
    IF s = '' THEN RETURN NULL; END IF;
    -- ISO: 2003-09-12, 2003/9/12, 2003-09-12T00:00:00Z
    m := regexp_match(s, '^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T ].*)?$');
    IF m IS NOT NULL THEN
        BEGIN RETURN make_date(m[1]::int, m[2]::int, m[3]::int); EXCEPTION WHEN others THEN RETURN NULL; END;
    END IF;
    -- day, month, year in figures: 12-09-2003, 12/09/2003, 12.09.2003, 12 09 2003, 12-09-03; month first only when nothing else reads
    m := regexp_match(s, '^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{2}|\d{4})$');
    IF m IS NOT NULL THEN
        y := m[3]::int;
        IF y < 100 THEN y := y + CASE WHEN y > 30 THEN 1900 ELSE 2000 END; END IF;
        IF m[1]::int <= 12 AND m[2]::int > 12 THEN mo := m[1]::int; d := m[2]::int;
        ELSE d := m[1]::int; mo := m[2]::int;
        END IF;
        BEGIN RETURN make_date(y, mo, d); EXCEPTION WHEN others THEN RETURN NULL; END;
    END IF;
    -- the month in words: 12 Sep 2003, 12th September 2003, 12-Sep-03, September 12, 2003, Sep 12 2003
    m := regexp_match(s, '^(\d{1,2})(?:st|nd|rd|th)?[-/ ,.]+([A-Za-z]{3,9})\.?[-/ ,.]+(\d{2}|\d{4})$');
    IF m IS NOT NULL THEN
        d := m[1]::int; mo := platform.month_no(m[2]); y := m[3]::int;
    ELSE
        m := regexp_match(s, '^([A-Za-z]{3,9})\.?[-/ ,.]+(\d{1,2})(?:st|nd|rd|th)?[-/ ,.]+(\d{2}|\d{4})$');
        IF m IS NOT NULL THEN mo := platform.month_no(m[1]); d := m[2]::int; y := m[3]::int; END IF;
    END IF;
    IF m IS NOT NULL THEN
        IF mo IS NULL THEN RETURN NULL; END IF;
        IF y < 100 THEN y := y + CASE WHEN y > 30 THEN 1900 ELSE 2000 END; END IF;
        BEGIN RETURN make_date(y, mo, d); EXCEPTION WHEN others THEN RETURN NULL; END;
    END IF;
    -- an Excel day number (five figures: 1927 onwards)
    IF s ~ '^\d{5}(\.0+)?$' THEN RETURN date '1899-12-30' + floor(s::numeric)::int; END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION platform.read_date(text) IS
  'V717: a date as Nigeria writes it — day, month, year (12-09-2003 is 12 September), ISO, the month in words on either side, an Excel day number; month first only when the figures allow nothing else; NULL when it cannot be read.';

CREATE OR REPLACE FUNCTION platform.date_misread(p text)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE m text[] := regexp_match(btrim(coalesce(p, '')), '^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{4})$');
BEGIN
    IF m IS NULL OR m[1]::int > 12 OR m[2]::int > 12 OR m[1]::int = m[2]::int THEN RETURN NULL; END IF;
    BEGIN RETURN make_date(m[3]::int, m[1]::int, m[2]::int); EXCEPTION WHEN others THEN RETURN NULL; END;
END $$;
COMMENT ON FUNCTION platform.date_misread(text) IS
  'V717: what a month-first reading made of a day-month-year text whose day and month are both twelve or less (12-09-2003 → 9 December 2003); NULL when the text was never ambiguous. Recognises a misread on record exactly.';

-- ── 2 · DateStyle day, month, year: the database, the application roles, the functions that cast JSON text to dates ──
DO $$
DECLARE r record; n_fn int := 0;
BEGIN
    BEGIN
        EXECUTE format('ALTER DATABASE %I SET datestyle = %L', current_database(), 'ISO, DMY');
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE WARNING 'V717: the database''s DateStyle was not set (not its owner); the roles and the readers carry the day-first reading';
    END;
    FOR r IN SELECT rolname FROM pg_roles WHERE rolname LIKE 'app\_%' ORDER BY rolname LOOP
        BEGIN
            EXECUTE format('ALTER ROLE %I SET datestyle = %L', r.rolname, 'ISO, DMY');
        EXCEPTION WHEN insufficient_privilege THEN
            RAISE WARNING 'V717: the role %''s DateStyle was not set', r.rolname;
        END;
    END LOOP;
    FOR r IN SELECT p.oid::regprocedure AS fn
               FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
              WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_' AND p.prokind = 'f' AND l.lanname = 'plpgsql'
                AND p.prosrc ~ '(->>|->)\s*''[A-Za-z_0-9]+''\s*\)+::(date|timestamp(tz)?)'
              ORDER BY 1 LOOP
        EXECUTE format('ALTER FUNCTION %s SET datestyle = %L', r.fn, 'ISO, DMY');
        n_fn := n_fn + 1;
    END LOOP;
    RAISE NOTICE 'V717: DateStyle ISO, DMY on the database, the application roles and % functions that cast JSON text to dates or times', n_fn;
END $$;

-- ── 2b · the two old-portal readers that still fell through to a bare cast (V304's finance.legacy_date for a two-digit year,
--         V215's admissions.pg_legacy_ts for every day-month-year cell) read day first ──
CREATE OR REPLACE FUNCTION finance.legacy_date(p text)
RETURNS timestamptz LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text := btrim(coalesce(p, '')); d date;
BEGIN
    IF t = '' THEN RETURN NULL; END IF;
    BEGIN
        IF t ~ '^[0-9]{5}(\.[0-9]+)?$' AND t::numeric BETWEEN 20000 AND 80000 THEN
            RETURN (date '1899-12-30' + floor(t::numeric)::int)::timestamp AT TIME ZONE 'UTC' + ((t::numeric - floor(t::numeric)) * interval '1 day');
        ELSIF t ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}' THEN
            RETURN t::timestamptz;
        ELSIF t ~ '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-]([0-9]{4}|[0-9]{2})(\D|$)' THEN
            -- V717: day, month, year — 13/03/2023, 13-03-23 (platform.read_date; the time of day, when written after it, is not kept)
            d := platform.read_date(substring(t from '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-](?:[0-9]{4}|[0-9]{2})'));
            RETURN d::timestamp AT TIME ZONE 'UTC';
        ELSIF t ~* '^[0-9]{1,2}[ -][a-z]{3,9}[ ,-]+[0-9]{4}' THEN
            RETURN t::date::timestamp AT TIME ZONE 'UTC';
        END IF;
        RETURN t::timestamptz;
    EXCEPTION WHEN OTHERS THEN RETURN NULL;
    END;
END $$;
COMMENT ON FUNCTION finance.legacy_date(text) IS 'V304, V717: a date as the old portal wrote it — ISO, day-first figures with a four- or two-digit year, 13-Mar-2023, an Excel day number — as a timestamp; NULL when it cannot be read.';
ALTER FUNCTION finance.legacy_date(text) SET datestyle = 'ISO, DMY';

CREATE OR REPLACE FUNCTION admissions.pg_legacy_ts(p text)
RETURNS timestamptz
LANGUAGE plpgsql STABLE AS $$
DECLARE v timestamptz; t text := btrim(coalesce(p, '')); d date;
BEGIN
    IF t = '' THEN RETURN NULL; END IF;
    -- V717: a day-month-year cell (12-09-2023, 12/09/23, 12 Sep 2023) read as the old portal wrote it
    IF t !~ '^[0-9]{4}-' THEN
        d := platform.read_date(t);
        IF d IS NULL AND t ~ '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-]([0-9]{4}|[0-9]{2})(\D|$)' THEN
            d := platform.read_date(substring(t from '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-](?:[0-9]{4}|[0-9]{2})'));
        END IF;
        IF d IS NOT NULL THEN RETURN d::timestamp AT TIME ZONE 'UTC'; END IF;
    END IF;
    BEGIN v := t::timestamptz; RETURN v;
    EXCEPTION WHEN OTHERS THEN
        BEGIN v := t::date; RETURN v;
        EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
    END;
END $$;
COMMENT ON FUNCTION admissions.pg_legacy_ts(text) IS 'V215, V717: a legacy date or timestamp cell as a timestamp — day, month, year read as the old portal wrote it; NULL when it cannot be read.';
ALTER FUNCTION admissions.pg_legacy_ts(text) SET datestyle = 'ISO, DMY';

-- ── 3 · the Biodata form's date of birth, read day first (V553 restated) ──
CREATE OR REPLACE FUNCTION people.biodata_fields_to_record() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor text := nullif(current_setting('moaum.actor_id', true), '');
        v_val text := nullif(btrim(NEW.value), ''); v_own boolean; v_dob date; v_phone text; v_email text;
BEGIN
    IF v_val IS NULL OR v_office IS NULL THEN RETURN NEW; END IF;   -- nothing given, or an import: the record's own paths state it
    v_own := v_office = 'student' OR v_actor = NEW.student_id::text;
    IF NEW.field = 'date_of_birth' THEN
        v_dob := platform.read_date(v_val);   -- V717: 2003-09-12 and 12-09-2003 alike
        IF v_dob IS NULL OR v_dob > current_date OR v_dob < date '1900-01-01' THEN RETURN NEW; END IF;
        -- the student's own answer fills an empty record only; an office's corrects it
        UPDATE people.student SET date_of_birth = v_dob
         WHERE id = NEW.student_id AND date_of_birth IS DISTINCT FROM v_dob AND (NOT v_own OR date_of_birth IS NULL);
    ELSIF NEW.field = 'mobile' THEN
        v_phone := regexp_replace(v_val, '\D', '', 'g');
        v_phone := CASE WHEN v_phone ~ '^234[0-9]{10}$' THEN '0' || substr(v_phone, 4) ELSE v_phone END;
        IF v_phone !~ '^0[0-9]{10}$' THEN RETURN NEW; END IF;
        INSERT INTO people.student_contact (student_id, phone) VALUES (NEW.student_id, v_phone)
        ON CONFLICT (student_id) DO UPDATE SET phone = v_phone, updated_at = now()
         WHERE nullif(btrim(people.student_contact.phone), '') IS NULL;
    ELSIF NEW.field = 'personal_email' THEN
        v_email := lower(v_val);
        IF v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN RETURN NEW; END IF;
        INSERT INTO people.student_contact (student_id, email) VALUES (NEW.student_id, v_email)
        ON CONFLICT (student_id) DO UPDATE SET email = v_email, updated_at = now()
         WHERE nullif(btrim(people.student_contact.email), '') IS NULL;
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION people.biodata_fields_to_record() IS
  'V553, V717: the date of birth given on the Biodata form — read day first (platform.read_date) — reaches people.student (by an office always, by the student only into an empty record); the phone and e-mail fill an empty people.student_contact';

-- ── 4 · the Post-UTME door's date-of-birth factor, compared as a date (V388 restated) ──
CREATE OR REPLACE FUNCTION admissions.putme_verify_as(p_session text, p_jamb text, p_proof text, p_kind text)
RETURNS uuid
LANGUAGE plpgsql STABLE AS $$
DECLARE a record; v_kind text := upper(coalesce(p_kind, 'APPLICATION_NO')); v_proof text := upper(regexp_replace(coalesce(p_proof, ''), '\s+', '', 'g')); v_ok boolean := false;
        v_date date := platform.read_date(p_proof);
BEGIN
    IF coalesce(btrim(p_jamb), '') = '' THEN RETURN NULL; END IF;
    IF v_kind <> 'NONE' AND v_proof = '' THEN RETURN NULL; END IF;
    SELECT ap.id, ap.application_no, ap.putme_token, ac.phone, c.id AS candidate_id INTO a
      FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id JOIN admissions.applicant_account ac ON ac.id = ap.account_id
     WHERE ap.session = p_session AND c.jamb_key = upper(btrim(p_jamb)) AND c.entry_mode <> 'CCE';
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_ok := CASE v_kind
              WHEN 'NONE'           THEN true
              WHEN 'APPLICATION_NO' THEN upper(regexp_replace(coalesce(a.application_no, ''), '\s+', '', 'g')) = v_proof
              WHEN 'SLIP_TOKEN'     THEN upper(coalesce(a.putme_token, '')) = v_proof
              WHEN 'PHONE'          THEN regexp_replace(coalesce(a.phone, ''), '\D', '', 'g') <> '' AND right(regexp_replace(coalesce(a.phone, ''), '\D', '', 'g'), 10) = right(regexp_replace(v_proof, '\D', '', 'g'), 10)
              WHEN 'DATE_OF_BIRTH'  THEN EXISTS (SELECT 1 FROM admissions.attachment x WHERE x.candidate_id = a.candidate_id AND x.kind = 'DATE_OF_BIRTH'
                                                    AND ((v_date IS NOT NULL AND platform.read_date(x.payload ->> 'dob') = v_date)   -- V717: 12/09/2003, 12-09-2003 or 2003-09-12
                                                      OR (regexp_replace(v_proof, '\D', '', 'g') <> ''
                                                          AND regexp_replace(coalesce(x.payload ->> 'dob', ''), '\D', '', 'g') = regexp_replace(v_proof, '\D', '', 'g'))))
              ELSE false END;
    RETURN CASE WHEN v_ok THEN a.id END;
END $$;
COMMENT ON FUNCTION admissions.putme_verify_as(text, text, text, text) IS 'V388, V717: the Post-UTME application a JAMB registration number names, with the factor asked for (NONE: the JAMB number alone; a date of birth however it is written), or NULL — never which part was wrong.';

-- ── 5 · the register read against JAMB's date-of-birth file, and put right ──
CREATE OR REPLACE FUNCTION people.jamb_dob_officer()
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE o text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF o IS NULL OR o NOT IN ('academic', 'registrar', 'dregistrar', 'records', 'ict', 'super') THEN
        RAISE EXCEPTION 'DOB_RECONCILE_OFFICE: the register''s dates of birth are put right by the Academic Office, the Registry, Records or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    RETURN o;
END $$;
COMMENT ON FUNCTION people.jamb_dob_officer() IS 'V717: the offices that write JAMB''s date of birth onto the register; DOB_RECONCILE_OFFICE otherwise.';

CREATE OR REPLACE FUNCTION people.jamb_dates_of_birth(p_session text, p_commit boolean, p_reason text DEFAULT NULL)
RETURNS TABLE(student_id uuid, session text, jamb_reg_no text, surname text, other_names text, programme_code text,
              jamb_text text, jamb_date date, held date, form_value text, action text)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE r record; v_reason text := coalesce(nullif(btrim(p_reason), ''), nullif(current_setting('moaum.reason', true), ''), 'Date of birth as JAMB gave it, read day, month, year');
BEGIN
    IF p_commit THEN
        PERFORM people.jamb_dob_officer();
        PERFORM set_config('moaum.reason', v_reason, true);
    END IF;
    FOR r IN
        SELECT s.id, c.session, c.jamb_reg_no, s.surname, s.other_names, s.programme_code, s.date_of_birth AS held,
               x.payload ->> 'dob' AS jamb_text, platform.read_date(x.payload ->> 'dob') AS jamb_date, platform.date_misread(x.payload ->> 'dob') AS misread,
               (SELECT b.value FROM people.biodata b WHERE b.student_id = s.id AND b.field = 'date_of_birth') AS form_value
          FROM people.student s
          JOIN admissions.candidate c ON c.id = s.candidate_id
          JOIN LATERAL (SELECT a.payload FROM admissions.attachment a WHERE a.candidate_id = c.id AND a.kind = 'DATE_OF_BIRTH'
                         ORDER BY a.arrived_at DESC NULLS LAST, a.id LIMIT 1) x ON true
         WHERE s.duplicate_of IS NULL AND (p_session IS NULL OR c.session = p_session)
         ORDER BY c.session, s.surname, s.other_names, s.id
    LOOP
        student_id := r.id; session := r.session; jamb_reg_no := r.jamb_reg_no; surname := r.surname; other_names := r.other_names;
        programme_code := r.programme_code; jamb_text := r.jamb_text; jamb_date := r.jamb_date; held := r.held; form_value := r.form_value;
        action := CASE WHEN r.jamb_date IS NULL THEN 'UNREADABLE'
                       WHEN r.held IS NULL THEN 'FILLED'
                       WHEN r.held = r.jamb_date THEN 'AGREES'
                       WHEN r.misread IS NOT NULL AND r.held = r.misread THEN 'CORRECTED'
                       ELSE 'DIFFERS' END;
        IF p_commit AND action IN ('FILLED', 'CORRECTED', 'AGREES') THEN
            IF action <> 'AGREES' THEN
                UPDATE people.student SET date_of_birth = r.jamb_date WHERE id = r.id;
            END IF;
            -- the Biodata form agrees: empty, or the same misread, it takes JAMB's date (the form's own path, V553, reaches the record)
            IF r.form_value IS NULL OR btrim(r.form_value) = '' OR (r.misread IS NOT NULL AND platform.read_date(r.form_value) = r.misread) THEN
                INSERT INTO people.biodata (student_id, field, value) VALUES (r.id, 'date_of_birth', r.jamb_date::text)
                ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
                form_value := r.jamb_date::text;
            END IF;
        END IF;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION people.jamb_dates_of_birth(text, boolean, text) IS
  'V717: every student linked to a candidate with a JAMB date-of-birth file, read against the record — AGREES, FILLED (an empty record takes JAMB''s date), CORRECTED (a record holding exactly the old misread takes JAMB''s date), DIFFERS (left, listed), UNREADABLE. Commit writes the record and an empty or misread Biodata form, on the audit spine with the reason; preview writes nothing.';

-- ── 6 · the correction the University asked for: every session, once ──
DO $$
DECLARE n_corr int; n_fill int; n_diff int; n_bad int; n_ok int;
BEGIN
    -- the migration acts as the Director of ICT, on the audit spine with its reason (set within this block: a statement-level setting
    -- does not outlive its statement when the file is applied statement by statement)
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
            set_config('moaum.actor_office', 'ict', true),
            set_config('moaum.reason', 'V717: the date of birth JAMB gave, read day, month, year', true);
    SELECT count(*) FILTER (WHERE action = 'CORRECTED'), count(*) FILTER (WHERE action = 'FILLED'), count(*) FILTER (WHERE action = 'DIFFERS'),
           count(*) FILTER (WHERE action = 'UNREADABLE'), count(*) FILTER (WHERE action = 'AGREES')
      INTO n_corr, n_fill, n_diff, n_bad, n_ok
      FROM people.jamb_dates_of_birth(NULL, true, 'V717: the date of birth JAMB gave, read day, month, year');
    RAISE NOTICE 'V717: dates of birth against JAMB''s file — % corrected, % filled, % agree, % differ (left for the Registry), % unreadable', n_corr, n_fill, n_ok, n_diff, n_bad;
END $$;
