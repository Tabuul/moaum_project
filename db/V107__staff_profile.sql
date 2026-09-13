-- ── V107 — the staff profile a lecturer keeps about themselves ──────────────
-- A member of staff maintains their own academic profile: the contact the
-- University reaches them on, where they sit (department, faculty, the
-- responsibility they carry), and the record of a scholar's career — Google
-- Scholar, research interests, publications, grants, the postgraduates they
-- have graduated, collaborations, conferences, national and international
-- assignments, innovations, patents, achievements and contributions to
-- society. Every one of these but the scalars is a list that grows, so the
-- lists are held as JSON arrays of lines rather than a table each.
--
-- The row is keyed on iam.person: one profile per person, their own and no
-- other. It is written only through hrm.save_my_staff_profile, which takes the
-- acting person from the audit context and never a parameter — so the endpoint
-- above it cannot be asked to write somebody else's. A recent photograph is
-- held beside it, its bytes in a blob table exempt from audit as every blob is.

CREATE TABLE hrm.staff_profile (
    person_id          uuid PRIMARY KEY REFERENCES iam.person(id) ON DELETE CASCADE,
    email              text,
    phone              text,
    department         text,
    faculty            text,
    responsibility     text,                 -- current responsibility in the department
    scholar_url        text,                 -- Google Scholar profile
    orcid              text,
    research_interests text,                  -- areas of research interest, free prose
    masters_graduated  integer NOT NULL DEFAULT 0,
    phd_graduated      integer NOT NULL DEFAULT 0,
    publications       jsonb NOT NULL DEFAULT '[]'::jsonb,  -- each entry a citation line
    grants             jsonb NOT NULL DEFAULT '[]'::jsonb,  -- grants obtained
    collaborations     jsonb NOT NULL DEFAULT '[]'::jsonb,  -- local and international
    conferences        jsonb NOT NULL DEFAULT '[]'::jsonb,  -- conferences attended
    assignments        jsonb NOT NULL DEFAULT '[]'::jsonb,  -- national and international assignments
    innovations        jsonb NOT NULL DEFAULT '[]'::jsonb,  -- innovations
    patents            jsonb NOT NULL DEFAULT '[]'::jsonb,  -- patents
    achievements       jsonb NOT NULL DEFAULT '[]'::jsonb,  -- achievements
    contributions      jsonb NOT NULL DEFAULT '[]'::jsonb,  -- contributions to society
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sp_masters CHECK (masters_graduated >= 0),
    CONSTRAINT ck_sp_phd     CHECK (phd_graduated >= 0),
    CONSTRAINT ck_sp_email   CHECK (email IS NULL OR email = '' OR email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    CONSTRAINT ck_sp_lists   CHECK (
        jsonb_typeof(publications) = 'array' AND jsonb_typeof(grants) = 'array'
        AND jsonb_typeof(collaborations) = 'array' AND jsonb_typeof(conferences) = 'array'
        AND jsonb_typeof(assignments) = 'array' AND jsonb_typeof(innovations) = 'array'
        AND jsonb_typeof(patents) = 'array' AND jsonb_typeof(achievements) = 'array'
        AND jsonb_typeof(contributions) = 'array')
);

COMMENT ON TABLE hrm.staff_profile IS
  'A member of staff''s own academic profile, one row per iam.person, written '
  'only through hrm.save_my_staff_profile by the person themselves.';

SELECT audit.attach('hrm.staff_profile');

CREATE TABLE hrm.staff_photo (
    person_id    uuid PRIMARY KEY REFERENCES iam.person(id) ON DELETE CASCADE,
    content_type text NOT NULL,
    bytes        bigint NOT NULL,
    content      bytea NOT NULL,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_photo_type  CHECK (content_type IN ('image/jpeg', 'image/png')),
    CONSTRAINT ck_photo_bytes CHECK (bytes BETWEEN 1 AND 2097152)   -- up to 2 MB
);

COMMENT ON TABLE hrm.staff_photo IS
  'A recent photograph for the staff profile; the bytes sit here, up to 2 MB, '
  'in a table exempt from audit as every blob table is.';

-- ── the write: the acting person's own profile, upserted whole ──────────────
-- One JSON in, one row out. The scalars are read out of it; a missing scalar
-- becomes NULL and a missing list becomes the empty array, so a partial save
-- is honest rather than half-applied. The actor is the audit context's, never
-- the caller's word, so this cannot be turned on another person's record.
CREATE OR REPLACE FUNCTION hrm.save_my_staff_profile(p jsonb)
RETURNS hrm.staff_profile
LANGUAGE plpgsql AS $$
DECLARE
    who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    r   hrm.staff_profile;
    arr CONSTANT text[] := ARRAY['publications','grants','collaborations','conferences',
                                 'assignments','innovations','patents','achievements','contributions'];
    k   text;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a profile is saved by the person themselves' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.person WHERE id = who) THEN
        RAISE EXCEPTION 'no person % on the register', who USING ERRCODE = '23503';
    END IF;
    -- every list field must be a JSON array or absent
    FOREACH k IN ARRAY arr LOOP
        IF p ? k AND jsonb_typeof(p -> k) <> 'array' THEN
            RAISE EXCEPTION '% must be a list', k USING ERRCODE = '22023';
        END IF;
    END LOOP;

    INSERT INTO hrm.staff_profile AS sp (
        person_id, email, phone, department, faculty, responsibility, scholar_url, orcid,
        research_interests, masters_graduated, phd_graduated,
        publications, grants, collaborations, conferences, assignments, innovations,
        patents, achievements, contributions, updated_at)
    VALUES (
        who,
        nullif(btrim(p ->> 'email'), ''),
        nullif(btrim(p ->> 'phone'), ''),
        nullif(btrim(p ->> 'department'), ''),
        nullif(btrim(p ->> 'faculty'), ''),
        nullif(btrim(p ->> 'responsibility'), ''),
        nullif(btrim(p ->> 'scholarUrl'), ''),
        nullif(btrim(p ->> 'orcid'), ''),
        nullif(btrim(p ->> 'researchInterests'), ''),
        greatest(0, coalesce((p ->> 'mastersGraduated')::int, 0)),
        greatest(0, coalesce((p ->> 'phdGraduated')::int, 0)),
        coalesce(p -> 'publications', '[]'::jsonb),
        coalesce(p -> 'grants', '[]'::jsonb),
        coalesce(p -> 'collaborations', '[]'::jsonb),
        coalesce(p -> 'conferences', '[]'::jsonb),
        coalesce(p -> 'assignments', '[]'::jsonb),
        coalesce(p -> 'innovations', '[]'::jsonb),
        coalesce(p -> 'patents', '[]'::jsonb),
        coalesce(p -> 'achievements', '[]'::jsonb),
        coalesce(p -> 'contributions', '[]'::jsonb),
        now())
    ON CONFLICT (person_id) DO UPDATE SET
        email = excluded.email, phone = excluded.phone, department = excluded.department,
        faculty = excluded.faculty, responsibility = excluded.responsibility,
        scholar_url = excluded.scholar_url, orcid = excluded.orcid,
        research_interests = excluded.research_interests,
        masters_graduated = excluded.masters_graduated, phd_graduated = excluded.phd_graduated,
        publications = excluded.publications, grants = excluded.grants,
        collaborations = excluded.collaborations, conferences = excluded.conferences,
        assignments = excluded.assignments, innovations = excluded.innovations,
        patents = excluded.patents, achievements = excluded.achievements,
        contributions = excluded.contributions, updated_at = now()
    RETURNING sp.* INTO r;

    RETURN r;
END $$;

-- ── the photograph: the acting person's own, upserted ───────────────────────
CREATE OR REPLACE FUNCTION hrm.set_my_staff_photo(p_content_type text, p_bytes bigint, p_content bytea)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a photograph is set by the person themselves' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.person WHERE id = who) THEN
        RAISE EXCEPTION 'no person % on the register', who USING ERRCODE = '23503';
    END IF;
    INSERT INTO hrm.staff_photo (person_id, content_type, bytes, content, updated_at)
    VALUES (who, p_content_type, p_bytes, p_content, now())
    ON CONFLICT (person_id) DO UPDATE SET
        content_type = excluded.content_type, bytes = excluded.bytes,
        content = excluded.content, updated_at = now();
END $$;
