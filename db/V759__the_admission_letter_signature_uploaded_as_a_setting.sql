-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V759 · The admission letter's signature, uploaded as a setting
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 13 November 2026: the signature printed on the letters of admission is a setting an authorised office
--  uploads, not a file in the code. Until now the letter drew public/signatures/registrar.jpg above the signatory's name (V283); the
--  file was never lodged, so every letter printed with the space empty, and changing it meant a release.
--
--  A signature belongs to a SIGNATORY, found by the name a document template states (credentials.document_template.signatory_name,
--  V262/V283): a letter prints the signature held for the name its template names. An admission letter is drawn with the template
--  in force whenever it is opened (credentials.issued keeps no template version for it), so every admission letter prints the
--  signature of the signatory the template in force names — letters issued earlier included — and once a version names someone
--  else, no letter prints this person's signature until a version names them again (that person's is uploaded in turn).
--
--  · credentials.signatory_key(name): the name as signatures are matched — case, runs of spaces and the spaces either side of a
--    punctuation mark aside ("Andrew Aondoakaa Anjah, MAUA, MIMC" = "andrew  aondoakaa anjah ,maua,mimc"), the same on every
--    database whatever its locale: composed (NFC), and the capitals of the Latin alphabets (Yoruba's and Hausa's letters among
--    them) in small letters by translate(), not by lower(), which changes A-Z alone in the C locale.
--  · credentials.signatory_signature: one row a signatory (by that key): the name as typed, the image as uploaded and as a JPEG on
--    white for the PDF engine with its size in pixels — each in the file store when one is configured, in the row otherwise, as the
--    identity cards' signature (V622) — the version (rising with every upload, replacement and removal), who set it, when and from
--    which office. Audited. Never public: the API serves it to the offices that read the templates, and to a letter's owner inside
--    the letter.
--  · credentials.set_signatory_signature / credentials.remove_signatory_signature: upload or replace (a new version), and remove (the
--    row kept, the images cleared, the version rising — the trail stays). Only the offices that keep the document templates
--    (credentials.signature_office: registrar, dregistrar, academic, super — DocumentsController's CONFIG), and only for a name a
--    document template states.
--  · credentials.signatory_signature_of(name): the signature a document naming that signatory prints, or no row.
--  · credentials.signatory_signatures(): the signatories the current template versions name, and any signature still held for a name
--    none of them names (it prints on no letter while no version names it; listed so it can be removed).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V759: the admission letter''s signature uploaded as a setting', true);

-- ── the name as signatures are matched ──────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION credentials.signatory_key(p_name text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    -- composed first (NFC): a letter typed as its base and a combining mark is the letter. Small letters by translate(), not lower(),
    -- and the spaces and punctuation marks read in the C collation: lower() and the regular expressions' classes follow the
    -- database's locale (lower() changes A-Z alone in the C locale), and a key is the same on every database. The capitals are
    -- those of the Latin alphabets, each with its one small letter: A-Z, Latin-1, Latin Extended-A and -B (Hausa's hooked
    -- letters among them) and Latin Extended Additional (Yoruba's dotted letters). No-break and narrow spaces count as spaces:
    -- names pasted from a word processor carry them
    SELECT nullif(btrim(regexp_replace(regexp_replace(
               translate(normalize(coalesce(p_name, ''), NFC),
                         E'ABCDEFGHIJKLMNOPQRST' ||
                         E'UVWXYZ\u00c0\u00c1\u00c2\u00c3\u00c4\u00c5\u00c6\u00c7\u00c8\u00c9\u00ca\u00cb\u00cc\u00cd' ||
                         E'\u00ce\u00cf\u00d0\u00d1\u00d2\u00d3\u00d4\u00d5\u00d6\u00d8\u00d9\u00da\u00db\u00dc\u00dd\u00de\u0100\u0102\u0104\u0106' ||
                         E'\u0108\u010a\u010c\u010e\u0110\u0112\u0114\u0116\u0118\u011a\u011c\u011e\u0120\u0122\u0124\u0126\u0128\u012a\u012c\u012e' ||
                         E'\u0132\u0134\u0136\u0139\u013b\u013d\u013f\u0141\u0143\u0145\u0147\u014a\u014c\u014e\u0150\u0152\u0154\u0156\u0158\u015a' ||
                         E'\u015c\u015e\u0160\u0162\u0164\u0166\u0168\u016a\u016c\u016e\u0170\u0172\u0174\u0176\u0178\u0179\u017b\u017d\u0181\u0182' ||
                         E'\u0184\u0186\u0187\u0189\u018a\u018b\u018e\u018f\u0190\u0191\u0193\u0194\u0196\u0197\u0198\u019c\u019d\u019f\u01a0\u01a2' ||
                         E'\u01a4\u01a6\u01a7\u01a9\u01ac\u01ae\u01af\u01b1\u01b2\u01b3\u01b5\u01b7\u01b8\u01bc\u01c4\u01c5\u01c7\u01c8\u01ca\u01cb' ||
                         E'\u01cd\u01cf\u01d1\u01d3\u01d5\u01d7\u01d9\u01db\u01de\u01e0\u01e2\u01e4\u01e6\u01e8\u01ea\u01ec\u01ee\u01f1\u01f2\u01f4' ||
                         E'\u01f6\u01f7\u01f8\u01fa\u01fc\u01fe\u0200\u0202\u0204\u0206\u0208\u020a\u020c\u020e\u0210\u0212\u0214\u0216\u0218\u021a' ||
                         E'\u021c\u021e\u0220\u0222\u0224\u0226\u0228\u022a\u022c\u022e\u0230\u0232\u023a\u023b\u023d\u023e\u0241\u0243\u0244\u0245' ||
                         E'\u0246\u0248\u024a\u024c\u024e\u1e00\u1e02\u1e04\u1e06\u1e08\u1e0a\u1e0c\u1e0e\u1e10\u1e12\u1e14\u1e16\u1e18\u1e1a\u1e1c' ||
                         E'\u1e1e\u1e20\u1e22\u1e24\u1e26\u1e28\u1e2a\u1e2c\u1e2e\u1e30\u1e32\u1e34\u1e36\u1e38\u1e3a\u1e3c\u1e3e\u1e40\u1e42\u1e44' ||
                         E'\u1e46\u1e48\u1e4a\u1e4c\u1e4e\u1e50\u1e52\u1e54\u1e56\u1e58\u1e5a\u1e5c\u1e5e\u1e60\u1e62\u1e64\u1e66\u1e68\u1e6a\u1e6c' ||
                         E'\u1e6e\u1e70\u1e72\u1e74\u1e76\u1e78\u1e7a\u1e7c\u1e7e\u1e80\u1e82\u1e84\u1e86\u1e88\u1e8a\u1e8c\u1e8e\u1e90\u1e92\u1e94' ||
                         E'\u1e9e\u1ea0\u1ea2\u1ea4\u1ea6\u1ea8\u1eaa\u1eac\u1eae\u1eb0\u1eb2\u1eb4\u1eb6\u1eb8\u1eba\u1ebc\u1ebe\u1ec0\u1ec2\u1ec4' ||
                         E'\u1ec6\u1ec8\u1eca\u1ecc\u1ece\u1ed0\u1ed2\u1ed4\u1ed6\u1ed8\u1eda\u1edc\u1ede\u1ee0\u1ee2\u1ee4\u1ee6\u1ee8\u1eea\u1eec' ||
                         E'\u1eee\u1ef0\u1ef2\u1ef4\u1ef6\u1ef8\u1efa\u1efc\u1efe',
                         E'abcdefghijklmnopqrst' ||
                         E'uvwxyz\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5\u00e6\u00e7\u00e8\u00e9\u00ea\u00eb\u00ec\u00ed' ||
                         E'\u00ee\u00ef\u00f0\u00f1\u00f2\u00f3\u00f4\u00f5\u00f6\u00f8\u00f9\u00fa\u00fb\u00fc\u00fd\u00fe\u0101\u0103\u0105\u0107' ||
                         E'\u0109\u010b\u010d\u010f\u0111\u0113\u0115\u0117\u0119\u011b\u011d\u011f\u0121\u0123\u0125\u0127\u0129\u012b\u012d\u012f' ||
                         E'\u0133\u0135\u0137\u013a\u013c\u013e\u0140\u0142\u0144\u0146\u0148\u014b\u014d\u014f\u0151\u0153\u0155\u0157\u0159\u015b' ||
                         E'\u015d\u015f\u0161\u0163\u0165\u0167\u0169\u016b\u016d\u016f\u0171\u0173\u0175\u0177\u00ff\u017a\u017c\u017e\u0253\u0183' ||
                         E'\u0185\u0254\u0188\u0256\u0257\u018c\u01dd\u0259\u025b\u0192\u0260\u0263\u0269\u0268\u0199\u026f\u0272\u0275\u01a1\u01a3' ||
                         E'\u01a5\u0280\u01a8\u0283\u01ad\u0288\u01b0\u028a\u028b\u01b4\u01b6\u0292\u01b9\u01bd\u01c6\u01c6\u01c9\u01c9\u01cc\u01cc' ||
                         E'\u01ce\u01d0\u01d2\u01d4\u01d6\u01d8\u01da\u01dc\u01df\u01e1\u01e3\u01e5\u01e7\u01e9\u01eb\u01ed\u01ef\u01f3\u01f3\u01f5' ||
                         E'\u0195\u01bf\u01f9\u01fb\u01fd\u01ff\u0201\u0203\u0205\u0207\u0209\u020b\u020d\u020f\u0211\u0213\u0215\u0217\u0219\u021b' ||
                         E'\u021d\u021f\u019e\u0223\u0225\u0227\u0229\u022b\u022d\u022f\u0231\u0233\u2c65\u023c\u019a\u2c66\u0242\u0180\u0289\u028c' ||
                         E'\u0247\u0249\u024b\u024d\u024f\u1e01\u1e03\u1e05\u1e07\u1e09\u1e0b\u1e0d\u1e0f\u1e11\u1e13\u1e15\u1e17\u1e19\u1e1b\u1e1d' ||
                         E'\u1e1f\u1e21\u1e23\u1e25\u1e27\u1e29\u1e2b\u1e2d\u1e2f\u1e31\u1e33\u1e35\u1e37\u1e39\u1e3b\u1e3d\u1e3f\u1e41\u1e43\u1e45' ||
                         E'\u1e47\u1e49\u1e4b\u1e4d\u1e4f\u1e51\u1e53\u1e55\u1e57\u1e59\u1e5b\u1e5d\u1e5f\u1e61\u1e63\u1e65\u1e67\u1e69\u1e6b\u1e6d' ||
                         E'\u1e6f\u1e71\u1e73\u1e75\u1e77\u1e79\u1e7b\u1e7d\u1e7f\u1e81\u1e83\u1e85\u1e87\u1e89\u1e8b\u1e8d\u1e8f\u1e91\u1e93\u1e95' ||
                         E'\u00df\u1ea1\u1ea3\u1ea5\u1ea7\u1ea9\u1eab\u1ead\u1eaf\u1eb1\u1eb3\u1eb5\u1eb7\u1eb9\u1ebb\u1ebd\u1ebf\u1ec1\u1ec3\u1ec5' ||
                         E'\u1ec7\u1ec9\u1ecb\u1ecd\u1ecf\u1ed1\u1ed3\u1ed5\u1ed7\u1ed9\u1edb\u1edd\u1edf\u1ee1\u1ee3\u1ee5\u1ee7\u1ee9\u1eeb\u1eed' ||
                         E'\u1eef\u1ef1\u1ef3\u1ef5\u1ef7\u1ef9\u1efb\u1efd\u1eff') COLLATE "C",
               '[\s\u00a0\u2007\u202f]+', ' ', 'g'), ' ?([[:punct:]]) ?', '\1', 'g')), '')
$$;
COMMENT ON FUNCTION credentials.signatory_key(text) IS
  'V759: a signatory''s name as a signature is matched to a document template — composed (NFC), the Latin capitals in small letters whatever the database''s locale, spaces run together and none either side of a punctuation mark ("Anjah, MAUA" = "anjah ,maua"); NULL for a blank name';

-- ── who keeps the signatures: the offices that keep the document templates ────────────────────────────────────────────────────
CREATE FUNCTION credentials.signature_office(p_office text) RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT coalesce(p_office IN ('registrar', 'dregistrar', 'academic', 'super'), false)
$$;
COMMENT ON FUNCTION credentials.signature_office(text) IS
  'V759: true for an office that uploads, replaces or removes a signatory''s signature — the offices that change the document templates (the Registrar, the Deputy Registrar, the Academic Office; super)';

-- ── the signatures ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE credentials.signatory_signature (
    name_key                 text PRIMARY KEY,
    name                     text NOT NULL,
    signature                bytea NULL,
    signature_object_id      uuid NULL REFERENCES platform.file_object(id) ON DELETE SET NULL,
    signature_type           text NULL,
    signature_jpeg           bytea NULL,
    signature_jpeg_object_id uuid NULL REFERENCES platform.file_object(id) ON DELETE SET NULL,
    jpeg_width               integer NULL,
    jpeg_height              integer NULL,
    version                  integer NOT NULL DEFAULT 1,
    set_at                   timestamptz NOT NULL DEFAULT now(),
    set_by                   uuid NOT NULL,
    set_office               text NOT NULL,
    CONSTRAINT ck_signatory_signature_key CHECK (name_key IS NOT DISTINCT FROM credentials.signatory_key(name)),
    CONSTRAINT ck_signatory_signature_type CHECK (signature_type IS NULL OR signature_type IN ('image/png', 'image/jpeg')),
    -- a removed signature leaves nothing behind it in the row
    CONSTRAINT ck_signatory_signature_cleared CHECK (signature_type IS NOT NULL OR (signature IS NULL AND signature_object_id IS NULL
                                                     AND signature_jpeg IS NULL AND signature_jpeg_object_id IS NULL
                                                     AND jpeg_width IS NULL AND jpeg_height IS NULL)),
    CONSTRAINT ck_signatory_signature_size CHECK ((jpeg_width IS NULL) = (jpeg_height IS NULL) AND coalesce(jpeg_width > 0 AND jpeg_height > 0, true))
);
COMMENT ON TABLE credentials.signatory_signature IS
  'V759: a signatory''s signature, by the name a document template states (name_key = credentials.signatory_key(name)): as uploaded and as a JPEG on white for the PDF engine (each in the file store when one is configured, else in the row), the version rising with every upload, replacement and removal; set by the offices that keep the document templates; never public';
COMMENT ON COLUMN credentials.signatory_signature.name IS 'V759: the signatory''s name as last typed for the upload';
COMMENT ON COLUMN credentials.signatory_signature.jpeg_width IS 'V759: the JPEG''s width in pixels (at most 800 a side), so a letter fits it without decoding it';
SELECT audit.attach('credentials.signatory_signature');

-- ── upload or replace ───────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION credentials.set_signatory_signature(p_name text, p_signature bytea, p_signature_object uuid, p_type text,
                                                    p_jpeg bytea, p_jpeg_object uuid, p_width integer, p_height integer)
RETURNS credentials.signatory_signature LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_key text := credentials.signatory_key(p_name); s credentials.signatory_signature;
BEGIN
    IF who IS NULL OR NOT credentials.signature_office(office) THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_OFFICE: a signature on the University''s documents is uploaded by the offices that keep the document templates (the Registrar, the Deputy Registrar or the Academic Office)'
              USING ERRCODE = '42501';
    END IF;
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_NAME: say whose signature this is, by the name the document template states' USING ERRCODE = '23514';
    END IF;
    -- a name no template states would never print: almost always a typing slip
    IF NOT EXISTS (SELECT 1 FROM credentials.document_template t WHERE credentials.signatory_key(t.signatory_name) = v_key) THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_UNKNOWN: no document template names "%" as its signatory; upload the signature for the name the template states', btrim(p_name)
              USING ERRCODE = '23514';
    END IF;
    IF p_type IS NULL OR p_type NOT IN ('image/png', 'image/jpeg') THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_FORMAT: the signature is a PNG or a JPEG' USING ERRCODE = '23514';
    END IF;
    IF (p_signature IS NULL AND p_signature_object IS NULL) OR (p_jpeg IS NULL AND p_jpeg_object IS NULL) THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_IMAGE: the signature comes as uploaded and as the JPEG the letter prints' USING ERRCODE = '23514';
    END IF;
    -- what the row holds is what it says it is (an image in the file store was checked before it was stored)
    IF p_type = 'image/png' AND substring(p_signature FROM 1 FOR 4) <> '\x89504e47'::bytea THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_FORMAT: the file is not the PNG it is said to be' USING ERRCODE = '23514';
    END IF;
    IF p_type = 'image/jpeg' AND substring(p_signature FROM 1 FOR 2) <> '\xffd8'::bytea THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_FORMAT: the file is not the JPEG it is said to be' USING ERRCODE = '23514';
    END IF;
    IF p_jpeg IS NOT NULL AND substring(p_jpeg FROM 1 FOR 2) <> '\xffd8'::bytea THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_FORMAT: the image the letter prints is a JPEG' USING ERRCODE = '23514';
    END IF;
    -- the size in the limit's own unit, rounded up: a file just over the limit never reads as under it
    IF octet_length(p_signature) > 1000000 THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_TOO_LARGE: the signature is % MB (% bytes); the limit is 1 MB (1,000,000 bytes)',
              to_char(ceil(octet_length(p_signature) / 10000.0) / 100, 'FM990.00'), to_char(octet_length(p_signature), 'FM999,999,999,990')
              USING ERRCODE = '23514';
    END IF;
    IF p_width IS NULL OR p_height IS NULL OR p_width NOT BETWEEN 1 AND 800 OR p_height NOT BETWEEN 1 AND 800 THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_IMAGE: the JPEG the letter prints is at most 800 pixels a side, and its size is given' USING ERRCODE = '23514';
    END IF;
    INSERT INTO credentials.signatory_signature AS c (name_key, name, signature, signature_object_id, signature_type, signature_jpeg,
                                                      signature_jpeg_object_id, jpeg_width, jpeg_height, version, set_at, set_by, set_office)
    VALUES (v_key, btrim(p_name), p_signature, p_signature_object, p_type, p_jpeg, p_jpeg_object, p_width, p_height, 1, now(), who, office)
    ON CONFLICT (name_key) DO UPDATE SET
        name = EXCLUDED.name, signature = EXCLUDED.signature, signature_object_id = EXCLUDED.signature_object_id,
        signature_type = EXCLUDED.signature_type, signature_jpeg = EXCLUDED.signature_jpeg, signature_jpeg_object_id = EXCLUDED.signature_jpeg_object_id,
        jpeg_width = EXCLUDED.jpeg_width, jpeg_height = EXCLUDED.jpeg_height,
        version = c.version + 1, set_at = now(), set_by = who, set_office = office
    RETURNING * INTO s;
    RETURN s;
END $$;
COMMENT ON FUNCTION credentials.set_signatory_signature(text, bytea, uuid, text, bytea, uuid, integer, integer) IS
  'V759: upload or replace the signature of the signatory a document template names (p_name, matched by credentials.signatory_key): the image as uploaded (bytes or file-store object) and its type, the JPEG on white the PDF prints (bytes or object) and its width and height in pixels (1 to 800); a replacement takes the next version — the offices that keep the document templates';

-- ── remove ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION credentials.remove_signatory_signature(p_name text)
RETURNS credentials.signatory_signature LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s credentials.signatory_signature;
BEGIN
    IF who IS NULL OR NOT credentials.signature_office(office) THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_OFFICE: a signature on the University''s documents is removed by the offices that keep the document templates (the Registrar, the Deputy Registrar or the Academic Office)'
              USING ERRCODE = '42501';
    END IF;
    -- the row stays (nothing is deleted, D11): the images go, the version rises, the trail says who removed it
    UPDATE credentials.signatory_signature c SET
        signature = NULL, signature_object_id = NULL, signature_type = NULL, signature_jpeg = NULL, signature_jpeg_object_id = NULL,
        jpeg_width = NULL, jpeg_height = NULL, version = c.version + 1, set_at = now(), set_by = who, set_office = office
     WHERE c.name_key = credentials.signatory_key(p_name) AND c.signature_type IS NOT NULL
    RETURNING * INTO s;
    IF s.name_key IS NULL THEN
        RAISE EXCEPTION 'SIGNATORY_SIGNATURE_NONE: no signature is held for "%"', btrim(coalesce(p_name, '')) USING ERRCODE = 'P0002';
    END IF;
    RETURN s;
END $$;
COMMENT ON FUNCTION credentials.remove_signatory_signature(text) IS
  'V759: remove the signature held for a signatory (matched by credentials.signatory_key): the row and its trail stay, the images are cleared and the version rises; documents naming the signatory then leave the space for a hand signature — the offices that keep the document templates';

-- ── what a document prints ──────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION credentials.signatory_signature_of(p_name text)
RETURNS SETOF credentials.signatory_signature LANGUAGE sql STABLE ROWS 1 AS $$
    SELECT s.* FROM credentials.signatory_signature s
     WHERE s.name_key = credentials.signatory_key(p_name) AND s.signature_type IS NOT NULL
       AND (s.signature_jpeg IS NOT NULL OR s.signature_jpeg_object_id IS NOT NULL)
$$;
COMMENT ON FUNCTION credentials.signatory_signature_of(text) IS
  'V759: the signature a document prints above the signatory its template names (p_name = the template version''s signatory_name), or no row when none is held — a template naming someone else finds that person''s, never this one''s';

CREATE FUNCTION credentials.signatory_signatures()
RETURNS TABLE (name text, name_key text, kinds text[], in_use boolean, has_signature boolean, version integer, set_at timestamptz,
               set_by uuid, set_by_name text, set_office text, signature_type text, jpeg_width integer, jpeg_height integer)
LANGUAGE sql STABLE AS $$
    WITH cur AS (    -- the current version of each kind, as the documents read it
        SELECT DISTINCT ON (t.kind) t.kind, t.signatory_name
          FROM credentials.document_template t WHERE t.active ORDER BY t.kind, t.version DESC
    ), used AS (
        SELECT credentials.signatory_key(c.signatory_name) AS k,
               (array_agg(c.signatory_name ORDER BY c.kind = 'ADMISSION_LETTER' DESC, c.kind))[1] AS name,
               array_agg(c.kind ORDER BY c.kind) AS kinds
          FROM cur c GROUP BY 1
    )
    SELECT coalesce(u.name, s.name), coalesce(u.k, s.name_key), coalesce(u.kinds, '{}'::text[]), u.k IS NOT NULL,
           coalesce(s.signature_type IS NOT NULL AND (s.signature_jpeg IS NOT NULL OR s.signature_jpeg_object_id IS NOT NULL), false),
           s.version, s.set_at, s.set_by,
           nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, ''), ', '), ''), s.set_office, s.signature_type,
           s.jpeg_width, s.jpeg_height
      FROM used u
      FULL JOIN credentials.signatory_signature s ON s.name_key = u.k
      LEFT JOIN iam.person p ON p.id = s.set_by
     WHERE u.k IS NOT NULL OR s.signature_type IS NOT NULL
     ORDER BY coalesce('ADMISSION_LETTER' = ANY (u.kinds), false) DESC, coalesce(u.name, s.name)
$$;
COMMENT ON FUNCTION credentials.signatory_signatures() IS
  'V759: each signatory the current document template versions name (with the kinds naming them; the admission letter''s first) and whether a signature is held, and every signature still held for a name no current version names (in_use false), so it can be removed';

COMMIT;
