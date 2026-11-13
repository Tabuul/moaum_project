-- ═══════════════════════════════════════════════════════════
-- V750 — the nominal roll: the staff uploads follow it, and a re-upload updates who is on record
--
--   The University's word of 12 November 2026, with the November 2026 nominal rolls (Academic Staff, Senior Non-Teaching Staff,
--   Junior Staff): "this is the authentic list of Academic (Teaching) and Non Academic (Non Teaching) staff, visit the staff upload
--   for both so we can update the upload templates, and ones uploading the already existing staff records will be updated against
--   the existing records".
--
--   What stood: both uploads read the old sheet — one "Full Names" cell split at its last word, PNO, sex, first appointment,
--   department or unit, rank, phone, CONUASS / CONTISS. Someone already on record had little more than a blank e-mail or phone filled
--   (the teaching-staff upload also gave them a sign-in and a lecturer office where they had none); the roll's date of birth, LGA,
--   state, confirmation and last promotion had nowhere to go; the teaching-staff upload had no dry run; and neither said, row by row,
--   what it did. The rolls of November 2026 carry the names in three cells (FIRST NAME, MIDDLE NAME, LAST-SURNAME), dates day first,
--   notes where a date is expected ("NA", "NIL", "TOS-[TSB, Makurdi]", "(Transfer of Service) …", "[ALERT]", "dd/mm/yyyy-UPG"), and
--   the junior staff under JP-NO, whose digits are often another person's P number.
--
--   The University's decisions of 12 November 2026:
--     a. a junior's staff number is JP + the digits (JP858), a series of its own; P + the digits stays for academic and senior
--        staff, and a junior is never merged into a P record;
--     b. on re-upload the e-mail and phone are FILLED only where the portal has none — a different one on the roll is reported, never
--        written; everything else the roll carries follows the roll; a blank or 'NA' cell never erases what is on record;
--     c. a row is matched on the staff number alone (whatever its case, V744), never on names; a name that differs is updated and
--        reported.
--
--   1 · hrm.staff_record holds what the roll carries: date of birth, LGA, state of origin, date of confirmation and of last promotion
--       (each with the note the roll gives in its place), the cadre (SENIOR / JUNIOR), the row as the roll gave it and when the roll
--       last changed the record.
--   2 · How a roll's cell is read (hrm.roll_text / roll_key / roll_date / roll_note / roll_phone, hrm.roll_read): whitespace
--       collapsed; blank, NA, NIL, N/A, NONE or a dash is no value; a date is day first (d/m/yyyy, '/', '-' or '.' between, as V717
--       reads every date), the first such date in a cell its date and the cell its note when it says more than the date; an e-mail or
--       phone that is not one is reported, never written. Names and text are compared case and spacing aside.
--       A department, faculty or posting the plain match (V137, V253) does not find is looked for as the roll writes it
--       (hrm.roll_place_key / roll_place_sound, hrm.roll_place): both sides read alike — case and punctuation aside, & as AND, a
--       bracketed note "(LABORATORY)" dropped, the CHS- / DEPT. OF / FACULTY OF / DIRECTORATE OF / OFFICE OF THE before the name
--       dropped, AE and OE as E (PAEDIATRICS, HAEMATOLOGY), CENTER as CENTRE, a plural's S — against the departments, faculties,
--       units, their codes (a code written with punctuation, ZZ-[UNIT] for ZZ_UNIT) and the unit list's own aliases (V253: MATHEMATICS/COMPUTER SCIENCE is
--       the University's own name for MTC); then, for a name of eight letters or more, the consonants alone (a misspelling —
--       HAEMATHOLOGY, COMMUNICATON). The closest reading decides, and only one place may answer it: two places that
--       read alike are no match, and an abbreviation (ULIS, LIBRARY & INFO SCI) or a name with more or other words (MEDICAL
--       MICROBIOLOGY & PARASITOLOGY, ANATOMICAL PATHOLOGY) is never stretched onto a department.
--       A name cell is taken only when it can be read: one left blank (or 'NA') or written as a query — a '?' anywhere, or two
--       names with ' or ' between them ("ADA or ADAEZE", "NGO? ZI?") — is not written; it is reported (unresolved: the
--       field first_name / middle_name / last_name, the reason BLANK or QUERY) and the name on record stands; a cell with no
--       letter in it ('...', '123') is blank. The old sheet's one Full Names cell written as a query is reported the same way
--       (field full_names) and names nobody. A title before the names (PROF., DR, TPL., HON., ALH., REV. FR., DR(MRS), …) is no
--       name (hrm.roll_untitled), nor is a bracket of titles anywhere ('ADA OKORO (DR. MRS).'), in every name cell, the old sheet's
--       Full Names and the given names on record alike (hrm.roll_name_cell); a cell that is only titles, with or without the
--       full stop ('MR', 'PROF DR', 'Dr.'), is blank — but a single bare title-word in LAST-SURNAME stands, since CHIEF or ELDER
--       may be someone's surname. A cell of dots, dashes or an ellipsis only (Word's – — … and the minus sign), an NA written
--       any way ('NILL', 'N/A.', '(NA)', 'N. A.') or a spreadsheet's error ('#N/A', '#REF!') is blank, and a name needs a letter
--       — the Latin letters with their accents (É, Ɓ, Ọ), Greek, Cyrillic or Arabic. The Add forms send
--       the given names whole (given_names), written as typed. A row is a blank line only when every cell but the serial number
--       is blank; a row with something in it and no staff number is reported. Names are compared case and spacing aside in
--       ASCII: a letter outside it (É, Ɓ) is compared as written, so a change of its case alone is written as a change.
--   3 · hrm.roll_apply: one row against the person it names — what differs is written and listed (field, from, to), the contacts
--       filled only where none is on record (and never an e-mail another person holds, or one given to another row of the same
--       upload), the rest listed as kept; nothing written when nothing differs. A blank cell never erases a name (V750 b): the
--       surname follows the roll only when the roll gives one; the given names follow it when the roll gives both cells; with
--       the MIDDLE NAME blank (hrm.roll_given_first) a FIRST NAME whose every word is already among the given names on record
--       leaves them as they are ('JOHN TERSOO', 'ADAKU NGOZI' and 'JOHN-CHIDI TERSOO' all stand for JOHN or NGOZI, 'TERSOO
--       JOHN' for 'JOHN TERSOO'; a title before them, 'DR. JOHN TERSOO', goes), and any other takes the place of the first of
--       them, the rest kept and none repeated ('NGOZI ADAKU' with NKECHI is 'NKECHI ADAKU', 'J.T.' with JOHN is 'JOHN T.',
--       'JOHN TERSOO' with 'JOHN TERSOO PETER' is 'JOHN TERSOO PETER', 'JOHN TERSOO-PETER' with 'MARK PETER' is 'MARK
--       TERSOO-PETER' — a hyphened name kept carries its own words; an apostrophe joins a name, so SA'ADU is SAADU; two
--       hyphened names that share a part both stand, and the part with them); a blank or query FIRST NAME (or a query MIDDLE NAME) leaves
--       the given names as they are ('MARY ANN' is not cut to 'ANN'), the roll's readable first name with them. A new person
--       needs a readable surname and FIRST NAME (on the old sheet, Full Names; on the Add forms, Given names): either blank or a
--       query is the row's ERROR, whatever the MIDDLE NAME holds — worded by the Add forms' own labels for a row they send. It never touches a sign-in, an employment, a photograph or a blood group, and
--       no office but the one the next paragraph moves.
--   4 · iam.import_staff and iam.import_lecturers restated: the roll's columns and the old sheet's both read; a dry run for both,
--       which writes each row in its savepoint and rolls it back — so it meets every rule the upload would and says exactly what the
--       upload will do, and leaves nothing; each returns, besides its counts, created / updated / unchanged / errors and the results,
--       row by row. A new person is made as before (the teaching-staff upload gives the sign-in — the stored password random, the
--       staff id opening the account until a password is chosen, the change forced at sign-in, V428 — and the lecturer office in the home department; the
--       non-teaching upload neither); a staff number too short to be a
--       username (P6: three characters at least, V017) is loaded and placed, its sign-in reported as not made; a new person whose
--       department or posting does not resolve is not loaded (SKIPPED, as before, its message saying the department or posting is
--       not on the portal — ask ICT to add it (or its spelling), or correct the cell, and upload again); someone on record is updated whatever resolves,
--       the department or unit left as it was when it does not, and the old sheet's one cell of names (a guess at the surname)
--       renames nobody — its result names the person as the record does. Each roll keeps to its own staff, by one reading of who
--       is teaching staff (hrm.roll_kind, the one hrm.roll_absent uses): a JP number is non-teaching staff (V750 a); otherwise
--       the category of the live employment, else of the HR record, ACADEMIC — or a lecturer office today — is teaching staff,
--       and an ERROR on the non-teaching upload; NON_ACADEMIC with no lecturer office is non-teaching staff, and an ERROR on the
--       teaching-staff upload — nothing written, the message
--       saying which desk loads them; someone with neither is loaded by whichever roll names them first, and from then on the
--       other refuses them. A staff number given twice in one upload is an ERROR on its second row, named as the first row named
--       them (a dry run and the upload say the same). An e-mail one row of the upload is given is kept from a later row with the
--       same address (GIVEN_TO_ANOTHER_ROW, naming that row's staff number), never written twice — across the requests one
--       upload is sent in too: the screen sends the addresses earlier requests gave (p_claimed), so a dry run and the upload
--       say the same. When the teaching-staff roll changes a lecturer's
--       home department, the lecturer office goes with it as the Edit form moves it (iam.update_lecturer, V140): the lecturer
--       office still open in another department ends today and one opens in the new department — no other office (a head of
--       department's stays) — listed as the change {lecturer_office, from, to}.
--   5 · hrm.roll_absent(kind, numbers): the staff in service of that kind (V698) whose number is not on the roll uploaded — the
--       roll's "on the portal but not on this roll". It reads; nobody is ended by it.
--   6 · iam.update_lecturer (V140) restated: the Edit form moves the lecturer office when the department it saves differs from the
--       record's or from where a lecturer office still open stands, so an office left behind in another department moves on the
--       next save.
-- ═══════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V750: the nominal roll — the staff uploads follow it and update who is on record', true);

-- ── 1 · the HR staff register holds what the roll carries ───────────────────────────────────────────────────────────────────
ALTER TABLE hrm.staff_record
    ADD COLUMN date_of_birth          date        NULL,
    ADD COLUMN lga                    text        NULL,
    ADD COLUMN state_of_origin        text        NULL,
    ADD COLUMN date_of_confirmation   date        NULL,
    ADD COLUMN confirmation_note      text        NULL,
    ADD COLUMN date_of_last_promotion date        NULL,
    ADD COLUMN promotion_note         text        NULL,
    ADD COLUMN cadre                  text        NULL,
    ADD COLUMN roll_as_given          jsonb       NULL,
    ADD COLUMN roll_updated_at        timestamptz NULL;
ALTER TABLE hrm.staff_record ADD CONSTRAINT ck_staffrec_cadre CHECK (cadre IS NULL OR cadre IN ('SENIOR', 'JUNIOR'));
COMMENT ON COLUMN hrm.staff_record.date_of_birth IS 'V750: the date of birth on the nominal roll (day first on the roll).';
COMMENT ON COLUMN hrm.staff_record.lga IS 'V750: the local government area of origin on the nominal roll.';
COMMENT ON COLUMN hrm.staff_record.state_of_origin IS 'V750: the state of origin on the nominal roll.';
COMMENT ON COLUMN hrm.staff_record.date_of_confirmation IS 'V750: the date of confirmation of appointment on the nominal roll; the first date its cell gives.';
COMMENT ON COLUMN hrm.staff_record.confirmation_note IS 'V750: the roll''s DATE OF CONFIRMATION cell when it says more than a date (a transfer of service, a query mark) — as the roll wrote it.';
COMMENT ON COLUMN hrm.staff_record.date_of_last_promotion IS 'V750: the date of last promotion on the nominal roll; the first date its cell gives.';
COMMENT ON COLUMN hrm.staff_record.promotion_note IS 'V750: the roll''s DATE OF LAST PROMOTION cell when it says more than a date (an upgrade, a query mark) — as the roll wrote it.';
COMMENT ON COLUMN hrm.staff_record.cadre IS 'V750: SENIOR or JUNIOR for non-teaching staff (a junior is numbered JP + digits, a series of its own); NULL for academic staff.';
COMMENT ON COLUMN hrm.staff_record.roll_as_given IS 'V750: the nominal roll''s row exactly as it was uploaded, the last time it changed this record.';
COMMENT ON COLUMN hrm.staff_record.roll_updated_at IS 'V750: when an upload of the nominal roll last changed this record.';

-- ── 2 · how a roll's cell is read ───────────────────────────────────────────────────────────────────────────────────────────

-- a cell's text: whitespace collapsed; blank, NA, NIL, N/A, NONE or a dash is no value
CREATE FUNCTION hrm.roll_text(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN t IS NULL OR upper(t) IN ('NA', 'N/A', 'N.A', 'N.A.', 'NIL', 'NONE', 'NULL')
                     OR t ~ '^[[:space:]._\u2010-\u2015\u2026\u2212-]+$'
                     -- an NA written any way (NILL, N/A., (NA), N. A., Not applicable) and a spreadsheet's error cell
                     OR (t !~ '[0-9]' AND upper(regexp_replace(t, '[^A-Za-z]', '', 'g')) IN ('NA', 'NIL', 'NILL', 'NONE', 'NULL', 'NOTAPPLICABLE'))
                     OR upper(t) IN ('#N/A', '#REF!', '#VALUE!', '#NAME?', '#DIV/0!', '#NULL!', '#NUM!', '#SPILL!', '#CALC!') THEN NULL ELSE t END
      FROM (SELECT nullif(btrim(regexp_replace(p, '[\s\u00a0]+', ' ', 'g')), '') AS t) x
$$;
COMMENT ON FUNCTION hrm.roll_text(text) IS
  'V750: a nominal-roll cell as text — whitespace collapsed; NULL for a blank cell, one saying NA, NIL, N/A or NONE, one of dots, dashes or an ellipsis only (- -- . ... and Word''s – — …, the minus sign), an NA written any way (NILL, N/A., (NA), N. A.) or a spreadsheet''s error (#N/A, #REF!) — no value: it never erases what is on record.';

-- the same text compared without regard to case or spacing
CREATE FUNCTION hrm.roll_key(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT upper(nullif(btrim(regexp_replace(p, '[\s\u00a0]+', ' ', 'g')), ''))
$$;
COMMENT ON FUNCTION hrm.roll_key(text) IS
  'V750: a value as a nominal-roll upload compares it with the record — case and spacing aside (SURNAME and Surname are the same name).';

-- a name cell written as a query: a '?' anywhere, or two names with ' or ' between them
CREATE FUNCTION hrm.roll_name_query(p text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(p ~ '\?' OR p ~* '\S\s+or\s+\S', false)
$$;
COMMENT ON FUNCTION hrm.roll_name_query(text) IS
  'V750: true when a nominal-roll name cell is a query rather than a name — a ''?'' anywhere ("NGO? ZI?") or two names with the word or between them ("ADA or ADAEZE"); such a cell is reported, never written.';

-- a name cell that can be read: the cell's text with a letter in it ('...' or '123' is no name)
CREATE FUNCTION hrm.roll_name(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN t ~ '[A-Za-z\u00c0-\u00d6\u00d8-\u00f6\u00f8-\u02af\u0386\u0388-\u03ff\u0400-\u0481\u048a-\u04ff\u0620-\u064a\u066e-\u06d3\u1e00-\u1eff]' THEN t END
      FROM (SELECT hrm.roll_text(p) AS t) x
$$;
COMMENT ON FUNCTION hrm.roll_name(text) IS
  'V750: a nominal-roll name cell as a name — hrm.roll_text, and NULL when the cell has no letter in it (''...'', ''123'', ''–''): such a cell is blank. A letter is a Latin one with or without its accents (É, Ɓ, Ọ), Greek, Cyrillic or Arabic.';

-- the names without the titles before them: PROF., DR, TPL., HON., ALH., REV. FR., DR(MRS), PASTOR (DR) … — a title is followed by
-- a full stop, a space or a bracket, so MSUGH, DRAKE or CHIEFTAIN keep their first letters
CREATE FUNCTION hrm.roll_untitled(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
        -- a bracket of titles ('(MRS)', '(DR. MRS)', '(Dr./Mrs.)'), wherever it stands, with the marks it leaves after it
        '\(\s*(?:(?:PROF|PROFESSOR|ASSOC|ASSOCIATE|DR|MR|MRS|MISS|MS|MADAM|ENGR|ENGINEER|REV|REVD|REVEREND|FR|SR|BARR|ARC|ARCH|TPL|SURV|PHARM|SIR|CHIEF|HON|HONOURABLE|PASTOR|PST|ELDER|DEACON|DCN|DEACONESS|VEN|VENERABLE|ALH|ALHAJ|ALHAJI|ALHAJA|HAJIA|HAJIYA|MALLAM|MALAM|COMR|COMRADE)\.?\s*[,/&]?\s*)+\)[\s.,;:]*', ' ', 'gi'),
        -- the titles before the names, a full stop, a space, a bracket, '/', ',' or '&' after each ('PROF. DR.', 'Dr./Mrs. Ngozi')
        '^\s*((PROF|PROFESSOR|ASSOC|ASSOCIATE|DR|MR|MRS|MISS|MS|MADAM|ENGR|ENGINEER|REV|REVD|REVEREND|FR|SR|BARR|ARC|ARCH|TPL|SURV|PHARM|SIR|CHIEF|HON|HONOURABLE|PASTOR|PST|ELDER|DEACON|DCN|DEACONESS|VEN|VENERABLE|ALH|ALHAJ|ALHAJI|ALHAJA|HAJIA|HAJIYA|MALLAM|MALAM|COMR|COMRADE)(\.+\s*[/,&]?\s*|\s*[/,&]\s*|\s+|(?=\()))+', '', 'i'),
        -- a mark left alone at either end ('ADA .', 'ADA - (MRS)'), and a comma, semicolon or colon ending the cell; a spaced dash
        -- between two names ('OKON - EDET') stands
        '^\s*([[:punct:]\u2010-\u2015\u2018-\u201f\u2026\u2212]+\s+)+|(\s*[,;:]+|\s+[[:punct:]\u2010-\u2015\u2018-\u201f\u2026\u2212]+)+\s*$', '', 'g'),
        '\s+', ' ', 'g'))
$$;
-- a cell that is titles only — one, or several with a full stop, a comma or a space between ('MR', 'PROF DR', 'Dr.', 'DR (MRS)');
-- p_min the fewest titles it must hold
CREATE FUNCTION hrm.roll_titles_only(p text, p_min int DEFAULT 1) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(regexp_replace(p, '[()]', ' ', 'g') ~*
        ('^[\s,./&]*(?:(?:PROF|PROFESSOR|ASSOC|ASSOCIATE|DR|MR|MRS|MISS|MS|MADAM|ENGR|ENGINEER|REV|REVD|REVEREND|FR|SR|BARR|ARC|ARCH|TPL|SURV|PHARM|SIR|CHIEF|HON|HONOURABLE|PASTOR|PST|ELDER|DEACON|DCN|DEACONESS|VEN|VENERABLE|ALH|ALHAJ|ALHAJI|ALHAJA|HAJIA|HAJIYA|MALLAM|MALAM|COMR|COMRADE)(?:\.+[\s,/&]*|[\s,/&]+))' || CASE WHEN p_min > 1 THEN '{' || (p_min - 1) || ',}' ELSE '*' END
         || '(?:PROF|PROFESSOR|ASSOC|ASSOCIATE|DR|MR|MRS|MISS|MS|MADAM|ENGR|ENGINEER|REV|REVD|REVEREND|FR|SR|BARR|ARC|ARCH|TPL|SURV|PHARM|SIR|CHIEF|HON|HONOURABLE|PASTOR|PST|ELDER|DEACON|DCN|DEACONESS|VEN|VENERABLE|ALH|ALHAJ|ALHAJI|ALHAJA|HAJIA|HAJIYA|MALLAM|MALAM|COMR|COMRADE)\.*[\s,./&]*$'), false)
$$;
COMMENT ON FUNCTION hrm.roll_titles_only(text, int) IS
  'V750: true when a nominal-roll name cell holds titles only (PROF., DR, MRS, …, bracketed or not) — at least p_min of them; MSUGH or DRAKE are names, a title needs a full stop, a comma, a space or the cell''s end after it.';

-- the name a name cell gives: no title, no NA, a letter in it; NULL when the cell holds no name. A cell of titles only is no name —
-- in a surname only when its title carries a full stop or a bracket, or there are two, since a bare CHIEF or ELDER may be a surname
CREATE FUNCTION hrm.roll_name_cell(p text, p_surname boolean DEFAULT false) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN t IS NULL THEN NULL
                WHEN hrm.roll_titles_only(t) AND (NOT p_surname OR t ~ '[.()]' OR hrm.roll_titles_only(t, 2)) THEN NULL
                WHEN hrm.roll_titles_only(t) THEN hrm.roll_name(t)
                ELSE hrm.roll_name(hrm.roll_untitled(t)) END
      FROM (SELECT hrm.roll_text(p) AS t) x
$$;
COMMENT ON FUNCTION hrm.roll_name_cell(text, boolean) IS
  'V750: the name a nominal-roll name cell gives — hrm.roll_text, the titles before it and any bracketed title dropped (hrm.roll_untitled), a letter in it (hrm.roll_name); NULL when it holds no name, a cell of titles only among them (in a surname, p_surname, only a dotted, bracketed or doubled title: a bare CHIEF or ELDER may be a surname).';

-- the words of a name, case and punctuation aside — an apostrophe joins (SA''ADU is SAADU), any other mark parts (MARY-ANN, J.T.)
CREATE FUNCTION hrm.roll_words(p text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
    SELECT array_remove(regexp_split_to_array(upper(btrim(regexp_replace(
               regexp_replace(coalesce(p, ''), '[''`\u2018\u2019\u02bc]', '', 'g'),
               '[[:space:][:punct:]\u2010-\u2015\u201a-\u201f\u2026\u2212]+', ' ', 'g'))), ' '), '')
$$;
COMMENT ON FUNCTION hrm.roll_words(text) IS
  'V750: the words of a name as the nominal-roll uploads compare them — upper case; an apostrophe joins (SA''ADU is SAADU); spaces, hyphens, full stops, Word''s dashes and quotes part (MARY-ANN is MARY and ANN, J.T. is J and T).';

COMMENT ON FUNCTION hrm.roll_untitled(text) IS
  'V750: names with the titles before them dropped, and a bracket of titles wherever it stands with the marks it leaves (PROF., DR, TPL., HON., ALH., REV. FR., DR(MRS), ''Dr./Mrs. NGOZI'', ''ADA OKORO (DR. MRS).'', …; one list for the roll and the old sheet), and a mark left alone at either end or a comma ending the cell (a spaced dash between two names stands); a title needs a full stop, a space, a bracket, ''/'', '','' or ''&'' after it here — a cell of titles only is read by hrm.roll_titles_only.';

-- the first day-first date a cell gives (d/m/yyyy; '/', '-' or '.' between; a doubled separator read as one)
CREATE FUNCTION hrm.roll_date(p text) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE m text[];
BEGIN
    m := regexp_match(coalesce(p, ''), '(?<![0-9])0*([0-9]{1,2})\s*[/.-]+\s*0*([0-9]{1,2})\s*[/.-]+\s*([0-9]{4})(?![0-9])');
    IF m IS NULL OR m[3]::int NOT BETWEEN 1900 AND 2100 THEN RETURN NULL; END IF;
    RETURN make_date(m[3]::int, m[2]::int, m[1]::int);
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;      -- 31/02, a month past 12: not a date, never guessed month first
END $$;
COMMENT ON FUNCTION hrm.roll_date(text) IS
  'V750: the first day-first date (d/m/yyyy) in a nominal-roll cell, or NULL — "TOS-TSB-[01/02/2010]" gives 1 February 2010; a day or month out of range is no date (never read month first).';

-- the cell as a note, when it says more than a date
CREATE FUNCTION hrm.roll_note(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN t IS NULL THEN NULL
                WHEN t ~ '^0*[0-9]{1,2}\s*[/.-]+\s*0*[0-9]{1,2}\s*[/.-]+\s*[0-9]{4}$' AND hrm.roll_date(t) IS NOT NULL THEN NULL
                ELSE t END
      FROM (SELECT hrm.roll_text(p) AS t) x
$$;
COMMENT ON FUNCTION hrm.roll_note(text) IS
  'V750: a date cell of the nominal roll kept as a note when it is more than a plain date ("(Transfer of Service) …", "dd/mm/yyyy?", "[ALERT]"); NULL for a plain date or no value.';

-- a Nigerian phone number as the portal writes it (0 and ten digits); NULL when the cell is not one
CREATE FUNCTION hrm.roll_phone(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN s ~ '^0[0-9]{10}$' THEN s
                WHEN s ~ '^234[0-9]{10}$' THEN '0' || substr(s, 4)
                WHEN s ~ '^2340[0-9]{10}$' THEN substr(s, 4)          -- +234 (0) 803 …
                WHEN s ~ '^[789][01][0-9]{8}$' THEN '0' || s      -- a mobile number written without its 0
           END
      FROM (SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') AS s) x   -- every mark aside, as platform.phone_valid reads it
$$;
COMMENT ON FUNCTION hrm.roll_phone(text) IS
  'V750: a phone number as the roll uploads write and compare it: 0 and ten digits (+234 803 123 4567, 2348031234567, 0803-123-4567 and a mobile number written without its 0 are all 08031234567: platform.phone_valid''s rule); NULL when the text is not one.';

-- what a field of the record reads as in an upload's report: a department, unit or faculty by its name
CREATE FUNCTION hrm.roll_shown(p_field text, p_value text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE p_field
               WHEN 'home_department' THEN coalesce((SELECT d.name FROM ref.department d WHERE d.code = p_value), p_value)
               WHEN 'home_unit'       THEN coalesce((SELECT u.name FROM ref.unit u WHERE u.code = p_value), p_value)
               WHEN 'home_faculty'    THEN coalesce((SELECT f.name FROM ref.faculty f WHERE f.code = p_value), p_value)
               ELSE p_value END
$$;
COMMENT ON FUNCTION hrm.roll_shown(text, text) IS
  'V750: a staff-record value as the roll uploads report it — a department, unit or faculty code by its name.';

-- a department, faculty or unit name as the roll uploads compare it when the plain match fails: case and punctuation aside, & as
-- AND, AE and OE as E (British spellings as American), CENTER as CENTRE, DEPT as DEPARTMENT, a plural's S dropped; p_drop_notes
-- drops a bracketed note, p_bare the CHS- / THE / DEPARTMENT OF / FACULTY OF / COLLEGE OF / DIRECTORATE OF / OFFICE OF (THE) before
-- the name
CREATE FUNCTION hrm.roll_place_key(p text, p_drop_notes boolean, p_bare boolean) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT nullif(replace(regexp_replace(
               CASE WHEN p_bare THEN regexp_replace(t, '^((CHS|THE) |(DEPARTMENT|FACULTY|COLLEGE|DIRECTORATE|OFFICE) OF (THE )?)+', '') ELSE t END,
               '\m(\w{2,}[^S\s])S\M', '\1', 'g'), ' ', ''), '')
      FROM (SELECT regexp_replace(regexp_replace(btrim(regexp_replace(regexp_replace(replace(
                       CASE WHEN p_drop_notes THEN regexp_replace(upper(coalesce(p, '')), '\([^)]*\)', ' ', 'g') ELSE upper(coalesce(p, '')) END,
                       '&', ' AND '), 'AE|OE', 'E', 'g'), '[^A-Z0-9]+', ' ', 'g')),
                   '\mCENTER\M', 'CENTRE', 'g'), '\mDEPT\M', 'DEPARTMENT', 'g') AS t) x
$$;
COMMENT ON FUNCTION hrm.roll_place_key(text, boolean, boolean) IS
  'V750: a department, faculty or unit name as the nominal-roll uploads compare it, both sides alike — case and punctuation aside, & as AND, AE and OE as E (PAEDIATRICS is PEDIATRICS, HAEMATOLOGY HEMATOLOGY), CENTER as CENTRE, DEPT as DEPARTMENT, a plural''s S dropped (SCIENCES is SCIENCE); p_drop_notes drops a bracketed note ("DEPT. OF ZZROLL (LABORATORY)"), p_bare the CHS- / THE / DEPARTMENT OF / FACULTY OF / COLLEGE OF / DIRECTORATE OF / OFFICE OF (THE) before the name. NULL for nothing.';

-- the same key by its consonants alone (no vowel, Y or H; a doubled letter once) — a misspelling's reading (HAEMATHOLOGY is
-- HAEMATOLOGY, COMMUNICATON COMMUNICATION); only for a key of eight letters or more, a shorter one too easily another's
CREATE FUNCTION hrm.roll_place_sound(p_key text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN length(p_key) >= 8 THEN regexp_replace(regexp_replace(p_key, '[AEIOUYH]', '', 'g'), '(.)\1+', '\1', 'g') END
$$;
COMMENT ON FUNCTION hrm.roll_place_sound(text) IS
  'V750: a place key (hrm.roll_place_key) by its consonants alone — no vowel, Y or H, a doubled letter once — so a misspelt name (HAEMATHOLOGY, COMMUNICATON) reads as the one it misspells; NULL for a key under eight letters.';

-- where a roll's department, faculty or posting is, when the plain match (V137, V253) finds nothing: p_kind DEPARTMENT (a lecturer's
-- home department), FACULTY (a lecturer's faculty) or POSTING (a non-teaching posting: a unit, department or faculty)
CREATE FUNCTION hrm.roll_place(p_raw text, p_kind text)
RETURNS TABLE (unit_code text, dept_code text, faculty_code text) LANGUAGE sql STABLE AS $$
    WITH roll AS (
        SELECT ARRAY[hrm.roll_place_key(p_raw, false, false), hrm.roll_place_key(p_raw, true, false)] AS given,
               ARRAY[hrm.roll_place_key(p_raw, false, true), hrm.roll_place_key(p_raw, true, true)] AS bare
    ), place AS (
        -- what the portal knows, in the order the unit register reads it (V253): the unit list's aliases, the departments, the
        -- faculties, the units
        SELECT 1 AS rank, CASE WHEN p_kind = 'POSTING' THEN a.unit_code END AS unit_code,
               CASE WHEN p_kind IN ('POSTING', 'DEPARTMENT') THEN a.dept_code END AS dept_code,
               CASE WHEN p_kind IN ('POSTING', 'FACULTY') THEN a.faculty_code END AS faculty_code, a.alias AS name, NULL::text AS code
          FROM ref.unit_alias a
         WHERE p_kind = 'POSTING' OR (p_kind = 'DEPARTMENT' AND a.dept_code IS NOT NULL) OR (p_kind = 'FACULTY' AND a.faculty_code IS NOT NULL)
        UNION ALL
        SELECT 2, NULL, d.code, NULL, d.name, d.code FROM ref.department d WHERE d.ended_on IS NULL AND p_kind IN ('DEPARTMENT', 'POSTING')
        UNION ALL
        SELECT 3, NULL, NULL, f.code, f.name, f.code FROM ref.faculty f WHERE p_kind IN ('FACULTY', 'POSTING')
        UNION ALL
        SELECT 4, u.code, NULL, NULL, u.name, u.code FROM ref.unit u WHERE u.ended_on IS NULL AND p_kind = 'POSTING'
    ), named AS (
        SELECT pl.rank, pl.unit_code, pl.dept_code, pl.faculty_code,
               ARRAY[hrm.roll_place_key(pl.name, false, false), hrm.roll_place_key(pl.name, true, false)] AS given,
               ARRAY[hrm.roll_place_key(pl.name, false, true), hrm.roll_place_key(pl.name, true, true)] AS bare,
               regexp_replace(upper(pl.code), '[^A-Z0-9]', '', 'g') AS code
          FROM place pl
    ), hits AS (
        -- 1 the name as written, 2 without what stands before it, 3 and 4 the same by their consonants (the closest reading first)
        SELECT 1 AS tier, n.rank, n.unit_code, n.dept_code, n.faculty_code FROM named n, roll r
         WHERE n.given && r.given OR n.code = ANY (r.given)
        UNION ALL
        SELECT 2, n.rank, n.unit_code, n.dept_code, n.faculty_code FROM named n, roll r
         WHERE n.bare && r.bare OR n.code = ANY (r.bare)
        UNION ALL
        SELECT 3, n.rank, n.unit_code, n.dept_code, n.faculty_code FROM named n, roll r
         WHERE ARRAY[hrm.roll_place_sound(n.given[1]), hrm.roll_place_sound(n.given[2])]
            && ARRAY[hrm.roll_place_sound(r.given[1]), hrm.roll_place_sound(r.given[2])]
        UNION ALL
        SELECT 4, n.rank, n.unit_code, n.dept_code, n.faculty_code FROM named n, roll r
         WHERE ARRAY[hrm.roll_place_sound(n.bare[1]), hrm.roll_place_sound(n.bare[2])]
            && ARRAY[hrm.roll_place_sound(r.bare[1]), hrm.roll_place_sound(r.bare[2])]
    ), closest AS (
        SELECT h.tier, h.rank FROM hits h ORDER BY h.tier, h.rank LIMIT 1
    )
    -- the closest reading answers only when one place answers it; two that read alike are no match
    SELECT min(h.unit_code), min(h.dept_code), min(h.faculty_code)
      FROM hits h JOIN closest c ON c.tier = h.tier AND c.rank = h.rank
    HAVING count(DISTINCT coalesce(h.unit_code, '') || '|' || coalesce(h.dept_code, '') || '|' || coalesce(h.faculty_code, '')) = 1
$$;
COMMENT ON FUNCTION hrm.roll_place(text, text) IS
  'V750: where a nominal roll''s department (p_kind DEPARTMENT: a department), faculty (FACULTY: a faculty) or posting (POSTING: a unit, department or faculty) is when the plain match (V137, V253) finds nothing — both sides read alike (hrm.roll_place_key), against the unit list''s aliases, the departments, the faculties and the units (that order, as the unit register reads them) and their codes: the name as written, then without the CHS- / DEPT. OF / FACULTY OF … before it, then each by its consonants (hrm.roll_place_sound, a misspelling). The closest reading answers only when exactly one place answers it; no row when none does or two do. An abbreviation, or a name with more or other words, is never stretched onto a place.';

-- one row of the roll (or of the old sheet) read: the person's number and names, and what the record is to hold
CREATE FUNCTION hrm.roll_read(p_row jsonb, p_kind text) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_new boolean; v_raw text; v_digits text; v_junior boolean; v_full text; v_clean text; v_parts text[];
    v_surname text; v_given text; t text; d date; v_stepin text; v_scale text; v_step int; v_row int; v_anycell boolean; v_whole boolean := false;
    v_first text; v_middle text; v_held boolean := false; v_names jsonb := '{}'::jsonb;
    v_vals jsonb := '{}'::jsonb; v_bad jsonb := '[]'::jsonb;
BEGIN
    IF p_row IS NULL OR jsonb_typeof(p_row) <> 'object' THEN RETURN NULL; END IF;
    v_row := nullif(left(regexp_replace(coalesce(p_row->>'sheet_row', ''), '[^0-9]', '', 'g'), 9), '')::int;
    -- a blank line: every cell but the row and serial numbers blank (a row with anything in it and no staff number is reported)
    v_anycell := EXISTS (SELECT 1 FROM jsonb_each_text(p_row) e
                          WHERE e.key NOT IN ('sheet_row', 'sno', 's_no', 'serial') AND hrm.roll_text(e.value) IS NOT NULL);

    -- the names: the roll's three cells, or the old sheet's one (titles dropped, the surname its last word). A cell left blank (or
    -- 'NA') or written as a query is not taken: it is reported, and what is on record stands (hrm.roll_apply) — a blank or query
    -- FIRST NAME, or a query MIDDLE NAME, holds the given names on record as they are (names_held)
    v_new := p_row ?| ARRAY['first_name', 'middle_name', 'last_name', 'surname'];
    IF v_new THEN
        v_surname := hrm.roll_text(coalesce(p_row->>'last_name', p_row->>'surname'));
        v_first := hrm.roll_text(p_row->>'first_name');
        v_middle := hrm.roll_text(p_row->>'middle_name');
        IF v_surname ~* '^(last[\s_-]*(sur)?name|surname)$' OR v_first ~* '^first[\s_-]*name' THEN RETURN NULL; END IF;   -- a header
        -- the Add forms send the given names whole (given_names), to be written as typed
        v_whole := p_row ? 'given_names' AND NOT p_row ?| ARRAY['first_name', 'middle_name'];
        IF v_whole THEN v_first := hrm.roll_text(p_row->>'given_names'); v_names := v_names || jsonb_build_object('add_form', true); END IF;
        IF hrm.roll_name_query(v_surname) THEN
            v_bad := v_bad || jsonb_build_object('field', 'last_name', 'onRoll', v_surname, 'reason', 'QUERY');
            v_names := v_names || jsonb_build_object('last_name_query', v_surname);
            v_surname := NULL;
        ELSE
            v_surname := hrm.roll_name_cell(v_surname, true);   -- a title before it is no name; blank, NA, only titles, no letter
            IF v_surname IS NULL AND hrm.roll_name(coalesce(p_row->>'last_name', p_row->>'surname')) IS NOT NULL THEN
                v_names := v_names || jsonb_build_object('last_name_cell', hrm.roll_text(coalesce(p_row->>'last_name', p_row->>'surname')));
            END IF;
            IF v_surname IS NULL THEN
                v_bad := v_bad || jsonb_build_object('field', 'last_name', 'onRoll', hrm.roll_key(coalesce(p_row->>'last_name', p_row->>'surname')), 'reason', 'BLANK');
            END IF;
        END IF;
        IF hrm.roll_name_query(v_first) THEN
            v_bad := v_bad || jsonb_build_object('field', CASE WHEN v_whole THEN 'given_names' ELSE 'first_name' END, 'onRoll', v_first, 'reason', 'QUERY');
            v_names := v_names || jsonb_build_object('first_name_query', v_first);
            v_first := NULL; v_held := true;
        ELSE
            v_first := hrm.roll_name_cell(v_first);
            IF v_first IS NULL AND NOT v_whole AND hrm.roll_name(p_row->>'first_name') IS NOT NULL THEN
                v_names := v_names || jsonb_build_object('first_name_cell', hrm.roll_text(p_row->>'first_name'));
            END IF;
            IF v_first IS NULL THEN
                v_bad := v_bad || jsonb_build_object('field', CASE WHEN v_whole THEN 'given_names' ELSE 'first_name' END,
                                                     'onRoll', hrm.roll_key(p_row->>CASE WHEN v_whole THEN 'given_names' ELSE 'first_name' END), 'reason', 'BLANK');
                v_held := true;
            END IF;
        END IF;
        IF hrm.roll_name_query(v_middle) THEN
            v_bad := v_bad || jsonb_build_object('field', 'middle_name', 'onRoll', v_middle, 'reason', 'QUERY');
            v_middle := NULL; v_held := true;
        ELSE
            v_middle := hrm.roll_name_cell(v_middle);    -- blank, NA or titles only: not listed, and the given names on record stand
        END IF;
        v_given := hrm.roll_text(concat_ws(' ', v_first, v_middle));
        v_names := v_names || CASE WHEN v_whole
                                   THEN jsonb_strip_nulls(jsonb_build_object('given_names', v_first, 'names_held', CASE WHEN v_held THEN true END))
                                   ELSE jsonb_strip_nulls(jsonb_build_object('first_name', v_first, 'middle_name', v_middle,
                                                                             'names_held', CASE WHEN v_held THEN true END)) END;
    ELSE
        v_full := hrm.roll_text(coalesce(p_row->>'full_names', p_row->>'fullNames', p_row->>'name', p_row->>'names', p_row->>'fullname'));
        IF v_full ~* '^(full\s*names?|names?)$' THEN RETURN NULL; END IF;
        IF hrm.roll_name_query(v_full) THEN          -- written as a query: reported, and names nobody
            v_bad := v_bad || jsonb_build_object('field', 'full_names', 'onRoll', v_full, 'reason', 'QUERY');
            v_names := jsonb_build_object('full_names_query', v_full);
        ELSIF hrm.roll_name_cell(v_full) IS NULL THEN   -- blank, NA or titles only: names nobody (a new person's ERROR)
            v_names := jsonb_strip_nulls(jsonb_build_object('full_names_blank', true, 'full_names_cell', v_full));
        ELSE
            v_clean := hrm.roll_name_cell(v_full);
            v_parts := string_to_array(v_clean, ' ');
            IF array_length(v_parts, 1) = 1 THEN
                v_surname := v_parts[1]; v_given := v_parts[1];
            ELSE
                v_surname := v_parts[array_upper(v_parts, 1)];
                v_given := hrm.roll_untitled(array_to_string(v_parts[1:array_upper(v_parts, 1) - 1], ' '));
            END IF;
        END IF;
    END IF;

    -- the number: JP-NO is a junior's (JP + digits); PNO is P + digits
    v_raw := upper(coalesce(p_row->>'jp_no', p_row->>'jpno', ''));
    v_junior := v_raw ~ '[0-9]';
    IF NOT v_junior THEN
        v_raw := upper(coalesce(p_row->>'pno', p_row->>'PNO', p_row->>'staff_number', p_row->>'staffNumber', p_row->>'staffno', ''));
    END IF;
    v_junior := v_junior OR btrim(v_raw) ~ '^JP' OR upper(btrim(coalesce(p_row->>'cadre', ''))) = 'JUNIOR';
    v_digits := regexp_replace(v_raw, '[^0-9]', '', 'g');
    IF v_digits = '' AND (NOT v_anycell OR btrim(v_raw) ~ '^(J?P[\s_-]*NO|PNO|STAFF)') THEN RETURN NULL; END IF;   -- a blank line or a header

    -- the roll's name cells as read (hrm.roll_apply decides the given names against the record), or the old sheet's guess
    v_vals := CASE WHEN v_new THEN jsonb_strip_nulls(jsonb_build_object('surname', v_surname)) || v_names
                   ELSE jsonb_strip_nulls(jsonb_build_object('surname', v_surname, 'given_names', v_given)) || v_names END;

    -- sex, birth, origin
    t := hrm.roll_text(p_row->>'sex');
    IF upper(left(t, 1)) IN ('M', 'F') THEN v_vals := v_vals || jsonb_build_object('sex', upper(left(t, 1)));
    ELSIF t IS NOT NULL THEN v_bad := v_bad || jsonb_build_object('field', 'sex', 'onRoll', t); END IF;
    t := hrm.roll_text(coalesce(p_row->>'date_of_birth', p_row->>'dob', p_row->>'birth_date'));
    d := hrm.roll_date(t);
    IF d IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('date_of_birth', d);
    ELSIF t IS NOT NULL THEN v_bad := v_bad || jsonb_build_object('field', 'date_of_birth', 'onRoll', t); END IF;
    t := hrm.roll_text(p_row->>'lga');
    IF t IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('lga', t); END IF;
    t := hrm.roll_text(coalesce(p_row->>'state', p_row->>'state_of_origin'));
    IF t IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('state_of_origin', t); END IF;

    -- appointment, confirmation, last promotion (a note kept where the roll gives one)
    t := hrm.roll_text(coalesce(p_row->>'date_first_appointment', p_row->>'date_of_1st_appt', p_row->>'dateOf1stAppt',
                                p_row->>'date_first_appt', p_row->>'first_appointment', p_row->>'appointment'));
    d := hrm.roll_date(t);
    IF d IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('date_first_appointment', d);
    ELSIF t IS NOT NULL THEN v_bad := v_bad || jsonb_build_object('field', 'date_first_appointment', 'onRoll', t); END IF;
    -- (a cell with no date in it keeps the date on record and gives its note; a plain date clears the note it replaces)
    t := hrm.roll_text(coalesce(p_row->>'date_of_confirmation', p_row->>'confirmation'));
    IF t IS NOT NULL THEN
        IF hrm.roll_date(t) IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('date_of_confirmation', hrm.roll_date(t)); END IF;
        v_vals := v_vals || jsonb_build_object('confirmation_note', hrm.roll_note(t));
    END IF;
    t := hrm.roll_text(coalesce(p_row->>'date_of_last_promotion', p_row->>'last_promotion'));
    IF t IS NOT NULL THEN
        IF hrm.roll_date(t) IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('date_of_last_promotion', hrm.roll_date(t)); END IF;
        v_vals := v_vals || jsonb_build_object('promotion_note', hrm.roll_note(t));
    END IF;

    -- rank and scale (CONUASS for teaching staff; CONTISS and the rest for the others — the old sheet's)
    t := hrm.roll_text(coalesce(p_row->>'present_rank', p_row->>'rank', p_row->>'presentRank', p_row->>'presentrank'));
    IF t IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('present_rank', t); END IF;
    IF p_kind = 'ACADEMIC' THEN
        v_step := nullif(left(regexp_replace(coalesce(p_row->>'conuass', p_row->>'connuas', p_row->>'conuas', p_row->>'conuass_step', ''), '[^0-9]', '', 'g'), 4), '')::int;
        IF v_step IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('conuass_step', v_step); END IF;
    ELSE
        v_stepin := upper(coalesce(hrm.roll_text(coalesce(p_row->>'contiss', p_row->>'scale', p_row->>'grade', p_row->>'conuass')), ''));
        v_scale := CASE WHEN v_stepin LIKE 'CONSOL%' THEN 'CONSOLIDATED' WHEN v_stepin LIKE 'CONUASS%' THEN 'CONUASS' WHEN v_stepin LIKE 'CONUNASS%' THEN 'CONUNASS'
                        WHEN v_stepin LIKE 'CONMESS%' THEN 'CONMESS' WHEN v_stepin LIKE 'CONHESS%' THEN 'CONHESS' WHEN v_stepin <> '' THEN 'CONTISS' END;
        v_step := nullif(left(regexp_replace(v_stepin, '[^0-9]', '', 'g'), 4), '')::int;
        IF v_scale = 'CONSOLIDATED' THEN
            v_vals := v_vals || jsonb_build_object('salary_scale', v_scale, 'contiss_step', NULL);
        ELSIF v_scale IS NOT NULL THEN
            v_vals := v_vals || jsonb_build_object('salary_scale', v_scale);
            IF v_step IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('contiss_step', v_step); END IF;
        END IF;
    END IF;

    -- the contacts as the roll gives them (checked and filled by hrm.roll_apply)
    t := hrm.roll_text(coalesce(p_row->>'email', p_row->>'e_mail', p_row->>'email_personal'));
    IF t IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('email', t); END IF;
    t := hrm.roll_text(coalesce(p_row->>'phone', p_row->>'phone_no', p_row->>'phoneNo', p_row->>'phone_number'));
    IF t IS NOT NULL THEN v_vals := v_vals || jsonb_build_object('phone', t); END IF;

    v_vals := v_vals || jsonb_build_object('roll_as_given', p_row - 'sheet_row');

    RETURN jsonb_build_object(
        'row', v_row,
        'template', CASE WHEN v_new THEN 'ROLL' ELSE 'OLD' END,
        'junior', v_junior,
        'digits', nullif(v_digits, ''),
        'staff_number', CASE WHEN v_digits = '' THEN NULL WHEN v_junior THEN 'JP' || v_digits ELSE 'P' || v_digits END,
        'surname', v_surname, 'given_names', v_given,
        'department', hrm.roll_text(coalesce(p_row->>'department', p_row->>'dept', p_row->>'departmentName', p_row->>'department_code')),
        'faculty', hrm.roll_text(coalesce(p_row->>'faculty', p_row->>'fac_coll_dir', p_row->>'faculty_code')),
        'posting', hrm.roll_text(coalesce(p_row->>'posting', p_row->>'current_posting', p_row->>'unit', p_row->>'department',
                                          p_row->>'dept', p_row->>'department_or_unit')),
        -- the column the posting came from, as the sheet heads it: the roll's CURRENT POSTING, the old sheets' Unit or Department
        'posting_cell', CASE WHEN p_row ?| ARRAY['posting', 'current_posting'] THEN 'CURRENT POSTING' WHEN p_row ? 'unit' THEN 'Unit'
                             WHEN p_row ?| ARRAY['department', 'dept', 'department_or_unit'] THEN 'Department' ELSE 'CURRENT POSTING' END,
        'vals', v_vals,
        'unreadable', v_bad,
        'error', CASE WHEN v_digits = '' THEN 'no staff number (PNO or JP-NO) on the row' END);
END $$;
COMMENT ON FUNCTION hrm.roll_read(jsonb, text) IS
  'V750: one row of the nominal roll (first_name, middle_name, last_name, pno or jp_no, …) or of the old sheet (full_names, …) read for an upload — the staff number (JP + digits for a junior), the names, and what the record is to hold, only what the row gives; NULL for a blank line (every cell but the row and serial numbers blank) or a header. A name cell left blank or NA, or with no letter in it, or written as a query (hrm.roll_name_query), is left out and listed under unreadable {field first_name | middle_name | last_name, onRoll, reason BLANK | QUERY} (the old sheet''s Full Names written as a query: {field full_names, reason QUERY}, naming nobody); vals carries the roll''s readable first_name and middle_name, and names_held when a blank or query FIRST NAME or a query MIDDLE NAME holds the given names on record (hrm.roll_apply decides them against the record).';

-- ── 3 · one row against the person it names ─────────────────────────────────────────────────────────────────────────────────

-- the given names a FIRST NAME makes of those on record when the roll leaves the MIDDLE NAME blank — a blank cell erases nothing
-- (V750 b): a title before them (PROF., DR., TPL. …) is no given name; a first name already among them (case and punctuation
-- aside) leaves them as they are; any other replaces the first of them and keeps the rest
CREATE FUNCTION hrm.roll_given_first(p_held text, p_first text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_first text := hrm.roll_name_cell(p_first); v_rest text; v_have text[]; v_want text[]; v_after text; w text; v_keep text[] := '{}';
    v_parts text[]; v_carried text[] := '{}'; v_out text[] := '{}';
BEGIN
    IF v_first IS NULL THEN RETURN NULL; END IF;
    v_rest := hrm.roll_name_cell(p_held);
    IF v_rest IS NULL THEN RETURN v_first; END IF;
    -- the words on each side, case and punctuation aside (MARY-ANN is MARY and ANN, J.T. is J and T)
    v_have := hrm.roll_words(v_rest);
    v_want := hrm.roll_words(v_first);
    IF cardinality(v_want) = 0 OR v_want <@ v_have THEN RETURN v_rest; END IF;   -- every word already among them: they stand
    -- otherwise the roll's first name takes the place of the first of them (cut where a space, '.', ',', ';' or '/' ends it); the
    -- rest stand, and no word is written twice: a name kept whose words the first name already gives goes, and a word of the first
    -- name that a hyphened name kept carries (TERSOO-PETER carries PETER) is not written again beside it
    v_after := regexp_replace(v_rest, '^[^[:space:].,;/]+[.,;/]?[[:space:]]*', '');
    FOREACH w IN ARRAY regexp_split_to_array(btrim(v_after), '\s+') LOOP
        v_parts := hrm.roll_words(w);
        CONTINUE WHEN cardinality(v_parts) = 0 OR v_parts <@ v_want;
        v_keep := v_keep || w;
        v_carried := v_carried || v_parts;
    END LOOP;
    FOREACH w IN ARRAY regexp_split_to_array(v_first, '\s+') LOOP
        v_parts := hrm.roll_words(w);
        CONTINUE WHEN cardinality(v_parts) > 0 AND v_parts <@ v_carried;
        v_out := v_out || w;
    END LOOP;
    RETURN hrm.roll_text(array_to_string(v_out || v_keep, ' '));
END $$;
COMMENT ON FUNCTION hrm.roll_given_first(text, text) IS
  'V750: the given names a nominal-roll FIRST NAME makes of those on record when the MIDDLE NAME is blank — a title before them dropped (hrm.roll_untitled); the same names when every word of the first name is already among them (case and punctuation aside: ''JOHN TERSOO'', ''ADAKU NGOZI'', ''JOHN-CHIDI TERSOO'' stand for JOHN or NGOZI, ''TERSOO JOHN'' for ''JOHN TERSOO''); else the first name in place of the first of them, the rest kept and none repeated (''NGOZI ADAKU'' with NKECHI is ''NKECHI ADAKU'', ''J.T.'' with JOHN is ''JOHN T.'', ''JOHN TERSOO-PETER'' with ''MARK PETER'' is ''MARK TERSOO-PETER''). A blank cell erases no name, and no name is written twice (two hyphened names sharing a part both stand).';

-- who a staff number is on record as, one reading for both uploads and hrm.roll_absent: a JP number is a junior, non-teaching staff
-- (V750 a); otherwise teaching staff (ACADEMIC) when the live
-- employment's category — else the HR record's — says so, or a lecturer office is held today; non-teaching staff (NON_ACADEMIC)
-- when the category says so and no lecturer office is held; NULL when neither is known
CREATE FUNCTION hrm.roll_kind(p_person uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN upper(btrim(pe.staff_number)) ~ '^JP' THEN 'NON_ACADEMIC'          -- a junior is non-teaching staff (V750 a)
                WHEN coalesce(e.category, sr.category) = 'ACADEMIC'
                  OR EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p_person AND a.office_code = 'lecturer'
                                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)) THEN 'ACADEMIC'
                WHEN coalesce(e.category, sr.category) = 'NON_ACADEMIC' THEN 'NON_ACADEMIC' END
      FROM iam.person pe
      LEFT JOIN hrm.staff_record sr ON sr.person_id = p_person
      LEFT JOIN LATERAL (SELECT x.category FROM hrm.employment x WHERE x.person_id = p_person AND x.status <> 'ENDED'
                          ORDER BY x.appointment_date DESC NULLS LAST LIMIT 1) e ON true
     WHERE pe.id = p_person
$$;
COMMENT ON FUNCTION hrm.roll_kind(uuid) IS
  'V750: who a staff number is on record as, for the staff uploads and hrm.roll_absent alike — NON_ACADEMIC for a JP number (a junior, V750 a); else ACADEMIC when the live employment''s category (else the HR record''s) is ACADEMIC or a lecturer office is held today; NON_ACADEMIC when the category is NON_ACADEMIC and no lecturer office is held; NULL when neither is known.';

CREATE FUNCTION hrm.roll_apply(p_person uuid, p_staff_number text, p_vals jsonb, p_claimed jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    pe iam.person; sr hrm.staff_record; v_has boolean := false;
    v_old jsonb := '{}'::jsonb; v_new jsonb; v_person jsonb; k text; v_changes jsonb := '[]'::jsonb; v_kept jsonb := '[]'::jsonb;
    v_email text; v_phone text; v_set_email text; v_set_phone text; v_set_surname text; v_set_given text; v_given text; v_first text;
    v_pid uuid := p_person;
    c_fields CONSTANT text[] := ARRAY['pno', 'sex', 'date_of_birth', 'lga', 'state_of_origin', 'date_first_appointment',
                                      'date_of_confirmation', 'confirmation_note', 'date_of_last_promotion', 'promotion_note',
                                      'present_rank', 'category', 'cadre', 'salary_scale', 'contiss_step', 'conuass_step',
                                      'home_department', 'home_faculty', 'home_unit', 'unit_as_given'];
BEGIN
    IF p_person IS NOT NULL THEN
        SELECT * INTO pe FROM iam.person WHERE id = p_person;
        IF NOT FOUND THEN RAISE EXCEPTION 'no person %', p_person USING ERRCODE = '23514'; END IF;
        SELECT * INTO sr FROM hrm.staff_record WHERE person_id = p_person;
        v_has := FOUND;
        IF v_has THEN v_old := to_jsonb(sr); END IF;
    END IF;
    v_person := coalesce(to_jsonb(pe), '{}'::jsonb);
    v_new := v_old;

    -- the names follow the roll (case and spacing aside), and a blank, NA or query cell never erases one (V750 b; hrm.roll_read
    -- leaves such a cell out): the surname when the roll gives one; the given names when the roll gives both cells; with the
    -- MIDDLE NAME blank, the first name kept among them or put first in their place (hrm.roll_given_first: 'JOHN TERSOO' stands
    -- for JOHN, 'NGOZI ADAKU' is 'NKECHI ADAKU' for NKECHI); a blank or query FIRST NAME, or a query MIDDLE NAME
    -- (names_held), leaves them as they are. A new person takes what the roll gives, and needs a readable FIRST NAME; the old
    -- sheet's guess (given_names) only ever reaches a new person (V750 4)
    v_first := p_vals->>'first_name';
    v_given := CASE
        WHEN p_vals ? 'given_names' THEN p_vals->>'given_names'
        WHEN p_person IS NULL THEN hrm.roll_text(concat_ws(' ', v_first, p_vals->>'middle_name'))
        WHEN coalesce((p_vals->>'names_held')::boolean, false) OR v_first IS NULL THEN NULL
        WHEN p_vals->>'middle_name' IS NOT NULL THEN v_first || ' ' || (p_vals->>'middle_name')
        ELSE hrm.roll_given_first(pe.given_names, v_first) END;
    IF p_vals->>'surname' IS NOT NULL AND hrm.roll_key(v_person->>'surname') IS DISTINCT FROM hrm.roll_key(p_vals->>'surname') THEN
        v_changes := v_changes || jsonb_build_object('field', 'surname', 'from', v_person->>'surname', 'to', p_vals->>'surname');
        v_set_surname := p_vals->>'surname';
    END IF;
    IF v_given IS NOT NULL AND hrm.roll_key(v_person->>'given_names') IS DISTINCT FROM hrm.roll_key(v_given) THEN
        v_changes := v_changes || jsonb_build_object('field', 'given_names', 'from', v_person->>'given_names', 'to', v_given);
        v_set_given := v_given;
    END IF;

    -- the record follows the roll, field by field; a field the row does not give is left as it is
    FOREACH k IN ARRAY c_fields LOOP
        CONTINUE WHEN NOT p_vals ? k;
        IF hrm.roll_key(v_old->>k) IS DISTINCT FROM hrm.roll_key(p_vals->>k) THEN
            v_new := jsonb_set(v_new, ARRAY[k], p_vals->k);
            v_changes := v_changes || jsonb_build_object('field', k, 'from', hrm.roll_shown(k, v_old->>k), 'to', hrm.roll_shown(k, p_vals->>k));
        END IF;
    END LOOP;

    -- the e-mail: filled only where none is on record (V750 b) — never one another person holds, nor one this upload has given
    -- another row (V749 keeps an address to one person)
    IF p_vals->>'email' IS NOT NULL THEN
        v_email := lower(btrim(p_vals->>'email'));
        IF NOT platform.email_valid(v_email) THEN
            v_kept := v_kept || jsonb_build_object('field', 'email', 'onRecord', pe.email, 'onRoll', p_vals->>'email', 'reason', 'NOT_AN_EMAIL');
        ELSIF hrm.roll_text(pe.email) IS NOT NULL THEN
            IF lower(btrim(pe.email)) <> v_email THEN
                v_kept := v_kept || jsonb_build_object('field', 'email', 'onRecord', pe.email, 'onRoll', v_email, 'reason', 'DIFFERS');
            END IF;
        ELSIF coalesce(p_claimed, '{}'::jsonb) ? v_email THEN      -- given to another row of this upload (in a dry run as in the upload)
            v_kept := v_kept || jsonb_build_object('field', 'email', 'onRecord', pe.email, 'onRoll', v_email, 'reason', 'GIVEN_TO_ANOTHER_ROW',
                                                   'givenTo', p_claimed->>v_email);
        ELSIF EXISTS (SELECT 1 FROM iam.person x WHERE lower(btrim(x.email)) = v_email AND x.id IS DISTINCT FROM p_person) THEN
            v_kept := v_kept || jsonb_build_object('field', 'email', 'onRecord', pe.email, 'onRoll', v_email, 'reason', 'HELD_BY_ANOTHER');
        ELSE
            v_set_email := v_email;
            v_changes := v_changes || jsonb_build_object('field', 'email', 'from', pe.email, 'to', v_email);
        END IF;
    END IF;

    -- the phone: filled only where none is on record (V750 b); a record with digits in it has one, though it is not a number the
    -- portal can write to
    IF p_vals->>'phone' IS NOT NULL THEN
        v_phone := hrm.roll_phone(p_vals->>'phone');
        IF v_phone IS NULL THEN
            v_kept := v_kept || jsonb_build_object('field', 'phone', 'onRecord', pe.phone, 'onRoll', p_vals->>'phone', 'reason', 'NOT_A_PHONE');
        ELSIF pe.phone ~ '[0-9]' THEN
            IF hrm.roll_phone(pe.phone) IS DISTINCT FROM v_phone THEN
                v_kept := v_kept || jsonb_build_object('field', 'phone', 'onRecord', pe.phone, 'onRoll', p_vals->>'phone', 'reason', 'DIFFERS');
            END IF;
        ELSE
            v_set_phone := v_phone;
            v_changes := v_changes || jsonb_build_object('field', 'phone', 'from', pe.phone, 'to', v_phone);
        END IF;
    END IF;

    -- a new person needs both names — the roll's FIRST NAME readable, whatever the MIDDLE NAME holds
    IF p_person IS NULL AND v_set_surname IS NULL THEN
        RAISE EXCEPTION '%', CASE WHEN p_vals ? 'add_form' AND p_vals ? 'last_name_query'
                                  THEN 'the surname is a query (' || (p_vals->>'last_name_query') || '): correct it'
                                  WHEN p_vals ? 'add_form' THEN 'the surname holds no name'
                                  WHEN p_vals ? 'full_names_query'
                                  THEN 'the name (Full Names) is a query (' || (p_vals->>'full_names_query') || '): correct it and upload again'
                                  WHEN p_vals ? 'full_names_cell'
                                  THEN 'the name (Full Names) holds no name (' || (p_vals->>'full_names_cell') || '): fill it in and upload again'
                                  WHEN p_vals ? 'full_names_blank'
                                  THEN 'the name (Full Names) is blank: fill it in and upload again'
                                  WHEN p_vals ? 'last_name_cell'
                                  THEN 'the surname (LAST-SURNAME) holds no name (' || (p_vals->>'last_name_cell') || '): fill it in and upload again'
                                  WHEN p_vals ? 'last_name_query'
                                  THEN 'the surname (LAST-SURNAME) is a query (' || (p_vals->>'last_name_query') || '): correct it and upload again'
                                  ELSE 'the surname (LAST-SURNAME) is blank' END USING ERRCODE = '23514';
    END IF;
    IF p_person IS NULL AND (v_set_given IS NULL OR (NOT p_vals ? 'given_names' AND v_first IS NULL)) THEN
        RAISE EXCEPTION '%', CASE WHEN p_vals ? 'add_form' AND p_vals ? 'first_name_query'
                                  THEN 'the given names are a query (' || (p_vals->>'first_name_query') || '): correct them'
                                  WHEN p_vals ? 'add_form' THEN 'the given names hold no name'
                                  WHEN p_vals ? 'first_name_cell'
                                  THEN 'the first name (FIRST NAME) holds no name (' || (p_vals->>'first_name_cell') || '): fill it in and upload again'
                                  WHEN p_vals ? 'first_name_query'
                                  THEN 'the first name is a query (' || (p_vals->>'first_name_query') || '): correct it and upload again'
                                  ELSE 'the first name is blank' END USING ERRCODE = '23514';
    END IF;

    IF jsonb_array_length(v_changes) = 0 THEN
        RETURN jsonb_build_object('person', p_person, 'changes', v_changes, 'kept', v_kept);
    END IF;

    -- written: the person, then the record (only the columns the roll speaks to; anything else on the record stands)
    IF v_pid IS NULL THEN
        v_pid := gen_random_uuid();
        INSERT INTO iam.person (id, staff_number, surname, given_names, email, phone)
        VALUES (v_pid, p_staff_number, v_set_surname, v_set_given, v_set_email, v_set_phone);
    ELSIF v_set_surname IS NOT NULL OR v_set_given IS NOT NULL OR v_set_email IS NOT NULL OR v_set_phone IS NOT NULL THEN
        UPDATE iam.person
           SET surname = coalesce(v_set_surname, surname), given_names = coalesce(v_set_given, given_names),
               email = coalesce(v_set_email, email), phone = coalesce(v_set_phone, phone)
         WHERE id = v_pid;
    END IF;

    v_new := v_new || jsonb_build_object('person_id', v_pid, 'roll_as_given', p_vals->'roll_as_given', 'roll_updated_at', now(), 'updated_at', now());
    IF v_has THEN
        UPDATE hrm.staff_record s
           SET (pno, sex, date_of_birth, lga, state_of_origin, date_first_appointment, date_of_confirmation, confirmation_note,
                date_of_last_promotion, promotion_note, present_rank, category, cadre, salary_scale, contiss_step, conuass_step,
                home_department, home_faculty, home_unit, unit_as_given, roll_as_given, roll_updated_at, updated_at)
             = (x.pno, x.sex, x.date_of_birth, x.lga, x.state_of_origin, x.date_first_appointment, x.date_of_confirmation, x.confirmation_note,
                x.date_of_last_promotion, x.promotion_note, x.present_rank, x.category, x.cadre, x.salary_scale, x.contiss_step, x.conuass_step,
                x.home_department, x.home_faculty, x.home_unit, x.unit_as_given, x.roll_as_given, x.roll_updated_at, x.updated_at)
          FROM jsonb_populate_record(NULL::hrm.staff_record, v_new) x
         WHERE s.person_id = v_pid;
    ELSE
        INSERT INTO hrm.staff_record (person_id, pno, sex, date_of_birth, lga, state_of_origin, date_first_appointment, date_of_confirmation,
                                      confirmation_note, date_of_last_promotion, promotion_note, present_rank, category, cadre, salary_scale,
                                      contiss_step, conuass_step, home_department, home_faculty, home_unit, unit_as_given, roll_as_given,
                                      roll_updated_at, updated_at)
        SELECT x.person_id, x.pno, x.sex, x.date_of_birth, x.lga, x.state_of_origin, x.date_first_appointment, x.date_of_confirmation,
               x.confirmation_note, x.date_of_last_promotion, x.promotion_note, x.present_rank, x.category, x.cadre, x.salary_scale,
               x.contiss_step, x.conuass_step, x.home_department, x.home_faculty, x.home_unit, x.unit_as_given, x.roll_as_given,
               x.roll_updated_at, x.updated_at
          FROM jsonb_populate_record(NULL::hrm.staff_record, v_new) x;
    END IF;

    RETURN jsonb_build_object('person', v_pid, 'changes', v_changes, 'kept', v_kept);
END $$;
COMMENT ON FUNCTION hrm.roll_apply(uuid, text, jsonb, jsonb) IS
  'V750: one nominal-roll row against the person it names (NULL: a new person under the staff number) — every value the row gives that differs (case and spacing aside) is written and listed {field, from, to}; a blank, NA or query name cell never erases a name (the surname only when the roll gives one; the given names when the roll gives both cells, or with the middle name blank as hrm.roll_given_first makes them — the first name kept among them or put first in their place — never on a blank or query first name or a query middle name; a new person needs a readable surname and first name); the e-mail and phone filled only where none is on record (never an e-mail another person holds or p_claimed lists as given to another row of the same upload), else listed as kept {field, onRecord, onRoll, reason DIFFERS | NOT_AN_EMAIL | NOT_A_PHONE | HELD_BY_ANOTHER | GIVEN_TO_ANOTHER_ROW (givenTo: that row''s staff number)}; nothing written when nothing differs (an upload''s dry run writes the row and rolls it back). Never a sign-in, an office, an employment, a photograph or a blood group.';

-- ── 4 · the two uploads ─────────────────────────────────────────────────────────────────────────────────────────────────────

-- iam.import_staff (V253, V744): the non-teaching staff — senior (P + PNO) and junior (JP + JP-NO)
DROP FUNCTION iam.import_staff(jsonb, boolean);
CREATE FUNCTION iam.import_staff(p_rows jsonb, p_dry_run boolean DEFAULT false, p_claimed jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (rows integer, created integer, existing integer, records integer, unplaced integer, skipped integer, first_error text,
               unplaced_units text, updated integer, unchanged integer, errors integer, results jsonb)
LANGUAGE plpgsql AS $function$
DECLARE
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    r jsonb; i int; v jsonb; v_vals jsonb; v_out jsonb; v_unres jsonb; v_chg jsonb;
    v_row int; v_staff text; v_pid uuid; v_ended date; v_action text; v_msg text; v_unitin text; v_unit text; v_dept text; v_fac text;
    v_recname text; v_name text; v_rep boolean; v_resname text; v_named jsonb := '{}'::jsonb;
    v_seen jsonb := '{}'::jsonb; v_places jsonb := '{}'::jsonb; v_list jsonb[] := '{}';
    -- the e-mail addresses given to rows of this upload: those the earlier requests gave (the screen sends them), then this one's
    v_claimed jsonb := coalesce((SELECT jsonb_object_agg(lower(btrim(e.key)), e.value) FROM jsonb_each(
                          CASE WHEN jsonb_typeof(p_claimed) = 'object' THEN p_claimed ELSE '{}'::jsonb END) e
                        WHERE btrim(e.key) <> ''), '{}'::jsonb);
    n int := 0; c_created int := 0; c_exist int := 0; c_rec int := 0; c_unplaced int := 0; c_skip int := 0;
    c_updated int := 0; c_unchanged int := 0; c_errors int := 0; v_err text := NULL; v_missing text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'staff are loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows of the nominal roll: first name, middle name, last name (surname), PNO or JP-NO, sex, date of birth, e-mail, phone, LGA, state, first appointment, confirmation, last promotion, present rank, current posting' USING ERRCODE = '23514';
    END IF;

    FOR r, i IN SELECT x.e, x.o::int FROM jsonb_array_elements(p_rows) WITH ORDINALITY x(e, o) LOOP
        v := hrm.roll_read(r, 'NON_ACADEMIC');
        CONTINUE WHEN v IS NULL;                              -- a blank line or a header
        n := n + 1;
        v_row := coalesce((v->>'row')::int, i);
        v_staff := v->>'staff_number';
        v_pid := NULL; v_ended := NULL; v_out := NULL; v_action := NULL; v_msg := v->>'error'; v_recname := NULL; v_name := NULL; v_rep := false;
        v_unres := coalesce(v->'unreadable', '[]'::jsonb);
        IF v_msg IS NULL AND v_seen ? upper(v_staff) THEN
            v_msg := v_staff || ' is on this upload already, at row ' || (v_seen->>upper(v_staff));
            v_rep := true;
        END IF;

        IF v_msg IS NOT NULL THEN
            v_action := 'ERROR';
        ELSE
            v_seen := v_seen || jsonb_build_object(upper(v_staff), v_row);
            SELECT p.id, p.ended_on, concat_ws(', ', p.surname, p.given_names) INTO v_pid, v_ended, v_recname
              FROM iam.person p WHERE upper(p.staff_number) = upper(v_staff);   -- V744: whatever its case
            IF v_pid IS NOT NULL THEN c_exist := c_exist + 1; END IF;

            -- the non-teaching roll never moves a lecturer onto the non-teaching staff: a number on record as teaching staff (the
            -- register's category, or a lecturer office today) is theirs, and the row writes nothing
            IF v_pid IS NOT NULL AND hrm.roll_kind(v_pid) = 'ACADEMIC' THEN
                v_action := 'ERROR';
                v_msg := v_staff || ' is on record as teaching staff: they are loaded on the teaching staff desk';
            END IF;
        END IF;

        IF v_action IS NULL THEN
            v_vals := (v->'vals') || jsonb_build_object('pno', v->>'digits', 'category', 'NON_ACADEMIC',
                                                         'cadre', CASE WHEN (v->>'junior')::boolean THEN 'JUNIOR' ELSE 'SENIOR' END);
            IF v_pid IS NOT NULL AND v->>'template' = 'OLD' THEN
                v_vals := v_vals - 'surname' - 'given_names';   -- the old sheet's one cell of names is a guess at the surname: it renames nobody
            END IF;

            -- the posting: placed in its unit, department or faculty (ref.resolve_unit, V253), else as the roll writes it — one
            -- place alone answering it (hrm.roll_place)
            v_unitin := v->>'posting';
            v_unit := NULL; v_dept := NULL; v_fac := NULL;
            IF v_unitin IS NOT NULL THEN
                SELECT u.unit_code, u.dept_code, u.faculty_code INTO v_unit, v_dept, v_fac FROM ref.resolve_unit(v_unitin) u LIMIT 1;
                IF v_unit IS NULL AND v_dept IS NULL AND v_fac IS NULL THEN
                    IF NOT v_places ? v_unitin THEN      -- read once an upload: a posting repeats down a roll
                        v_places := v_places || jsonb_build_object(v_unitin, (SELECT to_jsonb(pl) FROM hrm.roll_place(v_unitin, 'POSTING') pl));
                    END IF;
                    v_unit := v_places->v_unitin->>'unit_code';
                    v_dept := v_places->v_unitin->>'dept_code';
                    v_fac := v_places->v_unitin->>'faculty_code';
                END IF;
            END IF;
            IF v_unit IS NOT NULL OR v_dept IS NOT NULL OR v_fac IS NOT NULL THEN
                v_vals := v_vals || jsonb_build_object('home_unit', v_unit, 'home_department', v_dept, 'home_faculty', v_fac, 'unit_as_given', v_unitin);
            ELSE
                c_unplaced := c_unplaced + 1;
                IF v_unitin IS NOT NULL AND NOT (upper(v_unitin) = ANY(SELECT upper(x) FROM unnest(v_missing) x)) THEN v_missing := v_missing || v_unitin; END IF;
                v_unres := v_unres || jsonb_build_object('field', 'posting', 'onRoll', v_unitin);
                IF v_pid IS NULL THEN
                    v_action := 'SKIPPED';      -- a new member of staff is placed in their posting, or not loaded
                    v_msg := CASE WHEN v_unitin IS NULL
                                  THEN 'the ' || coalesce(v->>'posting_cell', 'CURRENT POSTING')
                                       || ' cell is blank: a new member of staff is placed in their posting — fill it in and upload again'
                                  ELSE 'no unit, department or faculty matching ' || v_unitin || ' is on the portal: ask ICT to add it or its spelling (or correct the '
                                       || coalesce(v->>'posting_cell', 'CURRENT POSTING') || ' cell) and upload again' END;
                END IF;
            END IF;

            -- the row written in its own savepoint; a dry run writes it the same way and rolls it back, so it meets every rule the
            -- upload would
            IF v_action IS NULL THEN
                BEGIN
                    v_out := hrm.roll_apply(v_pid, v_staff, v_vals, v_claimed);
                    v_action := CASE WHEN v_pid IS NULL THEN 'CREATED' WHEN jsonb_array_length(v_out->'changes') > 0 THEN 'UPDATED' ELSE 'UNCHANGED' END;
                    IF v_pid IS NOT NULL THEN      -- the name the record holds once the row is written (a dry run reads it before undoing it)
                        SELECT concat_ws(', ', p.surname, p.given_names) INTO v_name FROM iam.person p WHERE p.id = v_pid;
                    END IF;
                    IF p_dry_run THEN RAISE EXCEPTION 'V750: a dry run undoes its row'; END IF;
                    v_pid := coalesce(v_pid, (v_out->>'person')::uuid);
                EXCEPTION
                    WHEN raise_exception THEN
                        IF SQLERRM <> 'V750: a dry run undoes its row' THEN v_action := 'ERROR'; v_msg := SQLERRM; v_out := NULL; v_name := NULL; END IF;
                    WHEN OTHERS THEN
                        v_action := 'ERROR'; v_msg := SQLERRM; v_out := NULL; v_name := NULL;
                END;
                FOR v_chg IN SELECT c FROM jsonb_array_elements(v_out->'changes') c WHERE c->>'field' = 'email' LOOP
                    v_claimed := v_claimed || jsonb_build_object(v_chg->>'to', v_staff);
                END LOOP;
            END IF;
        END IF;

        CASE v_action
            WHEN 'CREATED' THEN c_created := c_created + 1; c_rec := c_rec + 1;
            WHEN 'UPDATED' THEN c_updated := c_updated + 1; c_rec := c_rec + 1;
            WHEN 'UNCHANGED' THEN c_unchanged := c_unchanged + 1; c_rec := c_rec + 1;
            WHEN 'SKIPPED' THEN c_skip := c_skip + 1;
            ELSE c_errors := c_errors + 1;
        END CASE;
        IF v_action IN ('SKIPPED', 'ERROR') AND v_err IS NULL THEN
            v_err := 'Row ' || v_row || coalesce(' (' || v_staff || ')', '') || ': ' || v_msg;
        END IF;
        -- a name cell left blank is reported only against a record it leaves standing (a new person's blank names are its error)
        IF v_pid IS NULL OR v_action = 'CREATED' THEN
            v_unres := coalesce((SELECT jsonb_agg(u ORDER BY o) FROM jsonb_array_elements(v_unres) WITH ORDINALITY x(u, o)
                                  WHERE u->>'reason' IS DISTINCT FROM 'BLANK'), '[]'::jsonb);
        END IF;
        -- the name: as the record holds it for someone on record (the old sheet's guess renames nobody), else as the row gives it; a
        -- number given twice is named as its first row named them, so a dry run and the upload say the same
        v_resname := CASE WHEN v_rep THEN v_named->>upper(v_staff)
                          WHEN v_name IS NOT NULL THEN v_name
                          WHEN v_recname IS NOT NULL AND v->>'template' = 'OLD' THEN v_recname
                          ELSE coalesce(nullif(concat_ws(', ', v->>'surname', v->>'given_names'), ''), v->'vals'->>'full_names_query') END;
        IF NOT v_rep AND v_staff IS NOT NULL THEN v_named := v_named || jsonb_build_object(upper(v_staff), v_resname); END IF;
        v_list := array_append(v_list, jsonb_build_object(
            'row', v_row, 'staffNumber', v_staff,
            'name', v_resname,
            'action', v_action,
            'cadre', CASE WHEN (v->>'junior')::boolean THEN 'JUNIOR' ELSE 'SENIOR' END, 'personId', v_pid,
            'changes', coalesce(v_out->'changes', '[]'::jsonb), 'kept', coalesce(v_out->'kept', '[]'::jsonb),
            'unresolved', v_unres, 'endedOn', v_ended, 'error', v_msg));
    END LOOP;

    RETURN QUERY SELECT n, c_created, c_exist, c_rec, c_unplaced, c_skip, v_err, nullif(array_to_string(v_missing, ', '), ''),
                        c_updated, c_unchanged, c_errors, to_jsonb(v_list);
END $function$;
COMMENT ON FUNCTION iam.import_staff(jsonb, boolean, jsonb) IS
  'Loads the non-teaching staff from the nominal roll (V253; V750: the roll''s columns — first, middle and last name, PNO or JP-NO, sex, date of birth, e-mail, phone, LGA, state, first appointment, confirmation, last promotion, present rank, current posting — or the old sheet''s). A junior (JP-NO) is JP + digits, a senior P + digits; found by the number whatever its case (V744), never by name. A new person: person and establishment record placed in the posting''s unit, department or faculty, no sign-in, no office (SKIPPED when the posting resolves to no unit, department or faculty — by ref.resolve_unit or, as the roll writes it, hrm.roll_place — its message saying to ask ICT to add the place or its spelling, or correct the cell, and upload again). Someone on record: what the roll gives follows the roll, the e-mail and phone only filled, a blank, NA or query name cell erasing no name, the posting left when it does not resolve; someone on record as teaching staff (hrm.roll_kind: the live employment''s or HR record''s category ACADEMIC, or a lecturer office today) is an ERROR that writes nothing ("P123 is on record as teaching staff: they are loaded on the teaching staff desk"). Per-row savepoints; a dry run writes each row and rolls it back, leaving nothing; p_claimed the e-mail addresses earlier requests of the same upload gave ({address: staff number}), kept from this one''s rows; returns the counts and each row''s result {row, staffNumber, name, action CREATED|UPDATED|UNCHANGED|SKIPPED|ERROR, cadre, personId, changes, kept, unresolved, endedOn, error}.';

-- iam.import_lecturers (V137, V428, V744): the teaching staff — P + PNO, home department and faculty
DROP FUNCTION iam.import_lecturers(jsonb);
CREATE FUNCTION iam.import_lecturers(p_rows jsonb, p_dry_run boolean DEFAULT false, p_claimed jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (rows integer, created integer, existing integer, credentialed integer, granted integer, records integer, no_department integer,
               skipped integer, first_error text, missing_departments text, updated integer, unchanged integer, errors integer, results jsonb)
LANGUAGE plpgsql AS $function$
DECLARE
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    r jsonb; i int; v jsonb; v_vals jsonb; v_out jsonb; v_unres jsonb; v_chg jsonb;
    v_row int; v_staff text; v_pid uuid; v_made uuid; v_cred boolean; v_ended date; v_action text; v_msg text;
    v_deptin text; v_dept text; v_facin text; v_fac text; v_date date; v_recname text; v_name text; v_office_from text;
    v_rep boolean; v_resname text; v_named jsonb := '{}'::jsonb;
    v_seen jsonb := '{}'::jsonb; v_places jsonb := '{}'::jsonb; v_list jsonb[] := '{}';
    -- the e-mail addresses given to rows of this upload: those the earlier requests gave (the screen sends them), then this one's
    v_claimed jsonb := coalesce((SELECT jsonb_object_agg(lower(btrim(e.key)), e.value) FROM jsonb_each(
                          CASE WHEN jsonb_typeof(p_claimed) = 'object' THEN p_claimed ELSE '{}'::jsonb END) e
                        WHERE btrim(e.key) <> ''), '{}'::jsonb);
    n int := 0; c_created int := 0; c_exist int := 0; c_cred int := 0; c_grant int := 0; c_rec int := 0; c_nodept int := 0; c_skip int := 0;
    c_updated int := 0; c_unchanged int := 0; c_errors int := 0; v_err text := NULL; v_missing text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'lecturers are loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows of the nominal roll: first name, middle name, last name (surname), PNO, sex, date of birth, e-mail, phone, LGA, state, first appointment, confirmation, last promotion, present rank, department, faculty' USING ERRCODE = '23514';
    END IF;

    FOR r, i IN SELECT x.e, x.o::int FROM jsonb_array_elements(p_rows) WITH ORDINALITY x(e, o) LOOP
        v := hrm.roll_read(r, 'ACADEMIC');
        CONTINUE WHEN v IS NULL;                              -- a blank line or a header
        n := n + 1;
        v_row := coalesce((v->>'row')::int, i);
        v_staff := v->>'staff_number';
        v_pid := NULL; v_ended := NULL; v_out := NULL; v_action := NULL; v_msg := v->>'error'; v_recname := NULL; v_name := NULL; v_rep := false;
        v_unres := coalesce(v->'unreadable', '[]'::jsonb);
        IF v_msg IS NULL AND (v->>'junior')::boolean THEN
            v_msg := v_staff || ' is a junior staff number (JP-NO): junior staff are loaded on the non-academic staff desk';
        END IF;
        IF v_msg IS NULL AND v_seen ? upper(v_staff) THEN
            v_msg := v_staff || ' is on this upload already, at row ' || (v_seen->>upper(v_staff));
            v_rep := true;
        END IF;

        IF v_msg IS NOT NULL THEN
            v_action := 'ERROR';
        ELSE
            v_seen := v_seen || jsonb_build_object(upper(v_staff), v_row);
            SELECT p.id, p.ended_on, concat_ws(', ', p.surname, p.given_names) INTO v_pid, v_ended, v_recname
              FROM iam.person p WHERE upper(p.staff_number) = upper(v_staff);   -- V744: whatever its case
            IF v_pid IS NOT NULL THEN c_exist := c_exist + 1; END IF;

            -- the teaching-staff roll never moves a member of the non-teaching staff onto it: a number on record as non-teaching staff
            -- (hrm.roll_kind: that category and no lecturer office today) is theirs, and the row writes nothing
            IF v_pid IS NOT NULL AND hrm.roll_kind(v_pid) = 'NON_ACADEMIC' THEN
                v_action := 'ERROR';
                v_msg := v_staff || ' is on record as non-teaching staff: they are loaded on the non-academic staff desk';
            END IF;
        END IF;

        IF v_action IS NULL THEN
            v_vals := (v->'vals') || jsonb_build_object('pno', v->>'digits', 'category', 'ACADEMIC', 'cadre', NULL);
            IF v_pid IS NOT NULL AND v->>'template' = 'OLD' THEN
                v_vals := v_vals - 'surname' - 'given_names';   -- the old sheet's one cell of names is a guess at the surname: it renames nobody
            END IF;

            -- the department: by code, or by name tolerant of case, spacing and & (V137), else as the unit register reads it (V253),
            -- else as the roll writes it — one department alone answering it (hrm.roll_place)
            v_deptin := v->>'department';
            v_dept := NULL;
            IF v_deptin IS NOT NULL THEN
                SELECT d.code INTO v_dept FROM ref.department d
                 WHERE d.ended_on IS NULL
                   AND ( upper(d.code) = upper(v_deptin)
                      OR regexp_replace(replace(upper(d.name), '&', 'AND'), '[^A-Z0-9]', '', 'g')
                       = regexp_replace(replace(upper(v_deptin), '&', 'AND'), '[^A-Z0-9]', '', 'g') )
                 ORDER BY d.code LIMIT 1;
                IF v_dept IS NULL THEN
                    SELECT u.dept_code INTO v_dept FROM ref.resolve_unit(v_deptin) u WHERE u.dept_code IS NOT NULL LIMIT 1;
                END IF;
                IF v_dept IS NULL THEN
                    IF NOT v_places ? ('D:' || v_deptin) THEN      -- read once an upload: a department repeats down a roll
                        v_places := v_places || jsonb_build_object('D:' || v_deptin, (SELECT pl.dept_code FROM hrm.roll_place(v_deptin, 'DEPARTMENT') pl));
                    END IF;
                    v_dept := v_places->>('D:' || v_deptin);
                END IF;
            END IF;
            IF v_dept IS NOT NULL THEN
                v_vals := v_vals || jsonb_build_object('home_department', v_dept, 'home_unit', NULL);
            ELSE
                c_nodept := c_nodept + 1;
                IF v_deptin IS NOT NULL AND NOT (upper(v_deptin) = ANY(SELECT upper(x) FROM unnest(v_missing) x)) THEN v_missing := v_missing || v_deptin; END IF;
                v_unres := v_unres || jsonb_build_object('field', 'department', 'onRoll', v_deptin);
                IF v_pid IS NULL THEN
                    v_action := 'SKIPPED';      -- a new lecturer's office is made in the home department: none, no lecturer
                    v_msg := CASE WHEN v_deptin IS NULL
                                  THEN 'the DEPARTMENT cell is blank: a new lecturer is given the lecturer office in their department — fill it in and upload again'
                                  ELSE 'no department matching ' || v_deptin || ' is on the portal: ask ICT to add the department (or correct the DEPARTMENT cell) '
                                       || 'and upload again — a new lecturer is given the lecturer office in their department' END;
                END IF;
            END IF;

            -- the faculty, college or directorate: by code or name (a bracketed code read too, "BASIC MEDICAL SCIENCES (BAMS)"), else as
            -- the unit register reads it
            v_facin := v->>'faculty';
            v_fac := NULL;
            IF v_facin IS NOT NULL THEN
                SELECT f.code INTO v_fac FROM ref.faculty f
                 WHERE upper(f.code) = upper(v_facin)
                    OR upper(f.code) = upper(substring(v_facin FROM '\(\s*([A-Za-z]+)\s*\)'))
                    OR ref.unit_key(f.name) = ref.unit_key(regexp_replace(v_facin, '\s*\([^)]*\)\s*', ' ', 'g'))
                    OR ref.unit_key(f.name) = regexp_replace(ref.unit_key(v_facin), '^(FACULTYOF|COLLEGEOF)', '')
                 ORDER BY f.code LIMIT 1;
                IF v_fac IS NULL THEN
                    SELECT u.faculty_code INTO v_fac FROM ref.resolve_unit(v_facin) u WHERE u.faculty_code IS NOT NULL LIMIT 1;
                END IF;
                IF v_fac IS NULL THEN
                    IF NOT v_places ? ('F:' || v_facin) THEN
                        v_places := v_places || jsonb_build_object('F:' || v_facin, (SELECT pl.faculty_code FROM hrm.roll_place(v_facin, 'FACULTY') pl));
                    END IF;
                    v_fac := v_places->>('F:' || v_facin);
                END IF;
                IF v_fac IS NOT NULL THEN
                    v_vals := v_vals || jsonb_build_object('home_faculty', v_fac);
                ELSE
                    v_unres := v_unres || jsonb_build_object('field', 'faculty', 'onRoll', v_facin);
                END IF;
            END IF;

            -- the row written in its own savepoint; a dry run writes it the same way and rolls it back, so it meets every rule the
            -- upload would
            IF v_action IS NULL THEN
                v_made := NULL; v_cred := false;
                BEGIN
                    v_out := hrm.roll_apply(v_pid, v_staff, v_vals, v_claimed);
                    IF v_pid IS NULL THEN
                        v_action := 'CREATED';
                        v_made := (v_out->>'person')::uuid;
                        v_date := (v_vals->>'date_first_appointment')::date;
                        -- the sign-in: the username the staff number; the stored password random, the staff id opening the account until a password is chosen, the change forced at sign-in (V428). A username is
                        -- three characters at least (V017): a number shorter (P6) is loaded and placed, and its sign-in reported as not made
                        IF length(v_staff) >= 3 THEN
                            INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by)
                            VALUES (v_made, lower(v_staff), crypt(gen_random_uuid()::text || gen_random_uuid()::text, gen_salt('bf', 12)), true, v_actor);
                            INSERT INTO iam.credential_event (id, person_id, kind, by_person, note)
                            VALUES (gen_random_uuid(), v_made, 'SET', v_actor, 'Bulk teaching-staff upload');
                            v_cred := true;
                        ELSE
                            v_out := jsonb_set(v_out, '{kept}', (v_out->'kept') || jsonb_build_array(jsonb_build_object(
                                         'field', 'sign_in', 'onRecord', NULL, 'onRoll', lower(v_staff), 'reason', 'USERNAME_TOO_SHORT')));
                        END IF;
                        -- the lecturer office, scoped to the home department
                        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                        VALUES (gen_random_uuid(), v_made, 'lecturer', 'department', v_dept,
                                'Teaching-staff upload (Users & roles)', v_actor, coalesce(v_date, current_date));
                    ELSE
                        -- a home department the roll changes takes the lecturer office with it, as the Edit form moves it
                        -- (iam.update_lecturer, V140): the lecturer office still open in another department ends today and one opens in
                        -- the new department; no other office is touched (a head of department's stays where it is)
                        IF v_dept IS NOT NULL AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_out->'changes') c WHERE c->>'field' = 'home_department') THEN
                            SELECT string_agg(coalesce(d.name, a.scope_id), ', ' ORDER BY a.scope_id) INTO v_office_from
                              FROM iam.office_assignment a LEFT JOIN ref.department d ON d.code = a.scope_id
                             WHERE a.person_id = v_pid AND a.office_code = 'lecturer' AND a.scope_kind = 'department'
                               AND a.scope_id IS DISTINCT FROM v_dept AND a.valid_to IS NULL;
                            IF v_office_from IS NOT NULL THEN
                                UPDATE iam.office_assignment SET valid_to = current_date
                                 WHERE person_id = v_pid AND office_code = 'lecturer' AND scope_kind = 'department'
                                   AND scope_id IS DISTINCT FROM v_dept AND valid_to IS NULL;
                                IF NOT EXISTS (SELECT 1 FROM iam.office_assignment
                                                WHERE person_id = v_pid AND office_code = 'lecturer' AND scope_kind = 'department'
                                                  AND scope_id = v_dept AND valid_to IS NULL) THEN
                                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                                    VALUES (gen_random_uuid(), v_pid, 'lecturer', 'department', v_dept,
                                            'Teaching-staff upload (Users & roles)', v_actor, current_date);
                                END IF;
                                v_out := jsonb_set(v_out, '{changes}', (v_out->'changes') || jsonb_build_array(jsonb_build_object(
                                             'field', 'lecturer_office', 'from', v_office_from, 'to', hrm.roll_shown('home_department', v_dept))));
                            END IF;
                        END IF;
                        v_action := CASE WHEN jsonb_array_length(v_out->'changes') > 0 THEN 'UPDATED' ELSE 'UNCHANGED' END;
                        -- the name the record holds once the row is written (a dry run reads it before undoing it)
                        SELECT concat_ws(', ', p.surname, p.given_names) INTO v_name FROM iam.person p WHERE p.id = v_pid;
                    END IF;
                    IF p_dry_run THEN RAISE EXCEPTION 'V750: a dry run undoes its row'; END IF;
                    v_pid := coalesce(v_pid, v_made);
                EXCEPTION
                    WHEN raise_exception THEN
                        IF SQLERRM <> 'V750: a dry run undoes its row' THEN v_action := 'ERROR'; v_msg := SQLERRM; v_out := NULL; v_name := NULL; END IF;
                    WHEN OTHERS THEN
                        v_action := 'ERROR'; v_msg := SQLERRM; v_out := NULL; v_name := NULL;
                END;
                IF v_action = 'CREATED' THEN
                    c_grant := c_grant + 1;
                    IF v_cred THEN c_cred := c_cred + 1; END IF;
                END IF;
                FOR v_chg IN SELECT c FROM jsonb_array_elements(v_out->'changes') c WHERE c->>'field' = 'email' LOOP
                    v_claimed := v_claimed || jsonb_build_object(v_chg->>'to', v_staff);
                END LOOP;
            END IF;
        END IF;

        CASE v_action
            WHEN 'CREATED' THEN c_created := c_created + 1; c_rec := c_rec + 1;
            WHEN 'UPDATED' THEN c_updated := c_updated + 1; c_rec := c_rec + 1;
            WHEN 'UNCHANGED' THEN c_unchanged := c_unchanged + 1; c_rec := c_rec + 1;
            WHEN 'SKIPPED' THEN c_skip := c_skip + 1;
            ELSE c_errors := c_errors + 1;
        END CASE;
        IF v_action IN ('SKIPPED', 'ERROR') AND v_err IS NULL THEN
            v_err := 'Row ' || v_row || coalesce(' (' || v_staff || ')', '') || ': ' || v_msg;
        END IF;
        -- a name cell left blank is reported only against a record it leaves standing (a new person's blank names are its error)
        IF v_pid IS NULL OR v_action = 'CREATED' THEN
            v_unres := coalesce((SELECT jsonb_agg(u ORDER BY o) FROM jsonb_array_elements(v_unres) WITH ORDINALITY x(u, o)
                                  WHERE u->>'reason' IS DISTINCT FROM 'BLANK'), '[]'::jsonb);
        END IF;
        -- the name: as the record holds it for someone on record (the old sheet's guess renames nobody), else as the row gives it; a
        -- number given twice is named as its first row named them, so a dry run and the upload say the same
        v_resname := CASE WHEN v_rep THEN v_named->>upper(v_staff)
                          WHEN v_name IS NOT NULL THEN v_name
                          WHEN v_recname IS NOT NULL AND v->>'template' = 'OLD' THEN v_recname
                          ELSE coalesce(nullif(concat_ws(', ', v->>'surname', v->>'given_names'), ''), v->'vals'->>'full_names_query') END;
        IF NOT v_rep AND v_staff IS NOT NULL THEN v_named := v_named || jsonb_build_object(upper(v_staff), v_resname); END IF;
        v_list := array_append(v_list, jsonb_build_object(
            'row', v_row, 'staffNumber', v_staff,
            'name', v_resname,
            'action', v_action,
            'cadre', NULL, 'personId', v_pid,
            'changes', coalesce(v_out->'changes', '[]'::jsonb), 'kept', coalesce(v_out->'kept', '[]'::jsonb),
            'unresolved', v_unres, 'endedOn', v_ended, 'error', v_msg));
    END LOOP;

    RETURN QUERY SELECT n, c_created, c_exist, c_cred, c_grant, c_rec, c_nodept, c_skip, v_err, nullif(array_to_string(v_missing, ', '), ''),
                        c_updated, c_unchanged, c_errors, to_jsonb(v_list);
END $function$;
COMMENT ON FUNCTION iam.import_lecturers(jsonb, boolean, jsonb) IS
  'Loads the teaching staff from the nominal roll (V137, V428; V750: the roll''s columns — first, middle and last name, PNO, sex, date of birth, e-mail, phone, LGA, state, first appointment, confirmation, last promotion, present rank, department, faculty — or the old sheet''s). P + PNO, found by the number whatever its case (V744), never by name. A new person: person, sign-in (the username the staff number; the stored password random, the staff id opening the account until a password is chosen, the change forced at sign-in — V428; none for a number under three characters, kept as {field sign_in, reason USERNAME_TOO_SHORT}), the lecturer office in the home department and the establishment record (SKIPPED when no department answers the DEPARTMENT cell — by code, name, ref.resolve_unit or, as the roll writes it, hrm.roll_place — its message saying to ask ICT to add the department, or correct the cell, and upload again). Someone on record: what the roll gives follows the roll, the e-mail and phone only filled, a blank, NA or query name cell erasing no name, the department left when it does not resolve; never a sign-in, and no office but this one: a home department the roll changes moves the lecturer office still open in another department to the new one, as the Edit form does (iam.update_lecturer) — listed as the change {field lecturer_office, from, to} (the departments'' names). Someone on record as non-teaching staff (hrm.roll_kind NON_ACADEMIC: that category and no lecturer office) is an ERROR that writes nothing ("P123 is on record as non-teaching staff: they are loaded on the non-academic staff desk"). Per-row savepoints; a dry run writes each row and rolls it back, leaving nothing; p_claimed the e-mail addresses earlier requests of the same upload gave ({address: staff number}), kept from this one''s rows; returns the counts and each row''s result {row, staffNumber, name, action CREATED|UPDATED|UNCHANGED|SKIPPED|ERROR, personId, changes, kept, unresolved, endedOn, error}.';

-- ── 5 · on the portal but not on this roll ──────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION hrm.roll_absent(p_kind text, p_numbers text[])
RETURNS TABLE (person_id uuid, staff_number text, name text, rank text, posting text)
LANGUAGE plpgsql STABLE AS $function$
DECLARE v_kind text := upper(btrim(coalesce(p_kind, '')));
BEGIN
    IF v_kind NOT IN ('ACADEMIC', 'NON_ACADEMIC') THEN
        RAISE EXCEPTION 'ROLL_KIND: the roll is ACADEMIC or NON_ACADEMIC, not %', coalesce(p_kind, '(none)') USING ERRCODE = '23514';
    END IF;
    RETURN QUERY
    WITH given AS (
        -- the roll's numbers as the portal writes them: P123 and JP858; a bare number is a P number
        SELECT DISTINCT CASE WHEN k ~ '^[0-9]+$' THEN 'P' || k ELSE k END AS num
          FROM (SELECT upper(regexp_replace(x, '[^A-Za-z0-9/]', '', 'g')) AS k FROM unnest(p_numbers) x) y
         WHERE k <> ''
    ), series AS (
        -- a roll speaks for its own series: the senior roll (P) is silent about the juniors (JP), and the other way round
        SELECT DISTINCT CASE WHEN num ~ '^JP[0-9]+$' THEN 'JP' WHEN num ~ '^P[0-9]+$' THEN 'P' ELSE 'OTHER' END AS s FROM given
    )
    SELECT pe.id, pe.staff_number, pe.surname || ', ' || pe.given_names, sr.present_rank,
           coalesce(dp.name, u.name, f.name, sr.unit_as_given)
      FROM iam.person pe
      LEFT JOIN hrm.staff_record sr ON sr.person_id = pe.id
      LEFT JOIN LATERAL (SELECT x.category FROM hrm.employment x WHERE x.person_id = pe.id AND x.status <> 'ENDED'
                          ORDER BY x.appointment_date DESC NULLS LAST LIMIT 1) e ON true
      LEFT JOIN ref.department dp ON dp.code = sr.home_department
      LEFT JOIN ref.unit u ON u.code = sr.home_unit
      LEFT JOIN ref.faculty f ON f.code = sr.home_faculty
     WHERE pe.staff_number IS NOT NULL AND btrim(pe.staff_number) <> '' AND pe.ended_on IS NULL
       -- in service (V698): an office today, or on the HR staff register
       AND (sr.person_id IS NOT NULL
            OR EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = pe.id AND a.valid_from <= current_date
                          AND (a.valid_to IS NULL OR a.valid_to >= current_date)))
       -- academic as the uploads read it (hrm.roll_kind: the register says so, or a lecturer office today); everyone else non-academic
       AND coalesce(hrm.roll_kind(pe.id) = 'ACADEMIC', false) = (v_kind = 'ACADEMIC')
       AND CASE WHEN upper(pe.staff_number) ~ '^JP[0-9]+$' THEN 'JP' WHEN upper(pe.staff_number) ~ '^P[0-9]+$' THEN 'P' ELSE 'OTHER' END
           IN (SELECT s FROM series)
       AND upper(pe.staff_number) NOT IN (SELECT num FROM given)
     ORDER BY pe.surname, pe.given_names, pe.staff_number;
END $function$;
COMMENT ON FUNCTION hrm.roll_absent(text, text[]) IS
  'V750: the staff in service (V698: an office today or on the HR staff register; a staff number; not left) of the kind named — ACADEMIC (the register says so, or a lecturer office) or NON_ACADEMIC (the rest) — whose staff number is not among the roll''s numbers (P123 / JP858; a bare number read as P), within the series the roll holds (P or JP): the nominal roll''s "on the portal but not on this roll". It reads; nobody is ended by it.';

-- ── 6 · the Edit form moves a lecturer office left behind ───────────────────────────────────────────────────────────────────
-- iam.update_lecturer as V140 made it, but for the one test that moves the office: the department saved differs from the record's
-- OR from where a lecturer office still open stands (an office the record had moved past stayed where it was, and saving the
-- department the form showed moved nothing)
CREATE OR REPLACE FUNCTION iam.update_lecturer(
    p_id uuid, p_surname text, p_given text, p_email text, p_phone text,
    p_sex text, p_rank text, p_conuass int, p_department text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_dept text; v_old text; v_sex text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'an edit is made by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p_id AND a.office_code = 'lecturer' AND a.scope_kind = 'department') THEN
        RAISE EXCEPTION 'that person is not a lecturer' USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_surname, '')) = '' OR btrim(coalesce(p_given, '')) = '' THEN
        RAISE EXCEPTION 'a surname and given names are required' USING ERRCODE = '23514';
    END IF;

    -- match the department by code or name (tolerant of case / spacing / & vs AND)
    SELECT d.code INTO v_dept FROM ref.department d
     WHERE d.ended_on IS NULL
       AND ( upper(d.code) = upper(btrim(p_department))
          OR regexp_replace(replace(upper(d.name), '&', 'AND'), '[^A-Z0-9]', '', 'g')
           = regexp_replace(replace(upper(btrim(p_department)), '&', 'AND'), '[^A-Z0-9]', '', 'g') )
     LIMIT 1;
    IF v_dept IS NULL THEN
        RAISE EXCEPTION 'no department matching %', coalesce(nullif(btrim(p_department), ''), '(blank)') USING ERRCODE = '23514';
    END IF;

    UPDATE iam.person
       SET surname = btrim(p_surname), given_names = btrim(p_given),
           email = nullif(btrim(coalesce(p_email, '')), ''), phone = nullif(btrim(coalesce(p_phone, '')), '')
     WHERE id = p_id;

    -- the home department the record currently names
    SELECT home_department INTO v_old FROM hrm.staff_record WHERE person_id = p_id;

    -- move the lecturer office when the department changes — from the record's, or from where a lecturer office still open
    -- stands (V750: an office left behind in another department moves on the next save)
    IF v_old IS DISTINCT FROM v_dept
       OR EXISTS (SELECT 1 FROM iam.office_assignment
                   WHERE person_id = p_id AND office_code = 'lecturer' AND scope_kind = 'department'
                     AND scope_id IS DISTINCT FROM v_dept AND valid_to IS NULL) THEN
        UPDATE iam.office_assignment SET valid_to = current_date
         WHERE person_id = p_id AND office_code = 'lecturer' AND scope_kind = 'department'
           AND scope_id IS DISTINCT FROM v_dept AND valid_to IS NULL;
        IF NOT EXISTS (SELECT 1 FROM iam.office_assignment
                        WHERE person_id = p_id AND office_code = 'lecturer' AND scope_kind = 'department'
                          AND scope_id = v_dept AND valid_to IS NULL) THEN
            INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
            VALUES (gen_random_uuid(), p_id, 'lecturer', 'department', v_dept,
                    'Teaching-staff edit (Users & roles)', v_actor, current_date);
        END IF;
    END IF;

    v_sex := upper(left(nullif(btrim(coalesce(p_sex, '')), ''), 1));
    IF v_sex NOT IN ('M', 'F') THEN v_sex := NULL; END IF;
    INSERT INTO hrm.staff_record (person_id, sex, present_rank, conuass_step, home_department)
    VALUES (p_id, v_sex, nullif(btrim(coalesce(p_rank, '')), ''), p_conuass, v_dept)
    ON CONFLICT (person_id) DO UPDATE SET
        sex = v_sex, present_rank = nullif(btrim(coalesce(p_rank, '')), ''),
        conuass_step = p_conuass, home_department = v_dept, updated_at = now();
END $$;

COMMENT ON FUNCTION iam.update_lecturer(uuid, text, text, text, text, text, text, int, text) IS
  'Edit a lecturer: names, contact, sex, rank, CONUASS and home department '
  '(moving the lecturer office when the department changes — V750: when the department saved differs from the record''s or from '
  'where a lecturer office still open stands, so an office left behind moves on the next save). Staff number and sign-in unchanged.';

COMMIT;
