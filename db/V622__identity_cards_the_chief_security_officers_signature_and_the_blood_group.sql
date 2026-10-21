-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V622 — Identity cards: the Chief Security Officer's signature, uploaded by the Director of ICT, and the blood group
--
--   The cards' backs were signed for "Registrar" with an empty line, and the front's Blood group read "—" on every card: the
--   card desk had no way to add it. On the University's word:
--
--   · credentials.card_signatory holds who signs the cards for the University — the Chief Security Officer: the name and the
--     signature image (kept as uploaded and as a JPEG on white for the PDF engine; in the file store when one is configured, in
--     the row otherwise). The Directorate of ICT sets, replaces or removes it (credentials.set_card_signatory, offices ict and
--     super); every student and staff card printed after carries it above the "Chief Security Officer" line.
--   · The blood group: a student's is the record's own (people.biodata field blood_group, which the biodata form already asks;
--     the health profile's where the biodata holds none); a member of staff's is held for the card (credentials.staff_card_detail).
--     The card desk (the Security Unit, super) adds or corrects either (credentials.set_blood_group), one of A+, A-, B+, B-, AB+,
--     AB-, O+, O-; the card prints it. credentials.blood_group_of reads what the record says in the common ways ("O positive",
--     "o+ve") as one of the eight, or nothing.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V622: the Chief Security Officer''s signature and the blood group on the identity cards', true);

-- ── who signs the cards ──────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE credentials.card_signatory (
    role                     text PRIMARY KEY,
    title                    text NOT NULL,
    name                     text NULL,
    signature                bytea NULL,
    signature_object_id      uuid NULL REFERENCES platform.file_object(id) ON DELETE SET NULL,
    signature_type           text NULL,
    signature_jpeg           bytea NULL,
    signature_jpeg_object_id uuid NULL REFERENCES platform.file_object(id) ON DELETE SET NULL,
    version                  integer NOT NULL DEFAULT 0,
    set_at                   timestamptz NULL,
    set_by                   uuid NULL,
    set_office               text NULL,
    CONSTRAINT ck_card_signatory_role CHECK (role IN ('CHIEF_SECURITY_OFFICER')),
    CONSTRAINT ck_card_signatory_type CHECK (signature_type IS NULL OR signature_type IN ('image/png', 'image/jpeg'))
);
COMMENT ON TABLE credentials.card_signatory IS
  'V622: who signs the identity cards for the University — the Chief Security Officer: the name and the signature (as uploaded and as a JPEG for the PDF engine; in the file store when one is configured, else in the row); set by the Directorate of ICT';
INSERT INTO credentials.card_signatory (role, title) VALUES ('CHIEF_SECURITY_OFFICER', 'Chief Security Officer');
SELECT audit.attach('credentials.card_signatory');

CREATE FUNCTION credentials.set_card_signatory(p_name text, p_signature bytea, p_signature_object uuid, p_type text,
                                               p_jpeg bytea, p_jpeg_object uuid, p_clear boolean)
RETURNS credentials.card_signatory LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s credentials.card_signatory; v_name text := nullif(btrim(coalesce(p_name, '')), '');
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'CARD_SIGNATORY_OFFICE: the signature on the identity cards is set by the Directorate of ICT' USING ERRCODE = '42501';
    END IF;
    IF p_type IS NOT NULL AND p_type NOT IN ('image/png', 'image/jpeg') THEN
        RAISE EXCEPTION 'CARD_SIGNATURE_FORMAT: the signature is a PNG or a JPEG' USING ERRCODE = '23514';
    END IF;
    UPDATE credentials.card_signatory c SET
        name = CASE WHEN p_name IS NULL THEN c.name ELSE v_name END,
        signature = CASE WHEN p_clear THEN NULL WHEN p_type IS NOT NULL THEN p_signature ELSE c.signature END,
        signature_object_id = CASE WHEN p_clear THEN NULL WHEN p_type IS NOT NULL THEN p_signature_object ELSE c.signature_object_id END,
        signature_type = CASE WHEN p_clear THEN NULL WHEN p_type IS NOT NULL THEN p_type ELSE c.signature_type END,
        signature_jpeg = CASE WHEN p_clear THEN NULL WHEN p_type IS NOT NULL THEN p_jpeg ELSE c.signature_jpeg END,
        signature_jpeg_object_id = CASE WHEN p_clear THEN NULL WHEN p_type IS NOT NULL THEN p_jpeg_object ELSE c.signature_jpeg_object_id END,
        version = c.version + 1, set_at = now(), set_by = who, set_office = office
     WHERE c.role = 'CHIEF_SECURITY_OFFICER' RETURNING * INTO s;
    RETURN s;
END $$;
COMMENT ON FUNCTION credentials.set_card_signatory(text, bytea, uuid, text, bytea, uuid, boolean) IS
  'V622: the Chief Security Officer''s name (NULL leaves it) and signature (a type with the bytes or objects replaces it; p_clear removes it) — the Directorate of ICT''s';

-- ── the blood group the card prints ──────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION credentials.blood_group_of(p_value text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN g IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-') THEN g END
      FROM (SELECT regexp_replace(regexp_replace(regexp_replace(upper(regexp_replace(coalesce(p_value, ''), '\s', '', 'g')),
                   '(POSITIVE|POS|\+VE|VE\+|\(\+\))$', '+'), '(NEGATIVE|NEG|-VE|VE-|\(-\))$', '-'), '^0', 'O') AS g) x
$$;
COMMENT ON FUNCTION credentials.blood_group_of(text) IS
  'V622: a blood group as one of A+, A-, B+, B-, AB+, AB-, O+, O- from the common ways it is written ("O positive", "o+ve", "0+"), or NULL';

CREATE TABLE credentials.staff_card_detail (
    person_id   uuid PRIMARY KEY REFERENCES iam.person(id) ON DELETE CASCADE,
    blood_group text NULL,
    set_at      timestamptz NOT NULL DEFAULT now(),
    set_by      uuid NULL,
    set_office  text NULL,
    CONSTRAINT ck_staff_card_blood CHECK (blood_group IS NULL OR blood_group IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'))
);
COMMENT ON TABLE credentials.staff_card_detail IS 'V622: what the staff identity card prints beside the HR record — the blood group, set at the card desk';
SELECT audit.attach('credentials.staff_card_detail');

CREATE FUNCTION credentials.student_blood_group(p_student uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT credentials.blood_group_of(b.value) FROM people.biodata b WHERE b.student_id = p_student AND b.field = 'blood_group'),
                    (SELECT credentials.blood_group_of(h.blood_group) FROM health.profile h WHERE h.student_id = p_student))
$$;
COMMENT ON FUNCTION credentials.student_blood_group(uuid) IS 'V622: the blood group a student''s card prints — the biodata''s, else the health profile''s';

CREATE FUNCTION credentials.staff_blood_group(p_person uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT d.blood_group FROM credentials.staff_card_detail d WHERE d.person_id = p_person
$$;

CREATE FUNCTION credentials.set_blood_group(p_kind text, p_holder uuid, p_value text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        g text := credentials.blood_group_of(p_value);
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('security', 'super') THEN
        RAISE EXCEPTION 'CARD_BLOOD_OFFICE: the blood group on the identity card is set at the card desk (the Security Unit)' USING ERRCODE = '42501';
    END IF;
    IF g IS NULL THEN
        RAISE EXCEPTION 'CARD_BLOOD_GROUP: a blood group is one of A+, A-, B+, B-, AB+, AB-, O+ or O-' USING ERRCODE = '23514';
    END IF;
    IF p_kind = 'STUDENT' THEN
        IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_holder) THEN
            RAISE EXCEPTION 'CARD_BLOOD_HOLDER: no such student' USING ERRCODE = 'P0002';
        END IF;
        INSERT INTO people.biodata (student_id, field, value) VALUES (p_holder, 'blood_group', g)
        ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value WHERE people.biodata.value IS DISTINCT FROM EXCLUDED.value;
    ELSIF p_kind = 'STAFF' THEN
        IF NOT EXISTS (SELECT 1 FROM iam.person WHERE id = p_holder) THEN
            RAISE EXCEPTION 'CARD_BLOOD_HOLDER: no such member of staff' USING ERRCODE = 'P0002';
        END IF;
        INSERT INTO credentials.staff_card_detail (person_id, blood_group, set_at, set_by, set_office) VALUES (p_holder, g, now(), who, office)
        ON CONFLICT (person_id) DO UPDATE SET blood_group = EXCLUDED.blood_group, set_at = now(), set_by = who, set_office = office;
    ELSE
        RAISE EXCEPTION 'CARD_BLOOD_HOLDER: a card is a student''s or a member of staff''s' USING ERRCODE = '23514';
    END IF;
    RETURN g;
END $$;
COMMENT ON FUNCTION credentials.set_blood_group(text, uuid, text) IS
  'V622: the blood group the card prints, set at the card desk (Security Unit, super): a student''s on the biodata (blood_group), a member of staff''s on credentials.staff_card_detail';

COMMIT;
