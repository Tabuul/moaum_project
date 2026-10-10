-- ═══════════════════════════════════════
-- V387 — the Quick Operational Manual: what to click, what to enter, what to
--        confirm and what to expect, by office, on every dashboard
--
--   The portal has a documentation package (docs/manual) that nobody opens at a
--   desk. This migration gives every signed-in person a short manual of their
--   own on the dashboard they already have: a procedure is a title, a purpose,
--   numbered steps and the expected result, bound to the offices that may
--   perform it and to the menu item it lives on. Nothing is rebuilt and nothing
--   of the workflows changes:
--
--   1 · the offices are the portal's own (ref.office, the OFFICE_ authorities the
--       token carries) and the finer grants where they exist — a support
--       posting's capabilities (V334). A procedure bound to a capability is read
--       only by a person whose posting carries it. The filter is the database's
--       (manual.procedures_for), never a page's.
--   2 · a step names a menu item by its id ({menu:t/matriculation-manage}); the
--       portal resolves it to the item's current label and page, so a menu
--       renamed later renames the manual.
--   3 · the manual is read through the one sign-in; printed and downloaded
--       through the central document system (V320); written to the audit spine.
--   4 · Manual Management (Super Administrator, System Administrator, Director
--       of ICT): a procedure is drafted, published, unpublished, archived and
--       restored; every edit keeps the previous version; the edition is a
--       number the dashboard shows (1.0 at birth, a minor step on every
--       publication, a major step when the administrator releases one).
--   5 · the first edition is seeded here from the portal as it is wired today
--       (frontend/src/lib/menus.ts, the screens and docs/manual); the portal's
--       build checks every {menu:…} reference against the menus.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V387: the Quick Operational Manual, its first edition', true);

CREATE SCHEMA IF NOT EXISTS manual;
COMMENT ON SCHEMA manual IS 'V387: the Quick Operational Manual — procedures by office, their versions, the edition and the record of readings';

-- ── 1 · the keys a procedure may be bound to: every office, and the portal''s own sidebars that are not offices ────────
-- A postgraduate signs in as a student but reads the School''s sidebar (menu pgstudent); a JUPEB applicant signs in as an
-- applicant with the JUPEB sidebar. The portal names the sidebar beside the office, and the manual binds to either.
CREATE OR REPLACE FUNCTION manual.known_keys()
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT array_agg(k ORDER BY k) FROM (
        SELECT code AS k FROM ref.office
        UNION SELECT unnest(ARRAY['pgstudent', 'pgapplicant', 'jupebapplicant', 'jupebcandidate', 'jupebstudent', 'cceapplicant', 'everyone'])
    ) x
$$;
COMMENT ON FUNCTION manual.known_keys() IS 'V387: what a procedure may be bound to — an office code, a sidebar the portal names beside the office, or everyone (every signed-in person)';

CREATE OR REPLACE FUNCTION manual.categories()
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY['DASHBOARD', 'ACCOUNT', 'STUDENTS', 'PAYMENTS', 'ADMISSIONS', 'ACADEMICS', 'RESULTS', 'EXAMS', 'SUPPORT', 'REPORTS', 'SETTINGS']
$$;

-- ── 2 · the procedure ────────────────────────────────────────────────────────────
CREATE TABLE manual.procedure (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(slug) <= 80),
    title           text NOT NULL CHECK (btrim(title) <> '' AND length(title) <= 120),
    purpose         text NOT NULL CHECK (btrim(purpose) <> '' AND length(purpose) <= 300),
    category        text NOT NULL CHECK (category = ANY (manual.categories())),
    offices         text[] NOT NULL CHECK (cardinality(offices) >= 1),
    capabilities    text[] NOT NULL DEFAULT '{}' CHECK (capabilities <@ helpdesk.support_capabilities()),
    menu_id         text CHECK (menu_id IS NULL OR menu_id ~ '^[a-z]+/[a-z0-9-]+$'),
    route           text CHECK (route IS NULL OR route ~ '^[a-z]+/[a-z0-9-]+$'),
    steps           text[] NOT NULL CHECK (cardinality(steps) BETWEEN 1 AND 20),
    expected        text NOT NULL CHECK (btrim(expected) <> '' AND length(expected) <= 300),
    sort_order      int NOT NULL DEFAULT 100,
    state           text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'PUBLISHED', 'ARCHIVED')),
    version         int NOT NULL DEFAULT 1 CHECK (version >= 1),
    seeded          boolean NOT NULL DEFAULT false,
    published_at    timestamptz,
    archived_at     timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    updated_by      uuid,
    updated_office  text,
    CONSTRAINT ck_manual_state_dates CHECK ((state = 'PUBLISHED') = (published_at IS NOT NULL AND archived_at IS NULL) OR state = 'DRAFT')
);
COMMENT ON TABLE manual.procedure IS 'V387: one procedure of the Quick Operational Manual — what to click, what to enter, what to expect — bound to the offices that may perform it';
COMMENT ON COLUMN manual.procedure.offices IS 'V387: the keys (manual.known_keys) whose manual carries the procedure; the acting office is matched on the server';
COMMENT ON COLUMN manual.procedure.capabilities IS 'V387: when not empty, the procedure is read only by a support posting carrying one of these (V334)';
COMMENT ON COLUMN manual.procedure.menu_id IS 'V387: the menu item the procedure lives on; the portal resolves it to the current label and page';
COMMENT ON COLUMN manual.procedure.route IS 'V387: the page (route id) whose contextual help lists the procedure; the menu item when null';
COMMENT ON COLUMN manual.procedure.steps IS 'V387: the numbered steps; `Button` names a control, {menu:<id>} a menu item';
CREATE INDEX ix_manual_procedure_offices ON manual.procedure USING gin (offices);
CREATE INDEX ix_manual_procedure_state ON manual.procedure (state, category, sort_order);
SELECT audit.attach('manual.procedure');

-- every edit keeps what the procedure said before it
CREATE TABLE manual.procedure_version (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    procedure_id    uuid NOT NULL REFERENCES manual.procedure (id) ON DELETE CASCADE,
    version         int NOT NULL,
    snapshot        jsonb NOT NULL,
    saved_at        timestamptz NOT NULL DEFAULT now(),
    saved_by        uuid,
    saved_office    text,
    note            text,
    UNIQUE (procedure_id, version)
);
COMMENT ON TABLE manual.procedure_version IS 'V387: the procedure as it read at each version before an edit replaced it';
SELECT audit.exempt('manual.procedure_version', 'a snapshot of an audited row at the moment it was edited, written once and never changed; the edit itself is on the spine');

-- the edition the dashboard shows
CREATE TABLE manual.edition (
    one             boolean PRIMARY KEY DEFAULT true CHECK (one),
    major           int NOT NULL DEFAULT 1 CHECK (major >= 1),
    minor           int NOT NULL DEFAULT 0 CHECK (minor >= 0),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    updated_by      uuid,
    updated_office  text,
    note            text
);
COMMENT ON TABLE manual.edition IS 'V387: the manual''s edition — a minor step on every publication, unpublication or archiving; a major step when an administrator releases one';
SELECT audit.attach('manual.edition');
INSERT INTO manual.edition (major, minor, note) VALUES (1, 0, 'V387: the first edition, seeded from the portal as wired');

-- the readings: who opened the manual, searched it, read a procedure, printed or downloaded it
CREATE TABLE manual.view (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id       uuid NOT NULL,
    office          text,
    kind            text NOT NULL CHECK (kind IN ('OPEN', 'SEARCH', 'PROCEDURE', 'PRINT', 'PDF')),
    procedure_id    uuid REFERENCES manual.procedure (id) ON DELETE SET NULL,
    q               text CHECK (q IS NULL OR length(q) <= 120),
    at              timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_manual_view_at ON manual.view (at DESC);
CREATE INDEX ix_manual_view_procedure ON manual.view (procedure_id) WHERE procedure_id IS NOT NULL;
SELECT audit.exempt('manual.view', 'a reading of the manual: written once per opening, never changed, thousands a day; the manual''s content and its state changes are on the spine');

-- ── 3 · reading ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION manual.edition_text()
RETURNS text
LANGUAGE sql STABLE AS $$ SELECT major || '.' || minor FROM manual.edition $$;

/* The procedures a person reads: published, bound to one of the keys the person acts under (the office, the sidebar the
   portal names beside it, and everyone), and — when the procedure is bound to a capability — carried by one of the
   person's support postings. The server passes the keys from the token and the capabilities from helpdesk.agent_capabilities. */
CREATE OR REPLACE FUNCTION manual.procedures_for(p_keys text[], p_caps text[] DEFAULT '{}')
RETURNS SETOF manual.procedure
LANGUAGE sql STABLE AS $$
    SELECT p.* FROM manual.procedure p
     WHERE p.state = 'PUBLISHED'
       AND p.offices && (coalesce(p_keys, '{}') || ARRAY['everyone'])
       AND (p.capabilities = '{}' OR p.capabilities && coalesce(p_caps, '{}'))
     ORDER BY array_position(manual.categories(), p.category), p.sort_order, p.title
$$;
COMMENT ON FUNCTION manual.procedures_for(text[], text[]) IS 'V387: the manual of a person — published procedures bound to their keys, and to a capability their posting carries';

CREATE OR REPLACE FUNCTION manual.search(p_keys text[], p_caps text[], p_q text)
RETURNS SETOF manual.procedure
LANGUAGE sql STABLE AS $$
    SELECT p.* FROM manual.procedures_for(p_keys, p_caps) p
     WHERE p_q IS NULL OR btrim(p_q) = ''
        OR p.title ILIKE '%' || btrim(p_q) || '%' OR p.purpose ILIKE '%' || btrim(p_q) || '%'
        OR p.category ILIKE '%' || btrim(p_q) || '%' OR coalesce(p.menu_id, '') ILIKE '%' || btrim(p_q) || '%'
        OR EXISTS (SELECT 1 FROM unnest(p.steps) s WHERE s ILIKE '%' || btrim(p_q) || '%')
$$;

CREATE OR REPLACE FUNCTION manual.context_for(p_keys text[], p_caps text[], p_route text)
RETURNS SETOF manual.procedure
LANGUAGE sql STABLE AS $$
    SELECT p.* FROM manual.procedures_for(p_keys, p_caps) p
     WHERE p_route IS NOT NULL AND (p.route = p_route OR (p.route IS NULL AND p.menu_id = p_route))
$$;
COMMENT ON FUNCTION manual.context_for(text[], text[], text) IS 'V387: the procedures a page offers as its own help — those bound to its route, or living on its menu item';

CREATE OR REPLACE FUNCTION manual.record_view(p_person uuid, p_office text, p_kind text, p_procedure uuid, p_q text)
RETURNS void
LANGUAGE sql AS $$
    INSERT INTO manual.view (person_id, office, kind, procedure_id, q) VALUES (p_person, p_office, p_kind, p_procedure, left(p_q, 120))
$$;

-- ── 4 · writing: Manual Management ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION manual.check_binding(p_offices text[], p_steps text[])
RETURNS void
LANGUAGE plpgsql STABLE AS $$
DECLARE bad text; s text;
BEGIN
    SELECT o INTO bad FROM unnest(p_offices) o WHERE NOT (o = ANY (manual.known_keys())) LIMIT 1;
    IF bad IS NOT NULL THEN
        RAISE EXCEPTION 'MANUAL_OFFICE_UNKNOWN: % is not an office of the portal nor a sidebar it names', bad USING ERRCODE = '23514';
    END IF;
    FOREACH s IN ARRAY p_steps LOOP
        IF s IS NULL OR btrim(s) = '' THEN
            RAISE EXCEPTION 'MANUAL_STEP_EMPTY: every step says something' USING ERRCODE = '23514';
        END IF;
        IF length(s) > 400 THEN
            RAISE EXCEPTION 'MANUAL_STEP_LONG: a step is one instruction, not a paragraph (400 characters at most)' USING ERRCODE = '23514';
        END IF;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION manual.bump_edition(p_actor uuid, p_office text, p_note text, p_major boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE manual.edition
       SET major = CASE WHEN p_major THEN major + 1 ELSE major END,
           minor = CASE WHEN p_major THEN 0 ELSE minor + 1 END,
           updated_at = now(), updated_by = p_actor, updated_office = p_office, note = p_note;
    RETURN manual.edition_text();
END $$;
COMMENT ON FUNCTION manual.bump_edition(uuid, text, text, boolean) IS 'V387: a minor step of the edition (every publication), or the major step an administrator releases';

/* A procedure drafted or edited. A new one is a DRAFT until published; an edit of an existing one keeps the previous version
   as a snapshot and counts the version up — a published procedure stays published while edited (the manual never goes blank). */
CREATE OR REPLACE FUNCTION manual.save_procedure(
    p_id uuid, p_slug text, p_title text, p_purpose text, p_category text, p_offices text[], p_capabilities text[],
    p_menu_id text, p_route text, p_steps text[], p_expected text, p_sort_order int,
    p_actor uuid, p_office text, p_note text)
RETURNS manual.procedure
LANGUAGE plpgsql AS $$
DECLARE old manual.procedure; r manual.procedure; v_slug text := lower(btrim(p_slug));
BEGIN
    PERFORM manual.check_binding(p_offices, p_steps);
    IF p_id IS NULL THEN
        IF EXISTS (SELECT 1 FROM manual.procedure WHERE slug = v_slug) THEN
            RAISE EXCEPTION 'MANUAL_SLUG_TAKEN: a procedure already carries the key %', v_slug USING ERRCODE = '23514';
        END IF;
        INSERT INTO manual.procedure (slug, title, purpose, category, offices, capabilities, menu_id, route, steps, expected, sort_order,
                                      state, created_by, updated_by, updated_office)
        VALUES (v_slug, btrim(p_title), btrim(p_purpose), p_category, p_offices, coalesce(p_capabilities, '{}'), nullif(btrim(p_menu_id), ''),
                nullif(btrim(p_route), ''), p_steps, btrim(p_expected), coalesce(p_sort_order, 100), 'DRAFT', p_actor, p_actor, p_office)
        RETURNING * INTO r;
        RETURN r;
    END IF;
    SELECT * INTO old FROM manual.procedure WHERE id = p_id FOR UPDATE;
    IF old.id IS NULL THEN
        RAISE EXCEPTION 'MANUAL_NOT_FOUND: no such procedure' USING ERRCODE = '23514';
    END IF;
    IF old.state = 'ARCHIVED' THEN
        RAISE EXCEPTION 'MANUAL_ARCHIVED: an archived procedure is restored before it is edited' USING ERRCODE = '23514';
    END IF;
    IF v_slug <> old.slug AND EXISTS (SELECT 1 FROM manual.procedure WHERE slug = v_slug) THEN
        RAISE EXCEPTION 'MANUAL_SLUG_TAKEN: a procedure already carries the key %', v_slug USING ERRCODE = '23514';
    END IF;
    INSERT INTO manual.procedure_version (procedure_id, version, snapshot, saved_by, saved_office, note)
    VALUES (old.id, old.version, to_jsonb(old) - 'id', p_actor, p_office, p_note);
    UPDATE manual.procedure
       SET slug = v_slug, title = btrim(p_title), purpose = btrim(p_purpose), category = p_category, offices = p_offices,
           capabilities = coalesce(p_capabilities, '{}'), menu_id = nullif(btrim(p_menu_id), ''), route = nullif(btrim(p_route), ''),
           steps = p_steps, expected = btrim(p_expected), sort_order = coalesce(p_sort_order, sort_order),
           version = old.version + 1, updated_at = now(), updated_by = p_actor, updated_office = p_office
     WHERE id = p_id
    RETURNING * INTO r;
    IF r.state = 'PUBLISHED' THEN
        PERFORM manual.bump_edition(p_actor, p_office, 'edited: ' || r.title);
    END IF;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION manual.set_state(p_id uuid, p_action text, p_actor uuid, p_office text, p_note text)
RETURNS manual.procedure
LANGUAGE plpgsql AS $$
DECLARE r manual.procedure;
BEGIN
    SELECT * INTO r FROM manual.procedure WHERE id = p_id FOR UPDATE;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'MANUAL_NOT_FOUND: no such procedure' USING ERRCODE = '23514';
    END IF;
    CASE p_action
        WHEN 'PUBLISH' THEN
            IF r.state = 'PUBLISHED' THEN RAISE EXCEPTION 'MANUAL_STATE: the procedure is already published' USING ERRCODE = '23514'; END IF;
            UPDATE manual.procedure SET state = 'PUBLISHED', published_at = now(), archived_at = NULL, updated_at = now(), updated_by = p_actor, updated_office = p_office
             WHERE id = p_id RETURNING * INTO r;
        WHEN 'UNPUBLISH' THEN
            IF r.state <> 'PUBLISHED' THEN RAISE EXCEPTION 'MANUAL_STATE: only a published procedure is unpublished' USING ERRCODE = '23514'; END IF;
            UPDATE manual.procedure SET state = 'DRAFT', published_at = NULL, updated_at = now(), updated_by = p_actor, updated_office = p_office
             WHERE id = p_id RETURNING * INTO r;
        WHEN 'ARCHIVE' THEN
            IF r.state = 'ARCHIVED' THEN RAISE EXCEPTION 'MANUAL_STATE: the procedure is already archived' USING ERRCODE = '23514'; END IF;
            UPDATE manual.procedure SET state = 'ARCHIVED', published_at = NULL, archived_at = now(), updated_at = now(), updated_by = p_actor, updated_office = p_office
             WHERE id = p_id RETURNING * INTO r;
        WHEN 'RESTORE' THEN
            IF r.state <> 'ARCHIVED' THEN RAISE EXCEPTION 'MANUAL_STATE: only an archived procedure is restored' USING ERRCODE = '23514'; END IF;
            UPDATE manual.procedure SET state = 'DRAFT', archived_at = NULL, updated_at = now(), updated_by = p_actor, updated_office = p_office
             WHERE id = p_id RETURNING * INTO r;
        ELSE
            RAISE EXCEPTION 'MANUAL_ACTION: % is not PUBLISH, UNPUBLISH, ARCHIVE or RESTORE', p_action USING ERRCODE = '23514';
    END CASE;
    PERFORM manual.bump_edition(p_actor, p_office, lower(p_action) || ': ' || r.title || coalesce(' — ' || nullif(btrim(p_note), ''), ''));
    RETURN r;
END $$;
COMMENT ON FUNCTION manual.set_state(uuid, text, uuid, text, text) IS 'V387: publish, unpublish, archive or restore a procedure; each steps the edition';

CREATE OR REPLACE FUNCTION manual.reorder(p_ids uuid[], p_actor uuid, p_office text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    UPDATE manual.procedure p
       SET sort_order = x.ord * 10, updated_at = now(), updated_by = p_actor, updated_office = p_office
      FROM unnest(p_ids) WITH ORDINALITY AS x (id, ord)
     WHERE p.id = x.id AND p.sort_order IS DISTINCT FROM x.ord * 10;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- ── 5 · the first edition: a seed is published at birth and marked as the migration''s ──
CREATE OR REPLACE FUNCTION manual.seed(
    p_slug text, p_title text, p_category text, p_offices text[], p_menu_id text, p_route text,
    p_purpose text, p_steps text[], p_expected text, p_capabilities text[] DEFAULT '{}', p_sort_order int DEFAULT 100)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM manual.check_binding(p_offices, p_steps);
    INSERT INTO manual.procedure (slug, title, purpose, category, offices, capabilities, menu_id, route, steps, expected, sort_order,
                                  state, seeded, published_at, created_by, updated_by, updated_office)
    VALUES (p_slug, p_title, p_purpose, p_category, p_offices, coalesce(p_capabilities, '{}'), p_menu_id, p_route, p_steps, p_expected,
            p_sort_order, 'PUBLISHED', true, now(), '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'ict')
    ON CONFLICT (slug) DO NOTHING;
END $$;
COMMENT ON FUNCTION manual.seed(text, text, text, text[], text, text, text, text[], text, text[], int) IS 'V387: a procedure of the first edition — published at birth; an existing key is left as the administrator has it';

-- the first edition, office by office (generated from the seed lists; every {menu:…} checked against the portal's menus by the build)
SELECT manual.seed('sign-in', 'Sign in', 'ACCOUNT', ARRAY['everyone']::text[], NULL, NULL,
    'Open your dashboard.',
    ARRAY['Open the portal address in your browser.',
          'Enter your matric, staff or JAMB number, or your e-mail, in the first box.',
          'Enter your password.',
          'Click `Sign in`.',
          'If you hold several offices, choose the office you are acting as.'],
    'Your dashboard opens with the menu of your office.', '{}'::text[], 10);
SELECT manual.seed('forgot-password', 'Reset a forgotten password', 'ACCOUNT', ARRAY['everyone']::text[], NULL, NULL,
    'Get back in when you cannot remember your password.',
    ARRAY['On the sign-in page click `Forgot password?`.',
          'Enter the e-mail on your record.',
          'Click `Send the reset link`.',
          'Open the e-mail and click the link (it works once, for a limited time).',
          'Enter the new password twice and click `Save the new password`.',
          'Sign in with the new password.'],
    'Every earlier session is ended and the new password works at once.', '{}'::text[], 11);
SELECT manual.seed('sign-in-help', 'Ask ICT for help signing in', 'ACCOUNT', ARRAY['everyone']::text[], NULL, NULL,
    'Reach ICT Support when no reset link arrives.',
    ARRAY['On the sign-in page click `Ask ICT Support for help`.',
          'Enter your name, your e-mail and your phone.',
          'Describe what happened in `What happened`.',
          'Click `Send to ICT Support`.',
          'Keep the request number shown; click `Track the request` to follow it.'],
    'The ICT Support Desk receives a ticket and answers by e-mail or SMS.', '{}'::text[], 12);
SELECT manual.seed('change-password', 'Change your password', 'ACCOUNT', ARRAY['everyone']::text[], NULL, NULL,
    'Replace your password while signed in.',
    ARRAY['Open your profile from the menu (`My Profile` for staff, `Profile` for students).',
          'Under the password section enter `Current password` and `New password`.',
          'Click `Save`.',
          'Sign in again on any other device.'],
    'The new password is in force and every other session is ended.', '{}'::text[], 13);
SELECT manual.seed('switch-office', 'Act as another office you hold', 'ACCOUNT', ARRAY['everyone']::text[], NULL, NULL,
    'Change the office you are acting as when you hold more than one.',
    ARRAY['Click your name at the foot of the menu.',
          'Click `Sign out`.',
          'Sign in again and choose the other office when asked.'],
    'The menu and every screen are the chosen office''s.', '{}'::text[], 14);
SELECT manual.seed('raise-ticket', 'Raise an ICT support ticket', 'SUPPORT', ARRAY['everyone']::text[], NULL, NULL,
    'Report a portal problem to the ICT Support Desk.',
    ARRAY['Open `ICT Support Tickets` in the menu.',
          'Click `Submit a New Ticket`.',
          'Choose the `Category`, enter a `Subject` and describe the problem in `Description`; attach a screenshot under `Attachments` if you have one.',
          'Click `Submit the Ticket`.',
          'Note the ticket number; open the ticket later to read the desk''s reply and, if it did not settle it, write under `Add an update for the desk`.'],
    'The desk''s queue receives the ticket; you are told of every reply by e-mail or SMS.', '{}'::text[], 20);
SELECT manual.seed('notifications', 'Read your notifications', 'DASHBOARD', ARRAY['everyone']::text[], NULL, NULL,
    'See what the portal has told you.',
    ARRAY['Open `Notifications` in the menu.',
          'Filter by `Channel` (e-mail, SMS, portal) or type a word in `Search`.',
          'Click a notice to read it in full.'],
    'Every notice sent to you is listed, newest first.', '{}'::text[], 21);
SELECT manual.seed('search-records', 'Search a record', 'DASHBOARD', ARRAY['everyone']::text[], NULL, NULL,
    'Find a student, applicant, staff member or course quickly.',
    ARRAY['Click `Search records` at the top of any page (or press `/`).',
          'Type a number, a name or a code.',
          'Click the result to open the record your office may read.'],
    'The record opens within your office''s scope.', '{}'::text[], 22);
SELECT manual.seed('student-dashboard', 'Read your dashboard', 'DASHBOARD', ARRAY['student']::text[], 's/dashboard', NULL,
    'Know what to do next this session.',
    ARRAY['Open {menu:s/dashboard}.',
          'Read the `Next step` card: pay school fees, register courses or read results.',
          'Click the card''s button (`Pay now`, `Register courses` or `Your results`).'],
    'You are on the screen the next step needs.', '{}'::text[], 10);
SELECT manual.seed('student-pay-fees', 'Pay school fees', 'PAYMENTS', ARRAY['student']::text[], 's/fees', NULL,
    'Pay the session''s school fees through the gateway and hold the receipt.',
    ARRAY['Open {menu:s/fees}.',
          'Choose the semester tab (`First semester`, `Full session · both semesters` or `Second semester`).',
          'Click `See breakdown` to read every line of the fee.',
          'Click `Pay now`; the gateway page opens.',
          'Pay by card, transfer or USSD on the gateway and wait to be returned to the portal.',
          'Confirm the status reads `PAID`; click `Receipt` to download it.'],
    'The fee is PAID, course registration unlocks and the receipt carries a verification code.', '{}'::text[], 20);
SELECT manual.seed('student-gst-fee', 'Pay the GST or EPS fee', 'PAYMENTS', ARRAY['student']::text[], 's/gst', NULL,
    'Pay the General Studies or Entrepreneurship fee a course of this session requires.',
    ARRAY['Open {menu:s/gst}.',
          'Read which GST/EPS course of the session is owed and the amount.',
          'Click `PAY GST FEE`.',
          'Pay on the gateway and wait to be returned.',
          'Open {menu:s/register} and add the course.'],
    'The course registers; without the fee it stays locked on the registration screen.', '{}'::text[], 21);
SELECT manual.seed('student-wallet', 'Top up the wallet or follow NELFUND funding', 'PAYMENTS', ARRAY['student']::text[], 's/wallet', NULL,
    'See what the wallet holds from each source and pay the shortfall.',
    ARRAY['Open {menu:s/wallet}.',
          'Read the balance by source (own top-up, NELFUND, scholarship).',
          'To add money click `Top up`, enter the amount and pay on the gateway.',
          'Click `Download statement` for the wallet statement.',
          'For a refund of your own top-up fill `Refund` (amount, bank, account number, account name) and submit.'],
    'The wallet pays the fee lines a source covers; a top-up covers only the shortfall.', '{}'::text[], 22);
SELECT manual.seed('student-register', 'Register courses', 'ACADEMICS', ARRAY['student']::text[], 's/register', NULL,
    'Register the semester''s courses within the unit limit.',
    ARRAY['Open {menu:s/register}; school fees must read PAID.',
          'Choose the session and the semester.',
          'Tick the courses; carryovers are listed first and the unit total is shown.',
          'Click `Register courses`.',
          'Read the summary and confirm.',
          'Click `Course form`, then `Print` to print or download the course form.'],
    'The registration is SUBMITTED to your department and the course form carries a verification code.', '{}'::text[], 30);
SELECT manual.seed('student-registration-history', 'Read a past registration', 'ACADEMICS', ARRAY['student']::text[], 's/reghistory', NULL,
    'Open an earlier session''s course form.',
    ARRAY['Open {menu:s/reghistory}.',
          'Click the session and semester.',
          'Click `Course form` to print it again.'],
    'The registration as approved then, with its course form.', '{}'::text[], 31);
SELECT manual.seed('student-results', 'Read your results', 'RESULTS', ARRAY['student']::text[], 's/results', NULL,
    'Read a semester''s published results and the statement of results.',
    ARRAY['Open {menu:s/results}.',
          'Choose the session and the semester.',
          'Click `Semester Results`.',
          'Click `All results` for every session, or {menu:s/broadsheet} for the broadsheet view.'],
    'The published grades, the GPA and the CGPA are shown; what is not yet published is not.', '{}'::text[], 40);
SELECT manual.seed('student-result-query', 'Query a result', 'RESULTS', ARRAY['student']::text[], 's/query', NULL,
    'Ask the department to look again at a mark.',
    ARRAY['Open {menu:s/query}.',
          'Choose the `Course` and `Which mark` (CA or examination).',
          'Write `What you say is wrong`.',
          'Submit the query and keep its number.',
          'Return to the same screen to read the department''s answer.'],
    'The query reaches the Head of Department; its outcome is shown here and sent to you.', '{}'::text[], 41);
SELECT manual.seed('student-carryover', 'See your carryovers', 'RESULTS', ARRAY['student']::text[], 's/carryover', NULL,
    'Know which courses must be repeated.',
    ARRAY['Open {menu:s/carryover}.',
          'Read the courses failed and the session they are offered again.',
          'Open {menu:s/register} when the semester opens; they are listed first.'],
    'Every carryover is registered before new courses.', '{}'::text[], 42);
SELECT manual.seed('student-transcript', 'Request a transcript, statement or certificate copy', 'ACADEMICS', ARRAY['student']::text[], 's/documents', NULL,
    'Have an official document issued or sent to an institution.',
    ARRAY['Open {menu:s/documents}.',
          'Click `Request a document`.',
          'Choose the `Document`, the `Academic session` and `Semester` where asked, `Delivery` and `Copies`.',
          'Under `Send to` enter the institution, the recipient and the address or e-mail.',
          'Pay the fee shown on the gateway.',
          'Click `Timeline` on the request to follow it; click `Secure link` for the verification link.'],
    'The Documents Office processes the request; you are told at each stage.', '{}'::text[], 50);
SELECT manual.seed('student-exam-card', 'Print the examination card', 'EXAMS', ARRAY['student']::text[], 's/exams', NULL,
    'Carry the card the hall checks.',
    ARRAY['Open {menu:s/exams}.',
          'Confirm the courses listed are the ones registered.',
          'Click `Examination card` and print it.'],
    'The card lists your papers with a QR code the invigilator scans.', '{}'::text[], 60);
SELECT manual.seed('student-cbt', 'Sit a CBT examination', 'EXAMS', ARRAY['student']::text[], 's/cbt', NULL,
    'Take a computer-based examination on the day it opens.',
    ARRAY['Open {menu:s/cbt}.',
          'Click `View instructions` on the examination and read them.',
          'Click `Print your CBT slip` if a slip is required at the hall.',
          'At the hall, on the examination day, click `Start`; the clock is the server''s.',
          'Answer; every answer is saved as you go.',
          'Click `SUBMIT EXAM` before the time ends (an unsubmitted attempt is submitted when time runs out).'],
    'The attempt is SUBMITTED; the result appears when the office publishes it.', '{}'::text[], 61);
SELECT manual.seed('student-timetable-attendance', 'Read the timetable and your attendance', 'ACADEMICS', ARRAY['student']::text[], 's/timetable', NULL,
    'Know where to be and how many lectures you have attended.',
    ARRAY['Open {menu:s/timetable} for the week''s lectures.',
          'Open {menu:s/attendance} for each course''s lectures attended and the percentage.'],
    'Both read from the department''s registers.', '{}'::text[], 32);
SELECT manual.seed('student-courses', 'Open a course space and submit an assignment', 'ACADEMICS', ARRAY['student']::text[], 's/courses', NULL,
    'Read materials and submit work for a registered course.',
    ARRAY['Open {menu:s/courses}.',
          'Click the course.',
          'Download the materials listed.',
          'Click `Open assignment`, attach your work and submit before the deadline.'],
    'The submission is timed and listed to the lecturer.', '{}'::text[], 33);
SELECT manual.seed('student-deferment', 'Apply for a deferment', 'ACADEMICS', ARRAY['student']::text[], 's/deferment', NULL,
    'Defer a semester or a session with the fee and the documents.',
    ARRAY['Open {menu:s/deferment}.',
          'Choose the `Deferment type`, the `Academic session` and `Semester`, and give the `Reason`.',
          'Click `Save and Continue`; upload the `Document` asked for and click `Upload`.',
          'Click `Continue to Review`, then `Pay … Deferment Fee` and pay on the gateway.',
          'Click `Submit Deferment Application`.',
          'Click `Timeline` to follow the department''s and the Registry''s decisions.'],
    'The application goes to your department; the outcome is shown and sent to you.', '{}'::text[], 34);
SELECT manual.seed('student-transfer', 'Apply for an inter-departmental transfer', 'ACADEMICS', ARRAY['student']::text[], 's/transfer', NULL,
    'Move to another programme with both departments'' consent.',
    ARRAY['Open {menu:s/transfer}.',
          'Choose the `Course applied for`, enter `Your UTME score` and the `Reason for seeking transfer`.',
          'Submit the application.',
          'When approved, click `Approval letter`.'],
    'The receiving and releasing departments decide; the Registry effects the transfer.', '{}'::text[], 35);
SELECT manual.seed('student-hostel', 'Apply for hostel accommodation', 'STUDENTS', ARRAY['student']::text[], 's/hostel', NULL,
    'Get a bed space while the window is open.',
    ARRAY['Open {menu:s/hostel}.',
          'Choose the `Hostel`, the `Room type`, your `Hall preferred` and `Block preferred`; state any `Special or medical accommodation need`.',
          'Click `Submit application`.',
          'When a space is offered click `Generate the payment reference`, then `Pay … now` within 48 hours.',
          'Read the allocation and the check-in instructions on the same screen.'],
    'The space is held 48 hours for payment and allocated when paid.', '{}'::text[], 70);
SELECT manual.seed('student-library-health', 'Use the library and the clinic', 'STUDENTS', ARRAY['student']::text[], 's/library', NULL,
    'Search the catalogue, pay a fine, book a clinic visit.',
    ARRAY['Open {menu:s/library}; type in `Search the catalogue`; click `Pay …` on a fine listed.',
          'Open {menu:s/health}; fill `Reason for visit` and `Preferred time` and submit.'],
    'Fines are cleared and the visit is booked.', '{}'::text[], 71);
SELECT manual.seed('student-idcard', 'Request the identity card', 'STUDENTS', ARRAY['student']::text[], 's/idcard', NULL,
    'Get the card, or a replacement.',
    ARRAY['Open {menu:s/idcard}.',
          'Confirm the photograph and the details; correct them under {menu:s/biodata} first if wrong.',
          'Click `Request a replacement` when a card was lost; pay the fee shown.',
          'Collect the card where the screen says.'],
    'The card is printed by the office named on the screen.', '{}'::text[], 72);
SELECT manual.seed('student-biodata', 'Correct your biodata or contact details', 'ACCOUNT', ARRAY['student']::text[], 's/profile', NULL,
    'Keep your phone, e-mail and address current; ask for a correction of a locked field.',
    ARRAY['Open {menu:s/profile}; edit `Phone`, `Personal email` and `Contact address`; click `Save`.',
          'Open {menu:s/biodata} for the locked fields (name, date of birth, state).',
          'Click `Request a change`, state the correction and attach the evidence.',
          'Follow the request on the same screen.'],
    'Contact details change at once; a locked field changes when the Registry approves.', '{}'::text[], 15);
SELECT manual.seed('student-support', 'Ask an office for help', 'SUPPORT', ARRAY['student']::text[], 's/support', NULL,
    'Send a request to the office that can act (department, Bursary, Registry).',
    ARRAY['Open {menu:s/support}.',
          'Click the office.',
          'Write `What is the problem?` and anything more; attach `Supporting documents`.',
          'Submit and follow the request on the same screen.'],
    'The office''s queue receives it and the answer is shown here.', '{}'::text[], 23);
SELECT manual.seed('student-graduation', 'Graduation clearance', 'ACADEMICS', ARRAY['student']::text[], 's/dashboard', NULL,
    'Clear every unit for graduation and collect the certificate.',
    ARRAY['Open {menu:s/dashboard} in your final session; open the graduation card.',
          'Read each unit''s clearance (department, library, hostel, Bursary); act on what is marked outstanding.',
          'Pay the graduation fee when it is listed.',
          'Open {menu:s/documents} to request the certificate when the list is published.'],
    'Every unit reads CLEARED and the certificate request is accepted.', '{}'::text[], 80);
SELECT manual.seed('pg-register-results', 'Register courses and read results (postgraduate)', 'ACADEMICS', ARRAY['pgstudent']::text[], 's/pgcourses', NULL,
    'Register the School''s courses for the semester and read their results.',
    ARRAY['Open {menu:s/pgcourses}.',
          'Choose the session and semester; tick the courses; click `Register`.',
          'Return here to read results when the School publishes them.'],
    'The registration is with the School; results appear when published.', '{}'::text[], 30);
SELECT manual.seed('pg-progress', 'Follow your academic progress', 'ACADEMICS', ARRAY['pgstudent']::text[], 's/pgprogress', NULL,
    'See the stages of your programme and what is next.',
    ARRAY['Open {menu:s/pgprogress}.',
          'Read the stage reached (coursework, proposal, seminar, thesis, viva, clearance).',
          'Click `Open` on the stage to act on it.'],
    'Each stage names what you must submit and who decides.', '{}'::text[], 31);
SELECT manual.seed('pg-research', 'Submit the proposal, seminar and thesis', 'ACADEMICS', ARRAY['pgstudent']::text[], 's/research', NULL,
    'Move the research through its stages.',
    ARRAY['Open {menu:s/research}.',
          'Upload the document the stage asks for (proposal, seminar paper, draft thesis).',
          'Submit; read the supervisor''s and the panel''s decisions on the same screen.'],
    'The School''s research desk receives each submission.', '{}'::text[], 32);
SELECT manual.seed('pg-fees', 'Pay postgraduate fees', 'PAYMENTS', ARRAY['pgstudent']::text[], 's/fees', NULL,
    'Pay the School''s fees and hold the receipt.',
    ARRAY['Open {menu:s/fees}.',
          'Click `Pay now`, pay on the gateway and wait to be returned.',
          'Click `Receipt`.'],
    'The fee reads PAID and registration unlocks.', '{}'::text[], 20);
SELECT manual.seed('applicant-register', 'Register for Post-UTME by JAMB number', 'ADMISSIONS', ARRAY['applicant']::text[], NULL, NULL,
    'Create your applicant account.',
    ARRAY['Open the Post-UTME registration page from the University website.',
          'Enter your JAMB registration number and click `Continue`.',
          'Confirm the name and programme JAMB sent; enter your e-mail, phone and a password.',
          'Click `Continue` to create the account and sign in.'],
    'Your applicant dashboard opens at stage 1 (application fee).', '{}'::text[], 10);
SELECT manual.seed('applicant-fee', 'Pay the application fee', 'PAYMENTS', ARRAY['applicant']::text[], 'a/fee', NULL,
    'Open the application form by paying the fee.',
    ARRAY['Open {menu:a/fee}.',
          'Click `Pay the application fee`; pay on the gateway and wait to be returned.',
          'Confirm the status reads PAID.'],
    'The application form opens.', '{}'::text[], 11);
SELECT manual.seed('applicant-form', 'Fill and submit the application form', 'ADMISSIONS', ARRAY['applicant']::text[], 'a/apply', NULL,
    'Give the University your details and O''Level results.',
    ARRAY['Open {menu:a/apply} and click `Open the application form`.',
          'Fill every section; click `Save and come back later` to keep a draft.',
          'Enter your O''Level sittings and grades exactly as on the result.',
          'Upload the passport photograph.',
          'Submit the form.'],
    'The application is SUBMITTED and the screening slip becomes available.', '{}'::text[], 12);
SELECT manual.seed('applicant-screening-slip', 'Print the screening slip', 'ADMISSIONS', ARRAY['applicant']::text[], 'a/screening', NULL,
    'Carry the slip to the screening or CBT.',
    ARRAY['Open {menu:a/screening}.',
          'Read the date, the centre, the room and the batch.',
          'Print the slip.'],
    'The slip carries the code the door checks.', '{}'::text[], 13);
SELECT manual.seed('applicant-putme-cbt', 'Sit the Post-UTME CBT', 'EXAMS', ARRAY['applicant']::text[], 'a/screening', NULL,
    'Take the examination on the day without a password.',
    ARRAY['Open the Post-UTME CBT page from the University website on the day.',
          'Enter your JAMB registration number and, only if the page asks for one, the verification detail it names (application number, slip code, phone or date of birth).',
          'Click `Verify candidate`; confirm your name and programme; tick the confirmation.',
          'Click `Start exam`; answer; click `SUBMIT EXAM`.',
          'No score is shown; the University releases scores later.'],
    'The attempt is submitted; `See your screening result` opens when scores are released.', '{}'::text[], 14);
SELECT manual.seed('applicant-score', 'Read the screening result', 'ADMISSIONS', ARRAY['applicant']::text[], 'a/score', NULL,
    'See the Post-UTME score when released.',
    ARRAY['Open {menu:a/score}.',
          'Read the score and whether it meets the programme''s cut-off.'],
    'The score is the one the Academic Office released.', '{}'::text[], 15);
SELECT manual.seed('applicant-status', 'Check the admission status', 'ADMISSIONS', ARRAY['applicant']::text[], 'a/status', NULL,
    'Know whether you are admitted, and to which programme.',
    ARRAY['Open {menu:a/status}.',
          'Pay the status-checking fee if the screen asks for it and return.',
          'Read the decision; click `Admission progress` for the stages that follow.'],
    'ADMITTED, NOT ADMITTED or still under consideration, with the next step named.', '{}'::text[], 16);
SELECT manual.seed('applicant-accept', 'Accept the offer and pay the acceptance fee', 'PAYMENTS', ARRAY['applicant']::text[], 'a/accept', NULL,
    'Secure the admission.',
    ARRAY['Open {menu:a/accept}.',
          'Read the undertaking and click `Accept the offer`.',
          'Click `Pay now` for the acceptance fee; pay on the gateway.',
          'Click `Clearance checklist`.'],
    'The offer is accepted and online screening opens.', '{}'::text[], 17);
SELECT manual.seed('applicant-clearance', 'Upload documents for online screening', 'ADMISSIONS', ARRAY['applicant']::text[], 'a/clearance', NULL,
    'Have your credentials cleared before school fees.',
    ARRAY['Open {menu:a/clearance}.',
          'For each item choose `Document to upload or replace`, pick the `File` and upload.',
          'Watch each item''s status; replace what is marked rejected.',
          'When every item reads cleared click `Next step: school fees`.'],
    'The Academic Office clears each document; school fees payment opens.', '{}'::text[], 18);
SELECT manual.seed('applicant-matric', 'Become a student', 'ADMISSIONS', ARRAY['applicant']::text[], 'a/matric', NULL,
    'Pay school fees and receive the matriculation number and student sign-in.',
    ARRAY['Open {menu:a/admission} and click `Pay school fees`; pay on the gateway.',
          'Open {menu:a/matric}.',
          'Read the matriculation number when issued and the student sign-in instructions.',
          'Sign in as a student with the matriculation number.'],
    'The student dashboard opens; the applicant account is closed.', '{}'::text[], 19);
SELECT manual.seed('pgapplicant-apply', 'Apply to the Postgraduate School', 'ADMISSIONS', ARRAY['pgapplicant']::text[], 'pg/apply', NULL,
    'File the postgraduate application and pay.',
    ARRAY['Open {menu:pg/apply}.',
          'Fill the pages (`Programme applied for`, personal details, the proposed research) and click `Next`.',
          'Click `Sign in to pay and continue application`; pay the application fee on the gateway.',
          'Upload each document asked for on the dashboard.',
          'Open {menu:pg/summary} to download the application summary.'],
    'The department reads the application; the School gives the final decision.', '{}'::text[], 10);
SELECT manual.seed('pgapplicant-status', 'Follow the postgraduate decision', 'ADMISSIONS', ARRAY['pgapplicant']::text[], 'pg/portal', NULL,
    'See the department''s recommendation and the School''s final admission.',
    ARRAY['Open {menu:pg/portal}.',
          'Read the stage: department recommendation, School decision, offer.',
          'Accept the offer and pay the acceptance fee when offered.'],
    'The offer is accepted; the student sign-in follows.', '{}'::text[], 11);
SELECT manual.seed('lecturer-teaching', 'See your courses and timetable', 'ACADEMICS', ARRAY['lecturer']::text[], 't/teaching', NULL,
    'Know what you teach this session and when.',
    ARRAY['Open {menu:t/teaching}.',
          'Choose the `Session`.',
          'Click a course for its class, slots and materials.'],
    'Every class allocated to you, with its timetable.', '{}'::text[], 10);
SELECT manual.seed('lecturer-class-list', 'Download the class list and take attendance', 'STUDENTS', ARRAY['lecturer']::text[], 'r/classlist', NULL,
    'Hold the register of the students registered for your course.',
    ARRAY['Open {menu:r/classlist}.',
          'Choose the course.',
          'Click `Download class list` or `Examination roll`.',
          'Click `Attendance register`; add the lecture (`Lecture date`, `Venue`), mark who is present (`All present` then untick absentees) and save.'],
    'The register is kept per lecture and the student sees it.', '{}'::text[], 11);
SELECT manual.seed('lecturer-score-sheet', 'Enter and attest a score sheet', 'RESULTS', ARRAY['lecturer']::text[], 't/scores', NULL,
    'Submit the course''s CA and examination scores into the result chain.',
    ARRAY['Open {menu:t/scores} and click `View` on the course.',
          'Click `Download the template`, fill it, then `Upload a completed sheet` — or type the scores on the screen.',
          'Click `Save the draft` while entering.',
          'Click `Download Validation Report` and correct what it flags.',
          'Click `Submit and attest`.'],
    'The sheet goes to the Head of Department; `Open the approval chain` shows where it is.', '{}'::text[], 20);
SELECT manual.seed('lecturer-held-scripts', 'Record held scripts', 'RESULTS', ARRAY['lecturer']::text[], 't/scores', NULL,
    'Name the students whose scripts are held so the sheet is not refused.',
    ARRAY['Open the score sheet under {menu:t/scores}.',
          'Click `Download the held-scripts template`, fill it and upload it on the sheet.',
          'Submit the sheet as usual.'],
    'Held students are marked and the sheet passes validation.', '{}'::text[], 21);
SELECT manual.seed('lecturer-sheet-history', 'Follow a submitted sheet', 'RESULTS', ARRAY['lecturer']::text[], 't/sheethistory', NULL,
    'See where each sheet is in the chain.',
    ARRAY['Open {menu:t/sheethistory}.',
          'Choose `Session`, `Semester` and `Standing`.',
          'Click the sheet to read the chain and any return note.'],
    'A returned sheet is reopened for correction from here.', '{}'::text[], 22);
SELECT manual.seed('lecturer-lms', 'Upload course material and set an assignment', 'ACADEMICS', ARRAY['lecturer']::text[], 't/lms', NULL,
    'Give the class materials and work.',
    ARRAY['Open {menu:t/lms} and click the course space.',
          'Click `Upload Material`, choose the file and upload.',
          'Create an assignment with its deadline; read submissions on the same screen.'],
    'Students see the material and submit under the deadline.', '{}'::text[], 12);
SELECT manual.seed('lecturer-queries', 'Answer a result query', 'RESULTS', ARRAY['lecturer']::text[], 't/scores', NULL,
    'Respond to a student''s query the Head referred to you.',
    ARRAY['Open the course''s sheet under {menu:t/scores}.',
          'Open the query listed on it; compare the script and the sheet.',
          'Write the answer and return it to the Head.'],
    'The Head closes the query with your answer.', '{}'::text[], 23);
SELECT manual.seed('lecturer-moderation-invigilation', 'Moderate questions and invigilate', 'EXAMS', ARRAY['lecturer']::text[], 't/moderation', NULL,
    'Approve another setter''s questions and run a hall.',
    ARRAY['Open {menu:t/moderation}; read each question awaiting; click `Approve` or `Return` with a note.',
          'Open {menu:t/invigilate} on the day; open the sitting; mark attendance and record incidents.'],
    'Approved questions may be drawn into a paper; the hall record is kept.', '{}'::text[], 30);
SELECT manual.seed('lecturer-self', 'Leave, payslip and profile', 'ACCOUNT', ARRAY['lecturer']::text[], 'r/self', NULL,
    'Read your payslip and apply for leave; keep your profile current.',
    ARRAY['Open {menu:r/self} for the payslip and leave application.',
          'Open {menu:t/myprofile}; edit and click `Save profile`.'],
    'HR receives the leave application; the profile is current.', '{}'::text[], 40);
SELECT manual.seed('result-pipeline', 'Monitor the result pipeline', 'RESULTS', ARRAY['hod', 'dean', 'exams', 'facultyexams', 'facultyofficer', 'records', 'dregistrar', 'super']::text[], 't/pipeline', NULL,
    'See every course''s sheet and the stage it has reached.',
    ARRAY['Open {menu:t/pipeline}.',
          'Choose the session and semester; narrow by faculty or department.',
          'Read each course''s stage (entered, attested, departmental, faculty, senate, published) and the days waiting.',
          'Click `Open the desk` on a stage to act, or `Download Excel` for the list.'],
    'Every late sheet is visible with who holds it.', '{}'::text[], 40);
SELECT manual.seed('broadsheet', 'Read or download a broadsheet', 'RESULTS', ARRAY['hod', 'dean', 'exams', 'facultyexams', 'facultyofficer', 'records', 'dregistrar', 'pgschool', 'pgsecretary']::text[], 't/broadsheet', NULL,
    'Have the programme''s results on one sheet.',
    ARRAY['Open {menu:t/broadsheet}.',
          'Choose the session, semester, programme and level.',
          'Click `Open sheet` on a course to see its sheet.',
          'Click `Download Excel` or `Download PDF`.'],
    'The broadsheet carries the University''s heading and a document serial.', '{}'::text[], 41);
SELECT manual.seed('approval-chain', 'Follow a sheet through the approval chain', 'RESULTS', ARRAY['hod', 'dean', 'exams', 'facultyexams', 'facultyofficer', 'records', 'academic', 'dregistrar', 'admin']::text[], 't/chain', NULL,
    'Know where one course''s sheet is and act at your stage.',
    ARRAY['Open {menu:t/chain}.',
          'Pick the sheet (`Open`).',
          'Read each stage, who acted and when.',
          'At your stage click `Approve and publish` or `Return to the lecturer` with the reason.'],
    'The sheet moves to the next stage or back to the lecturer with your note.', '{}'::text[], 42);
SELECT manual.seed('deferments-desk', 'Decide a deferment application', 'STUDENTS', ARRAY['hod', 'dean', 'academic', 'registrar', 'dregistrar', 'bursar', 'records', 'facultyofficer', 'pgschool', 'pgsecretary', 'super']::text[], 't/deferments', NULL,
    'Act on the applications waiting at your office.',
    ARRAY['Open {menu:t/deferments}.',
          'Filter by `Status / current office`, `Faculty`, `Department` or `Session`.',
          'Click `View` on an application; read the reason and the document.',
          'Approve or return it with a note.',
          'At the Registry click `Forward Approved Applications to DVC` with a `Covering note`.'],
    'The application moves to the next office; the student is told.', '{}'::text[], 60);
SELECT manual.seed('clearance-desk', 'Clear a student for graduation or a purpose', 'STUDENTS', ARRAY['hod', 'dean', 'academic', 'registrar', 'dregistrar', 'bursar', 'admin']::text[], 't/clearance', NULL,
    'Mark your unit''s clearance for the candidates listed.',
    ARRAY['Open {menu:t/clearance}.',
          'Choose the purpose and the session; tick the candidates.',
          'Click `Clear the selected candidates`, or `Hold` with `What is outstanding`.',
          'Click `Notify held candidates` to tell them; `Export the held list` for the office.'],
    'Each candidate''s clearance card shows your unit as CLEARED or HELD.', '{}'::text[], 61);
SELECT manual.seed('class-list', 'Download a class list or examination roll', 'STUDENTS', ARRAY['hod', 'dean', 'exams', 'academic']::text[], 'r/classlist', NULL,
    'Hold the register of a class.',
    ARRAY['Open {menu:r/classlist}.',
          'Choose the session, semester and course.',
          'Click `Download class list` or `Examination roll`.'],
    'The list is the registered students as approved.', '{}'::text[], 62);
SELECT manual.seed('records-queries', 'Answer a records query', 'STUDENTS', ARRAY['hod', 'dean', 'exams', 'facultyexams', 'facultyofficer', 'records', 'academic', 'registrar', 'dregistrar', 'bursar', 'housing', 'admin', 'super']::text[], 't/records', NULL,
    'Look up a student''s record and the queries raised to your office.',
    ARRAY['Open {menu:t/records}.',
          'Search the student by matriculation number or name.',
          'Open the query in the list; read the record beside it.',
          'Write the answer and close the query.'],
    'The student reads the answer on the portal.', '{}'::text[], 63);
SELECT manual.seed('student-statistics', 'Read student statistics', 'REPORTS', ARRAY['hod', 'academic', 'registrar', 'dregistrar', 'bursar', 'ict', 'admin', 'super', 'pgschool', 'pgsecretary']::text[], 't/studentstats', NULL,
    'Count students by faculty, programme, level, sex and state.',
    ARRAY['Open {menu:t/studentstats}.',
          'Choose the session and the breakdown.',
          'Click `Excel` or `PDF` to export.'],
    'Counts read from the live register.', '{}'::text[], 90);
SELECT manual.seed('hod-approve-sheets', 'Approve or return a score sheet (departmental)', 'RESULTS', ARRAY['hod']::text[], 't/approvals', NULL,
    'Give the department''s approval to an attested sheet.',
    ARRAY['Open {menu:t/approvals}.',
          'Click `Review` on the sheet; read the marks and the validation.',
          'Click `Approve`, or `Return` with `Why it is returned`.',
          'Click `Remind` to chase a lecturer whose sheet is late; `Escalate` when it stays late.'],
    'An approved sheet goes to the faculty; a returned one reopens for the lecturer.', '{}'::text[], 30);
SELECT manual.seed('hod-enter-on-behalf', 'Enter marks on a lecturer''s behalf', 'RESULTS', ARRAY['hod']::text[], 't/sheet', NULL,
    'Submit a sheet when the lecturer cannot.',
    ARRAY['Open {menu:t/scores} and click `View` on the course.',
          'Type the marks or click `Upload a completed sheet`.',
          'Click `Submit on the lecturer''s behalf` and give the reason.'],
    'The sheet enters the chain in your name, with the reason on the record.', '{}'::text[], 31);
SELECT manual.seed('hod-bulk-upload', 'Upload results in bulk', 'RESULTS', ARRAY['hod']::text[], 't/bulk', NULL,
    'Submit several courses'' sheets from one workbook.',
    ARRAY['Open {menu:t/bulk}.',
          'Click `Download the template`; fill one sheet per course.',
          'Click `Upload a completed sheet`; read the validation report.',
          'Submit the courses that validate.'],
    'Each course''s sheet is entered and attested in one pass.', '{}'::text[], 32);
SELECT manual.seed('hod-result-queries', 'Decide a student''s result query', 'RESULTS', ARRAY['hod']::text[], 't/queries', NULL,
    'Settle a query against a published mark.',
    ARRAY['Open {menu:t/queries}.',
          'Open the query; refer it to the lecturer or examine the script yourself.',
          'Enter the `Finding` and the `Answer`; click `Answer on the record`.',
          'Raise an amendment under {menu:t/chain} when the mark must change.'],
    'The student reads the answer; an amendment goes through the chain.', '{}'::text[], 33);
SELECT manual.seed('hod-amendment', 'Amend a published result', 'RESULTS', ARRAY['hod']::text[], 't/chain', NULL,
    'Correct a published mark through the chain.',
    ARRAY['Open {menu:t/chain} and open the course''s sheet.',
          'Click `Raise an amendment`; choose the `Student`, the `Outcome` and write `Why`.',
          'Click `Raise it`.',
          'Follow the amendment''s approvals on the same screen.'],
    'The mark changes only when every stage approves; the history is kept.', '{}'::text[], 34);
SELECT manual.seed('hod-courses', 'Create a course and make it live', 'ACADEMICS', ARRAY['hod']::text[], 't/deptcourses', NULL,
    'Add a course to the department''s catalogue.',
    ARRAY['Open {menu:t/deptcourses}.',
          'Click `Course`; enter `Code`, `Title`, `Units`, `Level`, `Semester` and `Kind`; click `Create`.',
          'Click `Make live` when the course may be offered.',
          'Click `Rename` to retitle, `End` to retire it.'],
    'The course is LIVE and may be bound to programmes and offered.', '{}'::text[], 10);
SELECT manual.seed('hod-offer-course', 'Offer a course to another department''s programme', 'ACADEMICS', ARRAY['hod']::text[], 't/deptcourses', NULL,
    'Let other programmes carry one of your courses, or propose carrying theirs.',
    ARRAY['Open {menu:t/deptcourses} and click `Open the course`.',
          'Click `+ Add Department / Programme`; choose the programme and write `Why those programmes should offer it`.',
          'The other Head reads the proposal and clicks `Approve` or `Reject`.'],
    'An approved offer binds the course to the programme''s structure.', '{}'::text[], 11);
SELECT manual.seed('hod-structure', 'Bind a course into the programme structure', 'ACADEMICS', ARRAY['hod']::text[], 't/structure', NULL,
    'Set what a level takes in a semester.',
    ARRAY['Open {menu:t/structure}.',
          'Choose the programme, `Level`, semester and `Track`.',
          'Pick the course and the `Basis` (core, elective); click `Bind the course`.',
          'Click `Remove` to unbind.'],
    'Registration offers the course to that level.', '{}'::text[], 12);
SELECT manual.seed('hod-allocate', 'Allocate teaching', 'ACADEMICS', ARRAY['hod']::text[], 'r/allocate', NULL,
    'Assign lecturers to the semester''s classes.',
    ARRAY['Open {menu:r/allocate}.',
          'Choose the session and semester.',
          'On a class use `Search a lecturer`, pick the lecturer and click `Assign`; `Add co-lecturer` for a second.',
          'Click `Save the lead & second examiner`.',
          'For many classes click `Download template`, fill it and `Upload Excel / CSV`.'],
    'The lecturer sees the class under My Courses; the sheet is theirs to enter.', '{}'::text[], 13);
SELECT manual.seed('hod-eligibility', 'See who may register a course', 'ACADEMICS', ARRAY['hod']::text[], 't/eligibility', NULL,
    'Check the rule that admits students to a course.',
    ARRAY['Open {menu:t/eligibility}.',
          'Choose the `Course` and `Department`.',
          'Read the levels, programmes and prerequisites that qualify.'],
    'The rule registration applies.', '{}'::text[], 14);
SELECT manual.seed('hod-transfers', 'Decide an inter-departmental transfer', 'STUDENTS', ARRAY['hod']::text[], 't/transfers', NULL,
    'Release or receive a student.',
    ARRAY['Open {menu:t/transfers}.',
          'Open the application; read the UTME score and the reason.',
          'Click `Approve` or `Decline`.',
          'Click `Record the application` for one brought on paper.'],
    'Both departments'' decisions go to the Registry.', '{}'::text[], 64);
SELECT manual.seed('hod-students', 'Read a student''s full record', 'STUDENTS', ARRAY['hod']::text[], 't/students', NULL,
    'Open the Student 360 for a student of the department.',
    ARRAY['Open {menu:t/students}.',
          'Search by matriculation number or name.',
          'Open the record: fees, registrations, results, standing, attendance.'],
    'The record within your department''s scope.', '{}'::text[], 65);
SELECT manual.seed('hod-pg-admissions', 'Recommend a postgraduate applicant', 'ADMISSIONS', ARRAY['hod', 'dean']::text[], 't/pgadmissions', NULL,
    'Give the department''s recommendation before the School decides.',
    ARRAY['Open {menu:t/pgadmissions}.',
          'Open the applicant; read the credentials and the proposal.',
          'Enter the recommendation and submit it.'],
    'The School of Postgraduate Studies gives the final admission.', '{}'::text[], 70);
SELECT manual.seed('dean-faculty-board', 'Approve sheets at the Faculty Board', 'RESULTS', ARRAY['dean']::text[], 't/approvals', NULL,
    'Give the faculty''s approval to the departments'' sheets.',
    ARRAY['Open {menu:t/approvals}.',
          'Click `Review` on a sheet; read the broadsheet beside it.',
          'Click `Approve`, or `Return` with `Why it is returned`.',
          'Click `Escalate` on a department that is late.'],
    'Approved sheets go to Senate business; returned ones go back to the department.', '{}'::text[], 30);
SELECT manual.seed('dean-graduation', 'Prepare the graduation list', 'ACADEMICS', ARRAY['dean', 'academic', 'records', 'pgschool', 'pgsecretary']::text[], 't/graduation', NULL,
    'Review the candidates for the award and send them to Senate.',
    ARRAY['Open {menu:t/graduation}.',
          'Choose the session and programme; click `Review`.',
          'Click `Open the exception list` and settle each exception.',
          'Click `Approve the awards`, then `Send the list to Senate` with the `Senate minute`.'],
    'The list is with Senate; certificates follow its minute.', '{}'::text[], 35);
SELECT manual.seed('dean-examiners', 'Appoint and assign external examiners', 'EXAMS', ARRAY['dean', 'hod', 'exams', 'academic', 'registrar', 'dregistrar', 'pgschool', 'pgsecretary', 'admin', 'super']::text[], 't/extexaminers', NULL,
    'Bring an external examiner onto the portal and give them projects.',
    ARRAY['Open {menu:t/extexaminers}; add the examiner (name, e-mail, institution).',
          'Open {menu:t/extappointments}; appoint them for the session.',
          'Open {menu:t/extassignments}; assign the projects.',
          'Read the assessments under {menu:t/extassessments} and the reports under {menu:t/extreports}.'],
    'The examiner activates the account by e-mail and sees only the assigned projects.', '{}'::text[], 80);
SELECT manual.seed('dean-budget', 'Read the faculty budget and requisitions', 'REPORTS', ARRAY['dean']::text[], 't/budget', NULL,
    'Follow the faculty''s money.',
    ARRAY['Open {menu:t/budget} for the budget lines and what is spent.',
          'Open {menu:t/requisitions} to raise or follow a requisition.'],
    'The Bursary acts on the requisition.', '{}'::text[], 91);
SELECT manual.seed('exams-verification', 'Verify a sheet (Verification Queue)', 'RESULTS', ARRAY['exams']::text[], 't/approvals', NULL,
    'Check an attested sheet before the department approves it.',
    ARRAY['Open {menu:t/approvals}.',
          'Click `Review`; compare the sheet with the examination roll and the validation report.',
          'Click `Approve`, or `Return` with `Why it is returned`.'],
    'A verified sheet waits for the Head of Department.', '{}'::text[], 30);
SELECT manual.seed('exams-on-behalf', 'Upload a score sheet on a lecturer''s behalf', 'RESULTS', ARRAY['exams']::text[], 't/scores', NULL,
    'Enter a sheet the lecturer cannot.',
    ARRAY['Open {menu:t/scores} and click `View` on the course.',
          'Click `Upload a completed sheet` or type the marks.',
          'Click `Submit on the lecturer''s behalf` with the reason.'],
    'The sheet enters the chain in your name.', '{}'::text[], 31);
SELECT manual.seed('exams-sessions', 'Open an examination session and release cards and sheets', 'EXAMS', ARRAY['exams', 'facultyexams']::text[], 't/exams', NULL,
    'Set the examination dates and release the examination cards and the score sheets.',
    ARRAY['Open {menu:t/exams}.',
          'Click `Open the session`; set `Academic session`, `Semester`, `Examinations begin`, `Examinations end` and `Score sheets due`; click `Save the dates`.',
          'Click `Release examination cards` when registration closes.',
          'Click `Release score sheets` so lecturers may enter marks.',
          'Click `Monitor`; `Remind` or `Escalate` late sheets.'],
    'Students print cards; lecturers see their sheets; late sheets are chased.', '{}'::text[], 10);
SELECT manual.seed('exams-cbt-courses', 'Allow a course to be examined by CBT', 'EXAMS', ARRAY['exams', 'facultyexams', 'records', 'academic', 'registrar', 'dregistrar']::text[], 't/cbtcourses', NULL,
    'Put a course on the CBT engine.',
    ARRAY['Open {menu:t/cbtcourses}.',
          'Search the course; click `Allow CBT`.',
          'Click `Withdraw` to take it off.'],
    'The course''s bank and examinations open under CBT Examinations.', '{}'::text[], 11);
SELECT manual.seed('exams-cbt-exam', 'Create and publish a CBT examination', 'EXAMS', ARRAY['exams', 'facultyexams']::text[], 't/unicbt', NULL,
    'Examine a CBT course on the engine.',
    ARRAY['Open {menu:t/cbtbank}; choose the course; click `Import` (the template is downloaded there) or `Add to the bank`; another officer clicks `Approve` on each question.',
          'Open {menu:t/unicbt}; click `Create examination`; choose the class, the number of questions, duration, window and rules.',
          'On the examination click `Pick every approved active question` or set the blueprint; click `Save the paper`.',
          'Click `Add a sitting` and `Invigilators` where halls are used; `Print slips`.',
          'Click `Publish to candidates`; the paper is frozen.',
          'On the day click `Live monitor`; after it `Close now`, `Complete`, then under results `Start the review`, `Approve` and `Publish to students` or `Send to the score sheet`.'],
    'Students sit in the room; approved results reach the course''s sheet.', '{}'::text[], 12);
SELECT manual.seed('exams-queries', 'Follow result queries of the programme', 'RESULTS', ARRAY['exams']::text[], 't/queries', NULL,
    'See every query and its state.',
    ARRAY['Open {menu:t/queries}.',
          'Filter `All`; open a query to read the finding and the answer.'],
    'Queries the Head answered are on the record.', '{}'::text[], 32);
SELECT manual.seed('facultyexams-scrutiny', 'Scrutinise sheets at the faculty desk', 'RESULTS', ARRAY['facultyexams']::text[], 't/resultdesk', NULL,
    'Check the departments'' sheets before the Faculty Board.',
    ARRAY['Open {menu:t/resultdesk}.',
          'Click `Open` on a sheet; read the marks against the broadsheet.',
          'Click `Open the approval chain` to approve or return with a note.'],
    'The Board sees only scrutinised sheets.', '{}'::text[], 30);
SELECT manual.seed('facultyofficer-desk', 'Read the faculty''s result desk and registers', 'RESULTS', ARRAY['facultyofficer']::text[], 't/resultdesk', NULL,
    'Follow the faculty''s sheets and keep its registers.',
    ARRAY['Open {menu:t/resultdesk}; click `Open` on a sheet to read it.',
          'Open {menu:t/regstudents} or {menu:t/regstaff}; filter and click `Print / Save as PDF`.'],
    'Registers print with the University''s heading.', '{}'::text[], 30);
SELECT manual.seed('facultyofficer-matric', 'Prepare matriculation for the faculty', 'STUDENTS', ARRAY['facultyofficer']::text[], 't/matriculation-manage', NULL,
    'Mark the faculty''s students ready for matriculation numbers.',
    ARRAY['Open {menu:t/matriculation-manage}.',
          'Choose `Academic session` and `Faculty`; click `Load`.',
          'Click `Validate`; correct what fails (`Edit`, `Save the correction`).',
          'Click `Mark ready for issuance`.'],
    'The Academic Office issues the numbers.', '{}'::text[], 31);
SELECT manual.seed('records-validation-desk', 'Validate sheets at the Validation Desk', 'RESULTS', ARRAY['records']::text[], 't/resultdesk', NULL,
    'Check sheets approved by the faculties before Senate.',
    ARRAY['Open {menu:t/resultdesk}.',
          'Click `Open` on a sheet; read it against the broadsheet.',
          'Click `Open the approval chain` to approve or return.'],
    'Validated sheets are listed for the Senate schedule.', '{}'::text[], 30);
SELECT manual.seed('records-senate', 'Record the Senate minute and release results', 'RESULTS', ARRAY['records', 'dregistrar']::text[], 't/senate', NULL,
    'Release a faculty''s results on Senate''s authority.',
    ARRAY['Open {menu:t/senate}.',
          'Choose the session, semester and `Faculty`.',
          'Enter the `Minute number`.',
          'Click `Record the minute and release` (or `Record the minute` alone).',
          'Click `Open publication`.'],
    'Results are published to students; the minute is on every sheet.', '{}'::text[], 31);
SELECT manual.seed('records-publication', 'Publish results', 'RESULTS', ARRAY['records']::text[], 't/publish', NULL,
    'Make released results visible to students.',
    ARRAY['Open {menu:t/publish}.',
          'Read what is released and not yet published.',
          'Publish; students are told.'],
    'Students read the results under Results.', '{}'::text[], 32);
SELECT manual.seed('records-transcripts', 'Produce and release a transcript', 'ACADEMICS', ARRAY['records', 'academic', 'registrar', 'dregistrar']::text[], 't/transcripts', NULL,
    'Answer a transcript request.',
    ARRAY['Open {menu:t/transcripts}.',
          'Open the request; click `Record payment` if paid outside the gateway.',
          'Click `Produce & verify`; read the transcript.',
          'Click `Sign & release`; the student''s `View verification` link works from then.'],
    'The transcript is issued, serialled and verifiable.', '{}'::text[], 50);
SELECT manual.seed('records-certificates', 'Print certificates', 'ACADEMICS', ARRAY['records', 'academic', 'registrar']::text[], 't/certificates', NULL,
    'Print a graduand''s certificate on a stationery batch.',
    ARRAY['Open {menu:t/certificates}.',
          'Click `Record the batch`: `Stationery batch`, `First serial`, `Last serial`, `Received on`.',
          'Pick the `Graduand`; click `Print a certificate`.',
          'Click `Collected` when handed over, `Spoiled one` for a misprint, `Reissue` for a replacement.'],
    'Every serial is accounted for.', '{}'::text[], 51);
SELECT manual.seed('records-documents-office', 'Run the Documents Office', 'ACADEMICS', ARRAY['records', 'academic', 'registrar', 'dregistrar']::text[], 't/documents', NULL,
    'Issue the documents students request.',
    ARRAY['Open {menu:t/documents}.',
          'Open `Requests`; click `Review` on a request.',
          'Click `Issue` (or `Record` for one issued on paper).',
          'Read `Issued documents`; set `Policies & templates` for fees and wording.'],
    'The student is told and the document verifies on the public page.', '{}'::text[], 52);
SELECT manual.seed('records-migration', 'Migrate records from the old portal', 'SETTINGS', ARRAY['records', 'ict']::text[], 't/legacy', NULL,
    'Bring old-portal students, results and payments over.',
    ARRAY['Open {menu:t/legacy}.',
          'Choose the kind of file; click `Download template` and fill it from the old portal''s export.',
          'Upload; read the preview and the errors.',
          'Commit the rows that validate.'],
    'The records exist on the new portal with their old references.', '{}'::text[], 95);
SELECT manual.seed('records-cohorts', 'Keep student cohorts', 'STUDENTS', ARRAY['records', 'academic', 'registrar', 'dregistrar', 'ict', 'admin', 'super']::text[], 't/cohorts', NULL,
    'See each student''s expected completion and correct a cohort.',
    ARRAY['Open {menu:t/cohorts}.',
          'Search; read `Effective cohort`, `Length in sessions` and `Issue`.',
          'Click `Set the Cohort` or `Set the Length` with the reason; `Recompute` after a change.'],
    'Positions and graduation lists follow the cohort.', '{}'::text[], 66);
SELECT manual.seed('adm-settings', 'Set the admission rules for a session', 'ADMISSIONS', ARRAY['academic']::text[], 't/admissionsetup', NULL,
    'State each programme''s cut-off, UTME subjects, O''Level subjects and quota.',
    ARRAY['Open {menu:t/admissionsetup}.',
          'Choose the session; click `New rule`; choose the `Programme`.',
          'Enter `Cut-off of its own`, tick the `Required UTME subjects`, choose the `Relevant O''Level subjects` and the `Programme quota`; enter the `Central Admissions Committee minute`.',
          'Click `State the rule`.',
          'Click `Save the catchment` and `Save the equivalencies` for the session''s catchment states and grade equivalencies.'],
    'The merit list and the eligibility engine apply the rule from then on.', '{}'::text[], 10);
SELECT manual.seed('adm-caps-upload', 'Upload the JAMB (CAPS) list', 'ADMISSIONS', ARRAY['academic']::text[], 't/capsintake', NULL,
    'Bring the session''s candidates in as JAMB sent them.',
    ARRAY['Open {menu:t/capsintake}.',
          'Choose the session; upload the CAPS file; read the counts (Loaded, new programmes named).',
          'Correct a programme name the University calls differently (`Edit this programme''s name`, `Save the programme`).',
          'Click `Commit`.',
          'Click `Withdraw the list` with `Why the list is withdrawn` if a wrong file was committed.'],
    'Candidates exist with their JAMB data; nothing is built on a withdrawn list.', '{}'::text[], 11);
SELECT manual.seed('adm-candidate-data', 'Upload passports, dates of birth and O''Level results', 'ADMISSIONS', ARRAY['academic']::text[], 't/candidatedata', NULL,
    'Attach the candidate data the admission needs.',
    ARRAY['Open {menu:t/candidatedata}.',
          'Choose the kind of file (passport, date of birth, O''Level) and upload it.',
          'Read what was read and what failed; click `Record what was read`.',
          'Under O''Level duplicates click `Keep on record` or `Use uploaded` with `How it was verified`.'],
    'The candidates carry the data; eligibility reads it.', '{}'::text[], 12);
SELECT manual.seed('adm-load-cutoff', 'Change the general UTME cut-off for loading', 'ADMISSIONS', ARRAY['academic']::text[], 't/capsintake', NULL,
    'Set the score below which a candidate is not loaded.',
    ARRAY['Open {menu:t/capsintake}.',
          'Under the cut-off panel enter `General UTME cut-off for loading`.',
          'Click `Change the cut-off`.'],
    'The next list loads only candidates at or above it.', '{}'::text[], 13);
SELECT manual.seed('adm-putme-schedule', 'Schedule the Post-UTME screening and the check-in', 'ADMISSIONS', ARRAY['academic', 'registrar', 'dregistrar', 'records', 'ict', 'admin', 'super']::text[], 't/putme-cbt', NULL,
    'Put candidates in centres, rooms and batches, publish the slips and run the door.',
    ARRAY['Open {menu:t/putme-cbt}.',
          'Click `Set up the examination`; enter the centres, rooms, capacity, dates and the fee.',
          'Click `Generate Batches`; read the counts.',
          'Click `Publish Schedule`; candidates print their slips.',
          'On the day click `Check-in Desk`; after it `Mark completed`.'],
    'Every submitted applicant has a batch; the door admits by slip.', '{}'::text[], 14);
SELECT manual.seed('adm-putme-scores-upload', 'Upload Post-UTME scores', 'ADMISSIONS', ARRAY['academic']::text[], 't/putme', NULL,
    'Enter screening scores from a sheet.',
    ARRAY['Open {menu:t/putme}.',
          'Choose `Session` and `Programme`; click `Download template` (or `Download all awaiting`).',
          'Fill the scores; click `Load a CSV`.',
          'Click `Score remaining as zero` for absentees if the policy says so.',
          'Click `Release scores`.'],
    'Applicants read their scores; the merit list uses them.', '{}'::text[], 15);
SELECT manual.seed('adm-putme-score-files', 'Receive and import a Post-UTME CBT score file', 'ADMISSIONS', ARRAY['academic']::text[], 't/putmefiles', NULL,
    'Take the Directorate of ICT''s official score file into the screening scores.',
    ARRAY['Open {menu:t/putmefiles}.',
          'Open the file sent; click `Confirm receipt`; click `Download` to keep a copy.',
          'Click `Preview & import`; read each line (NEW, SAME, DIFFERENT, RELEASED, NOT FOUND).',
          'Choose Keep or Replace (a reason is required to replace) and click `Confirm import`.',
          'Click `Release scores` when the session''s scores are complete.'],
    'Scores are entered once; a released score is never overwritten.', '{}'::text[], 16);
SELECT manual.seed('adm-eligibility', 'Recalculate programme eligibility', 'ADMISSIONS', ARRAY['academic', 'registrar']::text[], 't/admeligibility', NULL,
    'Check every applicant against the programme''s rule.',
    ARRAY['Open {menu:t/admeligibility}.',
          'Choose the session; filter by `Faculty`, `Department` or `Eligibility`.',
          'Click `Recalculate all` (or `Recalculate` on one).',
          'Click `View Eligibility Details` on an applicant to read why.',
          'Click `Request Change` with the `Recommended programme` and `Reason for change` when another programme fits; `Record the request`.'],
    'Each applicant reads ELIGIBLE or the rule missed; change requests go to Programme Changes.', '{}'::text[], 17);
SELECT manual.seed('adm-merit-list', 'Run the merit list and propose offers', 'ADMISSIONS', ARRAY['academic']::text[], 't/merit', NULL,
    'Rank the eligible candidates of a programme and propose admissions within the quota.',
    ARRAY['Open {menu:t/merit}.',
          'Choose the session and the `Programme`.',
          'Read the pool, the eligible and the proposed counts.',
          'Record the merit list against the programme; the proposed offers are listed.'],
    'Proposed offers wait for release under Offers & Waiting List.', '{}'::text[], 18);
SELECT manual.seed('adm-offers', 'Release offers and keep the waiting list', 'ADMISSIONS', ARRAY['academic']::text[], 't/offers', NULL,
    'Give offers a deadline, lapse the unanswered and promote from the waiting list.',
    ARRAY['Open {menu:t/offers}.',
          'Set `Accept by` or `Days after release`; release the offers.',
          'After the deadline click `Lapse them` (`On the authority of` the minute).',
          'Click `Promote` on the waiting list to fill the places.'],
    'Applicants read their offer; lapsed places go to the next in line.', '{}'::text[], 19);
SELECT manual.seed('adm-screening-review', 'Review an applicant''s screening', 'ADMISSIONS', ARRAY['academic', 'registrar']::text[], 't/screeningreview', NULL,
    'Clear or return the documents an applicant uploaded.',
    ARRAY['Open {menu:t/screeningreview}.',
          'Set `Required documents`, `Required fields` and `Instructions shown on the form`; click `Save the policy`.',
          'Open an applicant; click `Mark in review`.',
          'Click `Approve screening`, `Request correction` or `Return to the applicant`, with `Officer''s remarks`; `Unsuccessful` to end it.',
          'Click `Change course / programme` to recommend another programme.'],
    'The applicant is told and proceeds to school fees when approved.', '{}'::text[], 20);
SELECT manual.seed('adm-programme-changes', 'Decide a programme change', 'ADMISSIONS', ARRAY['academic', 'registrar', 'dregistrar', 'bursar', 'super']::text[], 't/programmechanges', NULL,
    'Correct an admission to another programme.',
    ARRAY['Open {menu:t/programmechanges}.',
          '`Find` the applicant; read `Programme applied for` and `What was found in error`.',
          'Click `Recommend the correction` (`Correct the admission to`, `Reason`).',
          'The deciding office clicks `Approve` or `Reject`.'],
    'The admission reads the new programme; the history is kept.', '{}'::text[], 21);
SELECT manual.seed('adm-de-screening', 'Screen Direct Entry candidates', 'ADMISSIONS', ARRAY['academic']::text[], 't/de-screening', NULL,
    'Record the Direct Entry decision.',
    ARRAY['Open {menu:t/de-screening}.',
          'Open the candidate; read the credentials uploaded.',
          'Enter the decision and the score where applicable.'],
    'The candidate proceeds like a UTME applicant.', '{}'::text[], 22);
SELECT manual.seed('adm-reports', 'Report on Post-UTME registration and admissions', 'REPORTS', ARRAY['academic']::text[], 't/applicants', NULL,
    'Count applicants and admissions by programme.',
    ARRAY['Open {menu:t/applicants} for the registration report; filter and export.',
          'Open {menu:t/admissions} for the admissions report.'],
    'Counts read from the live applications.', '{}'::text[], 23);
SELECT manual.seed('adm-admitted-list', 'Read the admitted list and download the list for JAMB', 'ADMISSIONS', ARRAY['registrar']::text[], 't/applicants', NULL,
    'Hold the admitted list and send it to JAMB.',
    ARRAY['Open {menu:t/applicants}.',
          'Filter by `Faculty`, `Programme` or `Entry mode`.',
          'Open {menu:t/admissions}; choose `Programme to export`; click `Download for JAMB`.'],
    'The file is in JAMB''s format.', '{}'::text[], 24);
SELECT manual.seed('adm-checking-window', 'Open admission status checking', 'ADMISSIONS', ARRAY['academic', 'registrar', 'ict', 'admin']::text[], 't/admissionchecking', NULL,
    'Let applicants check their status (and set the fee).',
    ARRAY['Open {menu:t/admissionchecking}.',
          'Choose the session; click `Open now` (or `Schedule` with `Opens` and `Closes`), with the `Reason`.',
          'Click `Extend`, `Shorten` or `Close now` later; `Record` an act done on paper.'],
    'Applicants see Admission Status; the fee is charged where set.', '{}'::text[], 25);
SELECT manual.seed('matric-format', 'Set the matriculation number format', 'STUDENTS', ARRAY['academic', 'registrar', 'dregistrar']::text[], 't/matriculation-config', NULL,
    'Define the series, segments and sequence of the numbers.',
    ARRAY['Open {menu:t/matriculation-config}.',
          'Click `Add a series`; enter `Name`, `University code`, `Segment after the University code`, `Separator` and `Sequence padding`; click `Save the rule`.',
          'Set `Last number issued` where a series continues from the old portal.',
          'Click `Open Matriculation Management`.'],
    'Numbers are issued in that format.', '{}'::text[], 30);
SELECT manual.seed('matric-issue', 'Issue matriculation numbers', 'STUDENTS', ARRAY['academic', 'registrar', 'dregistrar']::text[], 't/matriculation-manage', NULL,
    'Give the session''s new students their numbers.',
    ARRAY['Open {menu:t/matriculation-manage}.',
          'Choose `Academic session` and `Faculty`; click `Load`.',
          'Click `Validate`; correct what fails (`Edit`, `Save the correction`); `Drop from the batch` what must wait.',
          'Click `Mark ready for issuance`, then `Final review & issue`.',
          'Click `Confirm & Issue Matriculation Numbers`.',
          'Click `Broadcast` to tell the students; `Issued list` for the register; `Retry failed` if any failed.'],
    'Each student reads the number on the dashboard and signs in with it.', '{}'::text[], 31);
SELECT manual.seed('student-records-360', 'Read and correct a student record', 'STUDENTS', ARRAY['academic', 'registrar', 'dregistrar', 'ict', 'admin']::text[], 't/students', NULL,
    'Open the Student 360 and act on the record.',
    ARRAY['Open {menu:t/students}.',
          'Search by matriculation number or name; open the student.',
          'Read fees, registrations, results, standing, attendance and documents.',
          'Change the status or level where your office may, with the `Instrument` and `Reason`.'],
    'The record changes with the reason on the audit trail.', '{}'::text[], 32);
SELECT manual.seed('biodata-changes', 'Approve a biodata change', 'STUDENTS', ARRAY['academic', 'registrar']::text[], 't/biochange', NULL,
    'Decide a student''s request to correct a locked field.',
    ARRAY['Open {menu:t/biochange}.',
          'Open the request; read the evidence attached.',
          'Write `The decision, in words`; click `Approve with evidence` (or `Approve and write it on`), or reject.'],
    'The record changes and the student is told.', '{}'::text[], 33);
SELECT manual.seed('unpaid-registrations', 'List unpaid registrations', 'STUDENTS', ARRAY['academic', 'registrar', 'dregistrar', 'bursar']::text[], 't/unpaidreg', NULL,
    'See who registered without the fee in full.',
    ARRAY['Open {menu:t/unpaidreg}.',
          'Choose the `Session`.',
          'Export or act on the list.'],
    'Every registration with fees outstanding.', '{}'::text[], 34);
SELECT manual.seed('results-to-senate', 'Take results to Senate', 'RESULTS', ARRAY['academic', 'registrar']::text[], 't/approvals', NULL,
    'Approve the faculties'' results for Senate and record the minute.',
    ARRAY['Open {menu:t/approvals}.',
          'Click `Review` on a faculty''s business; `Approve` or `Return`.',
          'Click `Record Senate minute` with the number.'],
    'Results are released on the minute.', '{}'::text[], 40);
SELECT manual.seed('college-chs', 'Work the College of Health Sciences desk', 'ACADEMICS', ARRAY['academic', 'registrar', 'records', 'super']::text[], 't/college', NULL,
    'Manage the MBBS programme''s own payments, screening and results.',
    ARRAY['Open {menu:t/college}.',
          'Choose the tab (students, payments, examinations).',
          'Act as the College''s workflow names.'],
    'The College''s records are kept apart from the faculties''.', '{}'::text[], 41);
SELECT manual.seed('reports-returns', 'Run a report or a return', 'REPORTS', ARRAY['academic', 'registrar', 'dregistrar', 'bursar', 'records', 'facultyofficer', 'pgschool', 'pgsecretary']::text[], 't/reports', NULL,
    'Produce a statutory return or a listed report.',
    ARRAY['Open {menu:t/reports}.',
          'Click `Run` on the report; set the filters.',
          'Click `Open` to read it; export it.'],
    'The report prints with the University''s heading and a serial.', '{}'::text[], 90);
SELECT manual.seed('staff-upload', 'Upload non-academic staff', 'SETTINGS', ARRAY['registrar', 'dregistrar', 'super']::text[], 't/staffupload', NULL,
    'Bring staff onto the register from a sheet.',
    ARRAY['Open {menu:t/staffupload}.',
          'Click `Download Template`; fill it.',
          'Upload; read what was created and what failed.'],
    'Staff exist with staff numbers and may be granted offices.', '{}'::text[], 91);
SELECT manual.seed('registrar-staff', 'Keep staff records and recruitment', 'SETTINGS', ARRAY['registrar']::text[], 't/staff', NULL,
    'Read staff records and follow recruitment.',
    ARRAY['Open {menu:t/staff}; search a staff member; read the record.',
          'Open {menu:t/recruit} for recruitment exercises.'],
    'The staff register is current.', '{}'::text[], 92);
SELECT manual.seed('registrar-audit', 'Read the audit trail', 'SETTINGS', ARRAY['registrar', 'ict', 'admin', 'super', 'dsa']::text[], 't/audit', NULL,
    'See who did what, when, with what reason.',
    ARRAY['Open {menu:t/audit}.',
          'Filter by `Domain`, `Acting office`, person or date.',
          'Open an entry to read the before and after.'],
    'Every write is on the chain with its reason.', '{}'::text[], 93);
SELECT manual.seed('bursar-fee-schedule', 'Set the fee schedule for a session', 'PAYMENTS', ARRAY['bursar']::text[], 't/feesetup', NULL,
    'State every fee line by programme, level and entry mode and put the schedule in force.',
    ARRAY['Open {menu:t/feesetup}.',
          'Choose the session; click `Add an item`; enter the `Amount` and `Channel`; `State the item`.',
          'Click `State the applicant fees` (application, acceptance, admission checking), `State the deferment fee`, `State the postgraduate fees` and `Set the transfer fee`.',
          'Click `Put in force` (or `Put the recommended scheme in force` for the instalment scheme).',
          'Click `Download Excel` or `Download PDF` for the published schedule.'],
    'Students see the fee lines that apply to them; registration refuses when none applies.', '{}'::text[], 10);
SELECT manual.seed('bursar-gst-fee', 'Set the GST/EPS fee and its refunds', 'PAYMENTS', ARRAY['bursar']::text[], 't/feesetup', NULL,
    'State the fee a GST or EPS course requires and decide refunds.',
    ARRAY['Open {menu:t/feesetup} and the GST fee panel.',
          'Enter `GST fee (₦)`, `Effective from`, and the `Faculty`, `Programme`, `Level` or `Entry mode` it applies to; click `Save the rule`.',
          'On a refund proposed by the engine click `Refund` or `Keep` with the `Reason`; `Propose the refund` for one found by hand.'],
    'The fee is owed only for a course that runs and is owed; refunds go through the Refunds desk.', '{}'::text[], 11);
SELECT manual.seed('bursar-hostel-fee', 'State hostel fees', 'PAYMENTS', ARRAY['bursar']::text[], 't/hostel-finance', NULL,
    'Set the accommodation fee by hostel, room type and category.',
    ARRAY['Open {menu:t/hostel-finance}.',
          'Click `State the fee rule`; choose `Session`, `Hostel`, `Room type`, `Category`, `Level`; enter `Fee (₦)`.',
          'Click `End` on a rule no longer in force.'],
    'Hostel applications charge the rule''s fee.', '{}'::text[], 12);
SELECT manual.seed('bursar-jupeb-cce-fees', 'State JUPEB and CCE fees', 'PAYMENTS', ARRAY['bursar']::text[], 'f/jupebfees', NULL,
    'Set the application, checking, acceptance and school fees of JUPEB and the CCE.',
    ARRAY['Open {menu:f/jupebfees}; enter `Application fee (₦)`, `Admission status checking fee (₦)`, `Acceptance fee (₦)`, the school fee and `First semester share (%)`; save.',
          'Open {menu:cce/fees} for the CCE applicant fees and {menu:cce/school-fees} for the CCE school fee lines.'],
    'Each route charges its own lines and nothing of the University''s.', '{}'::text[], 13);
SELECT manual.seed('bursar-payments-query', 'Query payments and export the report', 'PAYMENTS', ARRAY['bursar']::text[], 't/payments', NULL,
    'Find transactions by student, programme, channel, category or period.',
    ARRAY['Open {menu:t/payments}.',
          'Filter by `Session`, `Payment category`, `Channel`, `Faculty`, `Department`, `Programme`, `Level` or `From`.',
          'Click `Export Excel` or `Export PDF`.'],
    'The list is the ledger''s; every row carries its gateway reference.', '{}'::text[], 20);
SELECT manual.seed('bursar-verify-payment', 'Verify a payment with the gateway', 'PAYMENTS', ARRAY['bursar']::text[], 't/gateways', NULL,
    'Confirm a reference the gateway holds but the portal does not show paid.',
    ARRAY['Open {menu:t/gateways}.',
          'Under `Ask about a reference` enter the reference; click `Ask the gateway now` (or `Verify with the gateway`).',
          'Read the answer; the payment posts when the gateway confirms it.',
          'Click `Run the sweep now` to re-ask every pending reference.'],
    'A confirmed payment reads PAID on the student''s record.', '{}'::text[], 21);
SELECT manual.seed('bursar-hanging', 'Resolve a hanging payment', 'PAYMENTS', ARRAY['bursar']::text[], 't/hanging', NULL,
    'Settle a payment the gateway confirmed that matched nothing.',
    ARRAY['Open {menu:t/hanging}.',
          'Open the payment; click `Ask the gateway` to re-read it.',
          'Click `Resolve`: match it to the student and the fee line.'],
    'The payment is on the student''s record with its original reference.', '{}'::text[], 22);
SELECT manual.seed('bursar-exceptions', 'Record a bank payment and post a credit', 'PAYMENTS', ARRAY['bursar']::text[], 't/exception', NULL,
    'Enter a payment made at the bank or by draft.',
    ARRAY['Open {menu:t/exception}.',
          'Click `Propose`; enter `Teller slip or draft number`, `Bank`, `Amount`, `Received on`, `Payer named on the slip` and a `Note`.',
          'A second officer clicks `Approve and post` (or `Reject`).',
          'Click `Record the credit` where a credit is agreed.'],
    'The credit posts on two signatures and the student reads it.', '{}'::text[], 23);
SELECT manual.seed('bursar-refunds', 'Raise and approve a refund', 'PAYMENTS', ARRAY['bursar']::text[], 't/refunds', NULL,
    'Return money to a student or a sponsor.',
    ARRAY['Open {menu:t/refunds}.',
          'Click `Raise it` (`From a payment reference` fills the amount); enter `Paid to`, `Bank`, `Account name`, `Account (last 4)`, `Reason`.',
          'A second officer clicks `Approve` (`Awaiting another approver` until then) or `Reject`.',
          'Click `Mark paid` when the bank has paid.'],
    'The refund is on the ledger against the original payment.', '{}'::text[], 24);
SELECT manual.seed('bursar-nelfund', 'Load NELFUND and other funding into wallets', 'PAYMENTS', ARRAY['bursar']::text[], 't/nelfund', NULL,
    'Credit students'' wallets from a sponsor''s list and reconcile remittances.',
    ARRAY['Open {menu:t/nelfund}.',
          'Click `Save the source` for a new sponsor (`Code`, `Name`, `Nature`, `Holding account`).',
          'Click `Download template`, fill the list, `Load the list` then `Load and match`.',
          'Click `Credit the wallet` on matched rows; `Reverse` with a `Reason` to undo.',
          'Open {menu:t/nelmatch} to match a bank remittance to the credits.'],
    'Each wallet holds the money by source; fees draw on it in order.', '{}'::text[], 25);
SELECT manual.seed('bursar-legacy', 'Upload the old portal''s fees history', 'PAYMENTS', ARRAY['bursar']::text[], 't/legacyfees', NULL,
    'Bring past payments over so balances are right.',
    ARRAY['Open {menu:t/legacyfees}.',
          'Click `Download template`; fill it from the old portal''s export (keep the Purpose column).',
          'Upload; click `Show what is loaded`; `Resume from the failed batch` if it stopped.',
          'Open {menu:t/legacygst} to reconcile old GST rows (`Dry run`, `Stage these rows`, `Reconcile`).'],
    'Old payments appear on the students'' records with their references.', '{}'::text[], 26);
SELECT manual.seed('bursar-interswitch-test', 'Issue an Interswitch test reference', 'PAYMENTS', ARRAY['bursar']::text[], 't/gateways', NULL,
    'Give the gateway a reference to certify Quickteller.',
    ARRAY['Open {menu:t/gateways}; open the Interswitch test references panel.',
          'Choose the `Student`, the `Amount (₦)` and `Payable for` (days); click `Issue a test reference`.',
          'Click `Copy` and send it to the gateway; `Withdraw` when done.'],
    'The gateway''s validation answers for the days chosen; nothing else changes.', '{}'::text[], 27);
SELECT manual.seed('bursar-financial-clearance', 'Give financial clearance', 'STUDENTS', ARRAY['bursar']::text[], 't/clearance', NULL,
    'Clear graduands and others of the Bursary''s hold.',
    ARRAY['Open {menu:t/clearance}.',
          'Tick the candidates whose fees are settled; click `Clear the selected candidates`.',
          'Click `Hold` with `What is outstanding` for the rest.'],
    'The clearance card reads CLEARED or HELD for the Bursary.', '{}'::text[], 28);
SELECT manual.seed('bursar-analytics', 'Read financial analytics and the college payment report', 'REPORTS', ARRAY['bursar']::text[], 't/finanalytics', NULL,
    'See collections by category, channel and period.',
    ARRAY['Open {menu:t/finanalytics}; set `Session of the payment`, `Payment types`, `Trend by`; click `Excel` or `PDF`.',
          'Open {menu:t/collegepayments} for the College of Health Sciences.'],
    'Figures read from the ledger.', '{}'::text[], 29);
SELECT manual.seed('bursar-books', 'Post a journal and reconcile the ledger', 'PAYMENTS', ARRAY['bursar']::text[], 't/accounts', NULL,
    'Keep the books and reconcile against the bank.',
    ARRAY['Open {menu:t/accounts}; click `New journal`; `Add a line` per `Account`; click `Post the journal` (or `Post the reversal`).',
          'Open {menu:t/ledger}; filter `From`; click `Export the journal`.',
          'Open {menu:t/reconcile}; mark rows `Matched` or `Flag` them.'],
    'The books balance and flagged rows are followed up.', '{}'::text[], 30);
SELECT manual.seed('bursar-held-scripts', 'Read held scripts for fees', 'STUDENTS', ARRAY['bursar']::text[], 't/heldscripts', NULL,
    'See whose results are held for fees owing.',
    ARRAY['Open {menu:t/heldscripts}.',
          'Read the students and the balances.',
          'When paid, the hold lifts on the next sheet release.'],
    'The list empties as fees are settled.', '{}'::text[], 31);
SELECT manual.seed('ict-open-putme-registration', 'Open Post-UTME registration', 'SETTINGS', ARRAY['ict']::text[], 't/applicationwindows', NULL,
    'Let applicants register for the session''s Post-UTME.',
    ARRAY['Open {menu:t/applicationwindows}.',
          'Click the Post-UTME tile; choose the admission session.',
          'Click `Open now`, or `Schedule` with `Opens` and `Closes`; enter the `Reason`.',
          'Write the `Closure message` applicants read when it is shut; click `Save message`.',
          'Confirm the tile reads OPEN.'],
    'The registration page accepts applicants; the website shows the dates.', '{}'::text[], 10);
SELECT manual.seed('ict-close-putme-registration', 'Close, extend or shorten Post-UTME registration', 'SETTINGS', ARRAY['ict']::text[], 't/applicationwindows', NULL,
    'End or move the registration window.',
    ARRAY['Open {menu:t/applicationwindows}; click the Post-UTME tile.',
          'Click `Close now`, `Extend` or `Shorten`; enter the new date where asked and the `Reason`.',
          'Confirm the tile''s state.'],
    'The page closes with your message; the log keeps the act.', '{}'::text[], 11);
SELECT manual.seed('ict-other-application-windows', 'Open the postgraduate, JUPEB and CCE application windows', 'SETTINGS', ARRAY['ict']::text[], 't/applicationwindows', NULL,
    'Control every application window from one screen.',
    ARRAY['Open {menu:t/applicationwindows}.',
          'Click the tile (Postgraduate application, Postgraduate status checking, JUPEB application, JUPEB status checking, CCE application).',
          'Click `Open now` or `Schedule`; enter the `Reason`; `Save message`.'],
    'Each window is open only when its tile says so.', '{}'::text[], 12);
SELECT manual.seed('ict-putme-cbt-windows', 'Open the Post-UTME CBT and its result checking', 'SETTINGS', ARRAY['ict']::text[], 't/applicationwindows', NULL,
    'Let candidates sit the CBT, and later check the released score.',
    ARRAY['Open {menu:t/applicationwindows}.',
          'Click the Post-UTME CBT tile; click `Open now` for the sitting; `Close now` after it.',
          'When the Academic Office has released scores click the Post-UTME result checking tile; `Open now`.'],
    'The public CBT page verifies candidates while open; results read only while checking is open.', '{}'::text[], 13);
SELECT manual.seed('ict-fees-window', 'Open school fees payment', 'SETTINGS', ARRAY['ict']::text[], 't/portalwindows', NULL,
    'Let students pay the session''s school fees.',
    ARRAY['Open {menu:t/portalwindows}.',
          'Click the School Fees Payment tile; choose the session and semester.',
          'Click `Open now`, or `Schedule` with `Opens` and `Closes`; enter the `Reason`.',
          'Confirm the status reads OPEN.'],
    'Students may initiate school fees payment.', '{}'::text[], 14);
SELECT manual.seed('ict-registration-window', 'Open course registration and late registration', 'SETTINGS', ARRAY['ict']::text[], 't/portalwindows', NULL,
    'Let students register, and set the late period and its fee.',
    ARRAY['Open {menu:t/portalwindows}.',
          'Click the Course Registration tile; choose the session and semester.',
          'Click `Open now` or `Schedule`; set the late period and whether the late fee applies; enter the `Reason`.',
          'Click `Extend`, `Shorten` or `Close now` later.'],
    'Registration opens for the semester; the late fee is charged after the date.', '{}'::text[], 15);
SELECT manual.seed('ict-admission-checking', 'Open admission status checking', 'SETTINGS', ARRAY['ict']::text[], 't/admissionchecking', NULL,
    'Let applicants check their status.',
    ARRAY['Open {menu:t/admissionchecking}.',
          'Choose the session; click `Open now` or `Schedule`; enter the `Reason`.',
          'Read `Paid or checked from` for who has checked.'],
    'Applicants see Admission Status.', '{}'::text[], 16);
SELECT manual.seed('ict-session-setup', 'Set up a session and its semesters', 'SETTINGS', ARRAY['ict']::text[], 't/session', NULL,
    'Create the academic session, its semesters and the registration dates per level.',
    ARRAY['Open {menu:t/session}.',
          'Create the session (`Opens`, `Closes`, `Semesters`); click `Edit` to change it.',
          'For each semester and level set `Registration opens`, `Registration closes`, `Late registration closes`, `Lectures from`, `Examinations from` and the unit limits.',
          'To make it current open the session''s state; enter the `Senate minute`, type TRANSITION and click `Transition now`, then `Complete the transition`.'],
    'The portal works from the current session; the next may be planned beside it.', '{}'::text[], 17);
SELECT manual.seed('ict-exam-sessions', 'Open an examination session', 'SETTINGS', ARRAY['ict']::text[], 't/examsession', NULL,
    'Set the examination dates and release cards and sheets.',
    ARRAY['Open {menu:t/examsession}.',
          'Click `Open the session`; set the dates; click `Save the dates`.',
          'Click `Release examination cards` and, when due, `Release score sheets`.'],
    'Students print cards; lecturers enter sheets.', '{}'::text[], 18);
SELECT manual.seed('ict-putme-cbt', 'Run the Post-UTME CBT on the engine', 'EXAMS', ARRAY['ict']::text[], 't/putmecbt', NULL,
    'Fill the bank, create the examination, open the window, monitor and export the scores.',
    ARRAY['Open {menu:t/putmebank}; choose the session''s bank; click `Import` (download the template there) or `Add to the bank`; another ICT officer clicks `Approve` on each question.',
          'Open {menu:t/putmecbt}; click `Create examination`; set the questions, duration, window, the rules and — only if the Directorate wants one — a second factor beside the JAMB number; `Save the paper`; `Publish to candidates`.',
          'Open {menu:t/applicationwindows}; open the Post-UTME CBT tile.',
          'On the day click `Live monitor` on the examination; `Terminate the attempt` or `Give the extra time` where needed.',
          'After the sitting `Close now`, `Complete`, `Start the review`, `Approve`.',
          'Open {menu:t/putmescores}; click `Generate official score file`, then `Send to Academic Office`.'],
    'Candidates sit without a password and see no score; the Academic Office imports the file.', '{}'::text[], 19);
SELECT manual.seed('ict-structure-upload', 'Upload faculties, departments, programmes and courses', 'SETTINGS', ARRAY['ict']::text[], 't/facultyupload', NULL,
    'Build or extend the academic structure from sheets.',
    ARRAY['Open {menu:t/facultyupload}, {menu:t/departmentupload} or {menu:t/programmeupload}; click `Download template`; fill; upload; or enter one and click `Save the faculty` / `Save the department` / `Save the programme`.',
          'Open {menu:t/courseupload}; choose `Programme`, `Curriculum`, `Session`, `Semester`; `Download template`; upload; click `View loaded courses`.',
          'Click `Open course registration` when the structure is complete.'],
    'The catalogue and structures exist; registration offers the courses.', '{}'::text[], 20);
SELECT manual.seed('ict-institution', 'Set the institution profile and logo', 'SETTINGS', ARRAY['ict']::text[], 't/institution', NULL,
    'Name the University on every document.',
    ARRAY['Open {menu:t/institution}.',
          'Edit `Name`, `Short name`, `Motto`, `Address`, `Telephone`, `E-mail`, `Website`, `Footer note`, `Date style`; upload the logo.',
          'Click `Preview a sample report (print)`.',
          'Click `Save the profile`.'],
    'Every PDF, print and notice carries the profile.', '{}'::text[], 21);
SELECT manual.seed('ict-users', 'Create a sign-in and grant an office', 'SETTINGS', ARRAY['ict', 'admin', 'super']::text[], 't/users', NULL,
    'Give a person an account and the office they act as.',
    ARRAY['Open {menu:t/users}.',
          'Find the person or click `Create` (`Surname`, `Given names`, `Email`, `Phone`, `Staff number`).',
          'Click `Create account`; set `Username` and `First password` (`Generate`); the person must change it at first sign-in.',
          'Click `Grant an office`; choose the `Office`, `Bounded to` (faculty or department), `From`, `Authority for the grant` and the `Reason, as it will read in the log`; click `Grant`.',
          'Click `End it` with `Ended with effect from` to remove an office.'],
    'The person signs in and acts as the office within its bounds.', '{}'::text[], 22);
SELECT manual.seed('ict-notify', 'Configure mail, SMS and the notice queue', 'SETTINGS', ARRAY['ict']::text[], 't/mail', NULL,
    'Keep notices flowing.',
    ARRAY['Open {menu:t/mail}; set the server and sender; test.',
          'Open {menu:t/sms}; set the provider and sender name; test.',
          'Open {menu:t/notify}; read failed notices; click `Requeue`.'],
    'Notices send by e-mail and SMS; failures are retried.', '{}'::text[], 23);
SELECT manual.seed('ict-security', 'Review security and sessions', 'SETTINGS', ARRAY['ict', 'admin', 'super']::text[], 't/security', NULL,
    'Read sign-in events, lockouts and open sessions.',
    ARRAY['Open {menu:t/security}.',
          'Read failed sign-ins, lockouts and sessions by person.',
          'End a session or lift a lockout where the record justifies it.'],
    'Access is as the record shows.', '{}'::text[], 24);
SELECT manual.seed('ict-api-keys', 'Issue or revoke an API key', 'SETTINGS', ARRAY['ict', 'super']::text[], 't/api', NULL,
    'Give an integration access, and take it away.',
    ARRAY['Open {menu:t/api}.',
          'Click `Register` (`Client name`, `Owner`, `Scopes`, `Daily quota`).',
          'Click `Issue a key`; copy it; click `I have copied it`.',
          'Click `Deprecate` or `Revoke` when it must end.'],
    'The key works within its scopes and quota.', '{}'::text[], 25);
SELECT manual.seed('ict-release-cloud-dr', 'Monitor the release, the cloud and disaster recovery', 'SETTINGS', ARRAY['ict']::text[], 't/release', NULL,
    'Know what is deployed and that recovery works.',
    ARRAY['Open {menu:t/release} for the version deployed and its checks.',
          'Open {menu:t/cloud} for the services'' health.',
          'Open {menu:t/dr}; after a drill click `Record the drill` (`Drill`, `Run on`, `RTO achieved (min)`, `RPO achieved (min)`, `Outcome`).'],
    'The drill log is current.', '{}'::text[], 26);
SELECT manual.seed('ict-governance', 'Log a data request', 'SETTINGS', ARRAY['ict', 'registrar', 'admin', 'super']::text[], 't/governance', NULL,
    'Keep the NDPA register.',
    ARRAY['Open {menu:t/governance}.',
          'Click `Log the request` (`Type`, `Requester`, `Due`).',
          'Click `Start`, then `Complete` or `Mark done`.'],
    'The register shows every request and its outcome.', '{}'::text[], 27);
SELECT manual.seed('cpo-find-student', 'Find a student', 'SUPPORT', ARRAY['ictagent']::text[], 't/supportstudents', NULL,
    'Open a student''s support profile.',
    ARRAY['Open {menu:t/supportstudents}.',
          'Enter the matriculation number, JAMB number or name in `Search`; filter by `Faculty`, `Department`, `Programme`, `Level` or `Status`.',
          'Click `Open` on the student.'],
    'The support profile opens within your posting''s scope.', ARRAY['VIEW_STUDENT']::text[], 10);
SELECT manual.seed('cpo-edit-student', 'Edit a student''s contact or personal details', 'SUPPORT', ARRAY['ictagent']::text[], 't/supportstudents', NULL,
    'Change a field your posting may edit, with the reason.',
    ARRAY['Open the student (see Find a student).',
          'Click `Edit` on the section (contact, personal, family, photograph).',
          'Change the field; enter the `Reason`; click `Save`.',
          'For a locked field (name, date of birth) click `Escalate` with `What the office should decide`; do not change it yourself.'],
    'The change is on the record with your reason; a locked field waits for the Registry.', ARRAY['EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO']::text[], 11);
SELECT manual.seed('cpo-request-change', 'Raise a Registry change for a student', 'SUPPORT', ARRAY['ictagent']::text[], 't/supportstudents', NULL,
    'Ask the deciding office to change what you may not.',
    ARRAY['Open the student; click `Escalate`.',
          'Choose the `Section`; write `What the office should decide` and the `Details`.',
          'Click `Submit`.'],
    'The office''s Support Escalations queue receives it; the student is told of the outcome.', ARRAY['REQUEST_CHANGE']::text[], 12);
SELECT manual.seed('cpo-add-course', 'Add a course to a student''s registration', 'SUPPORT', ARRAY['ictagent']::text[], 't/supportstudents', NULL,
    'Register a course the student could not.',
    ARRAY['Open the student; open the registration section; choose `Session` and `Semester`.',
          'Click `Add course`; search the course; click `Check and add` (eligibility, fee and unit limit are checked).',
          'Enter the `Reason` (the ticket reference); click `Submit the registration`.',
          'If the engine refuses, read the refusal; `Escalate` rather than override.'],
    'The course is on the registration through the same engine the student uses.', ARRAY['MANAGE_REGISTRATION']::text[], 13);
SELECT manual.seed('cpo-drop-course', 'Drop a course from a student''s registration', 'SUPPORT', ARRAY['ictagent']::text[], 't/supportstudents', NULL,
    'Remove a course with the reason.',
    ARRAY['Open the student; open the registration section.',
          'Click `Drop` on the course; enter the `Reason`.',
          'Click `Submit the registration`; confirm the course reads dropped (`Restore` undoes it).'],
    'The registration changes with your reason on the record.', ARRAY['MANAGE_REGISTRATION']::text[], 14);
SELECT manual.seed('cpo-reset-password', 'Reset a student''s password', 'SUPPORT', ARRAY['ictagent']::text[], 't/supportstudents', NULL,
    'Give a student back their sign-in without seeing their password.',
    ARRAY['Open the student; click `Reset password`.',
          'Choose the `Method` (temporary password, or a reset link by e-mail/SMS); enter the `Reason`.',
          'Click `Submit`; read the temporary password once or confirm the link was sent.',
          'Tell the student; the portal requires a new password at the next sign-in.'],
    'Every earlier session is ended; the student signs in once with the temporary password or link.', ARRAY['VIEW_STUDENT']::text[], 15);
SELECT manual.seed('cpo-payment-issue', 'Resolve a payment issue', 'SUPPORT', ARRAY['ictagent']::text[], 't/supportpayments', NULL,
    'Find out why a payment is not showing and act within the desk''s powers.',
    ARRAY['Open {menu:t/supportpayments}; search the reference, invoice or student; click `Investigate`.',
          'Read the gateway''s state and the portal''s; click `Verify payment` or `Recheck / re-sync`.',
          'Click `Refresh payment entitlement` when a paid fee has not unlocked registration; `Regenerate receipt` for a receipt.',
          'Click `Record the investigation` with what you found.',
          'If money moved but nothing matches click `Escalate to Bursary`; for a gateway fault `Escalate to ICT Director`.'],
    'The payment reads PAID when the gateway confirms it; anything else is with the office that decides.', ARRAY['VIEW_PAYMENTS']::text[], 16);
SELECT manual.seed('cpo-tickets', 'Work a ticket', 'SUPPORT', ARRAY['ictagent', 'helpdeskhead']::text[], 't/helpdesk', NULL,
    'Take a ticket from the queue to its close.',
    ARRAY['Open {menu:t/helpdesk}; filter `Queue`, `Status`, `Priority`; click `Open` (or `Take`).',
          'Click `Accept the Ticket`, then `Start Work`.',
          'Click `Open the Student in Support Mode` to act; `Send Update` to write to the requester; `Wait for the Requester` when a reply is needed.',
          'Click `Escalate to an Office` or `Escalate to a Person` for what you may not decide; `Transfer to a Queue` for another desk.',
          'Click `Mark as Resolved` with `Resolution summary`, then `Close as Resolved`.'],
    'The requester is told at each step; SLA clocks stop at the close.', '{}'::text[], 17);
SELECT manual.seed('cpo-escalate-rule', 'When to escalate instead of changing a record', 'SUPPORT', ARRAY['ictagent']::text[], 't/helpdesk', NULL,
    'Keep records right: the desk fixes access and registration; offices decide identity, money and results.',
    ARRAY['Change only what your posting''s capabilities allow and the student''s own evidence supports.',
          'Escalate to the Registry: names, dates of birth, state, matriculation numbers, status.',
          'Escalate to the Bursary: any money that moved, refunds, credits, fee lines.',
          'Escalate to the Academic Office or the department: results, programme, level, eligibility.',
          'Never share a temporary password by ticket text; use the reset method.'],
    'Every change has an owner and a reason; nothing is corrected twice.', '{}'::text[], 18);
SELECT manual.seed('cpo-action-history', 'Read the support action history', 'SUPPORT', ARRAY['ictagent', 'helpdeskhead']::text[], 't/supportaudit', NULL,
    'See what the desk changed on a student.',
    ARRAY['Open {menu:t/supportaudit}.',
          'Filter `From` and `Module`; click `Filter`.',
          'Click `Excel` for the office.'],
    'Every support action with its agent, reason and ticket.', '{}'::text[], 19);
SELECT manual.seed('hd-queues-agents', 'Create a queue and post an agent', 'SUPPORT', ARRAY['helpdeskhead']::text[], 't/helpdeskagents', NULL,
    'Set up who answers what.',
    ARRAY['Open {menu:t/helpdeskagents}.',
          'Click `New Queue` (`Code`, `Name`, `Category`, `Office that decides`); save.',
          'Click `Post an Agent`; choose the `Agent`, the `Queue`, `Availability`, the scope (`Only for a faculty` / `Only for a department`) and the capabilities; click `Post the Agent`.',
          'Click `New Routing Rule` (`Category`, `Agent chosen by`); `Create the Rule`.',
          'Click `End Posting` or `Take Off the Desk` to remove an agent; `Move the Tickets` to another.'],
    'Tickets route to the queue and its agents by the rule.', '{}'::text[], 10);
SELECT manual.seed('hd-assign', 'Assign, reassign, transfer or escalate a ticket', 'SUPPORT', ARRAY['helpdeskhead']::text[], 't/helpdesk', NULL,
    'Move a ticket to the right hands.',
    ARRAY['Open {menu:t/helpdesk}; open the ticket.',
          'Click `Assign to an Agent` (`Agent`, `Note`), `Transfer to a Queue`, or `Escalate to an Office` / `Escalate to a Person` with `Why`.',
          'Click `Reopen` on a closed ticket the requester disputes.'],
    'The ticket''s queue and owner change; the history is kept.', '{}'::text[], 11);
SELECT manual.seed('hd-settings', 'Set categories, SLA and auto-close', 'SUPPORT', ARRAY['helpdeskhead']::text[], 't/helpdesksettings', NULL,
    'Define what a ticket may be and how fast it is answered.',
    ARRAY['Open {menu:t/helpdesksettings}.',
          'Click `New Category` (`Code`, `Label`, `Handled as`, `What to attach`); `Add a Field`; `Save the Category`.',
          'Set the response and resolution SLA and the auto-close days; click `Save SLA and Settings`.'],
    'New tickets use the categories; SLA breaches show on the desk.', '{}'::text[], 12);
SELECT manual.seed('hd-reports', 'Read desk reports: SLA, workload and volumes', 'REPORTS', ARRAY['helpdeskhead']::text[], 't/helpdeskreports', NULL,
    'Monitor the desk.',
    ARRAY['Open {menu:t/helpdeskreports}.',
          'Choose the period and the queue.',
          'Read SLA met, open by agent, by category; click `Download the Report`.'],
    'The figures read from the tickets.', '{}'::text[], 13);
SELECT manual.seed('super-setup-console', 'Run the Setup Console', 'SETTINGS', ARRAY['super']::text[], NULL, NULL,
    'See what the portal still needs before go-live and jump to it.',
    ARRAY['Open `Setup Console` (the first item of the menu).',
          'Read each step''s state (people, sessions, structure, fees, gateways, mail).',
          'Click the step to open its screen.'],
    'Every step reads done.', '{}'::text[], 10);
SELECT manual.seed('super-lecturers-upload', 'Upload lecturers', 'SETTINGS', ARRAY['super']::text[], 't/lecturers', NULL,
    'Bring academic staff onto the register.',
    ARRAY['Open {menu:t/lecturers}.',
          'Click `Download template`; fill `Staff number (PNO)`, `Surname`, `Given names`, `Department`, `Present rank`, `Email`, `Phone`; upload.',
          'Click `Add staff` for one; `Edit` to correct.'],
    'Lecturers may be allocated classes and granted the office.', '{}'::text[], 11);
SELECT manual.seed('super-channels', 'Set notification channels', 'SETTINGS', ARRAY['super']::text[], 't/channels', NULL,
    'Choose how notices go out.',
    ARRAY['Open {menu:t/channels}.',
          'Enable or disable e-mail, SMS and portal notices by kind.',
          'Save.'],
    'Notices follow the channels set.', '{}'::text[], 12);
SELECT manual.seed('super-migration', 'Run a data migration', 'SETTINGS', ARRAY['super']::text[], 't/migration', NULL,
    'Bring the old portal''s data over.',
    ARRAY['Open {menu:t/migration}.',
          'Choose the kind; download the template; upload the file; read the preview.',
          'Commit.'],
    'Records exist with their old references.', '{}'::text[], 13);
SELECT manual.seed('admin-dashboard', 'Read the Administrator Dashboard and readiness', 'DASHBOARD', ARRAY['admin']::text[], 'r/admin', NULL,
    'See the portal''s state and what is not ready.',
    ARRAY['Open {menu:r/admin}; read the counters and the chase panels (`Chase the chain`, `Unraised sheets`).',
          'Open {menu:t/readiness}; choose the `Session`; click `Fix` on an item to open its screen.'],
    'Every readiness item reads done before the session opens.', '{}'::text[], 10);
SELECT manual.seed('admin-finance-oversight', 'Oversee gateways, the ledger and reconciliation', 'PAYMENTS', ARRAY['admin']::text[], 't/gateways', NULL,
    'Keep the payment system healthy.',
    ARRAY['Open {menu:t/gateways}; click `Test the gateways`; `Set the credentials` or `Set the configuration` when a gateway changes.',
          'Open {menu:t/reconcile}; `Flag` or mark `Matched`.',
          'Open {menu:t/exception} to approve bank credits; {menu:t/ledger} for the journal.'],
    'Payments post and the books reconcile.', '{}'::text[], 11);
SELECT manual.seed('admin-fee-schedules', 'Read fee schedules', 'PAYMENTS', ARRAY['admin']::text[], 't/feesched', NULL,
    'See the fee lines in force.',
    ARRAY['Open {menu:t/feesched}.',
          'Choose the session; read the lines by programme and level.'],
    'The schedule the Bursar put in force.', '{}'::text[], 12);
SELECT manual.seed('manual-edit', 'Create or edit a procedure of the Quick Operational Manual', 'SETTINGS', ARRAY['super', 'admin', 'ict']::text[], 't/manualadmin', NULL,
    'Keep the manual true to the portal.',
    ARRAY['Open {menu:t/manualadmin}.',
          'Click `New procedure`, or `Edit` on one.',
          'Enter `Title`, `Purpose`, the `Category`, the `Offices` that may perform it, the `Menu item` it lives on, the numbered `Steps` (name a control in backticks; click `Insert menu item` to name a menu item, which the portal keeps current) and the `Expected result`.',
          'Click `Save`; the previous version is kept.',
          'Click `Preview as` an office to read the manual as they will.'],
    'A new procedure is a DRAFT until published; an edited one stays published.', '{}'::text[], 10);
SELECT manual.seed('manual-publish', 'Publish, unpublish, archive or restore a procedure', 'SETTINGS', ARRAY['super', 'admin', 'ict']::text[], 't/manualadmin', NULL,
    'Control what readers see.',
    ARRAY['Open {menu:t/manualadmin}.',
          'Click `Publish` on a draft; `Unpublish` to hide it; `Archive` to retire it; `Restore` an archived one.',
          'Click `Release a new edition` after a set of changes; the dashboard shows the edition.'],
    'Readers see the published procedures of their office only; every act is audited.', '{}'::text[], 11);
SELECT manual.seed('manual-order', 'Order procedures and bind them to a page', 'SETTINGS', ARRAY['super', 'admin', 'ict']::text[], 't/manualadmin', NULL,
    'Set the order in each category and the page whose help lists a procedure.',
    ARRAY['Open {menu:t/manualadmin}.',
          'Drag or use the arrows to order; click `Save the order`.',
          'On a procedure set `Contextual page` to the route whose `How to` menu should list it.'],
    'The manual and the page''s help read in that order.', '{}'::text[], 12);
SELECT manual.seed('gst-dashboard', 'Read the GST dashboard', 'DASHBOARD', ARRAY['gst']::text[], 'r/gst', NULL,
    'See registrations, payments and examinations of the session at a glance.',
    ARRAY['Open {menu:r/gst}.',
          'Read the counts by course and `By faculty`; `Clear the filters` to see all.',
          'Click `Manage courses`, `Question bank`, `CBT examinations`, `Live monitor` or `Score sheets` to act.'],
    'Each tile opens the screen named.', '{}'::text[], 10);
SELECT manual.seed('gst-courses', 'Set up a GST course for the session', 'ACADEMICS', ARRAY['gst']::text[], 't/gstcourses', NULL,
    'State the course, its programmes, lecturer and CA.',
    ARRAY['Open {menu:t/gstcourses}.',
          'Open the course or create it (`Course code`, `Title`, `Units`, `Level`, `Semester`, `Session`, `CA out of`).',
          'Click `Programmes`; tick `Every programme` or the programmes `At level`; give `Reason for any programme taken off`.',
          'Click `Lecturer`; choose the `Lecturer` and `Second examiner`; `Save`.',
          'Click `Deactivate` when a course no longer runs.'],
    'Students of those programmes see the course and owe the GST fee for it.', '{}'::text[], 11);
SELECT manual.seed('gst-students', 'See GST students and their eligibility', 'STUDENTS', ARRAY['gst']::text[], 't/gststudents', NULL,
    'Know who is registered and who owes the fee.',
    ARRAY['Open {menu:t/gststudents}.',
          'Search; filter by course and payment status.',
          'Click `View eligibility` on a student; `Excel` or `PDF` for the list.'],
    'Registration and payment status per student.', '{}'::text[], 12);
SELECT manual.seed('gst-cbt', 'Create, run and publish a GST CBT examination', 'EXAMS', ARRAY['gst']::text[], 't/gstcbt', NULL,
    'Examine a GST course on the engine.',
    ARRAY['Open {menu:t/gstbank}; choose the course; click `Import` (template there) or `Add to the bank`; another officer clicks `Approve` on each question.',
          'Open {menu:t/gstcbt}; click `Create examination`; set the class, questions, duration, window and rules; `Save the paper`.',
          'Click `Add a sitting` and `Invigilators` where halls are used; `Print slips`.',
          'Click `Publish to candidates`.',
          'On the day click `Live monitor`; after it `Close now`, `Complete`, `Start the review`, `Approve`, then `Publish to students` or `Send to the score sheet`.'],
    'Students sit in the room; approved results reach the sheet and the student.', '{}'::text[], 13);
SELECT manual.seed('gst-score-sheets', 'Enter and attest a GST score sheet', 'RESULTS', ARRAY['gst']::text[], 't/scores', NULL,
    'Submit the course''s scores into the result chain.',
    ARRAY['Open {menu:t/scores}; click `View` on the course.',
          'Type the scores or `Upload a completed sheet`; `Save the draft`.',
          'Click `Download Validation Report`; correct what it flags.',
          'Click `Submit and attest`.'],
    'The sheet goes up the chain; {menu:t/sheethistory} follows it.', '{}'::text[], 14);
SELECT manual.seed('eps-courses-students', 'Set up EPS courses and see EPS students', 'ACADEMICS', ARRAY['eps']::text[], 't/epscourses', NULL,
    'State the course, its programmes and lecturer; know who owes the fee.',
    ARRAY['Open {menu:t/epscourses}; open or create the course; `Programmes`, `Lecturer`, `Save`.',
          'Open {menu:t/epsstudents}; search; `View eligibility`.'],
    'Students of those programmes see the course and owe the EPS fee for it.', '{}'::text[], 10);
SELECT manual.seed('eps-cbt', 'Run an EPS CBT examination', 'EXAMS', ARRAY['eps']::text[], 't/epscbt', NULL,
    'Examine an EPS course on the engine.',
    ARRAY['Open {menu:t/epsbank}; fill and moderate the bank.',
          'Open {menu:t/epscbt}; `Create examination`; `Save the paper`; `Publish to candidates`.',
          'After the sitting `Close now`, `Complete`, `Start the review`, `Approve`, `Publish to students` or `Send to the score sheet`.'],
    'Approved results reach the sheet and the student.', '{}'::text[], 11);
SELECT manual.seed('jupeb-applications', 'Verify a JUPEB application and admit', 'ADMISSIONS', ARRAY['jupeb']::text[], 'jupeb/applications', NULL,
    'Read an application, its payment and documents; decide it.',
    ARRAY['Open {menu:jupeb/applications}.',
          'Open the application; read the `Application summary` and the documents (the viewer rotates and fits).',
          'Click `Confirm` to admit or `Decline` with the reason; `Admission letter` prints the letter.',
          'Click `Acceptance letter` when the acceptance fee is paid; `Give the account` to create the student sign-in.'],
    'The applicant reads the status; an admitted one pays acceptance and becomes a student.', '{}'::text[], 10);
SELECT manual.seed('jupeb-payments', 'Read JUPEB payments and old-portal payments', 'PAYMENTS', ARRAY['jupeb']::text[], 'jupeb/payments', NULL,
    'See every JUPEB fee paid and bring old ones over.',
    ARRAY['Open {menu:jupeb/payments}; filter by session and kind.',
          'Open {menu:jupeb/oldpayments}; download the template; upload the old portal''s export; match.'],
    'Balances read right on each student.', '{}'::text[], 11);
SELECT manual.seed('jupeb-catalogue', 'Keep subjects, combinations and classes', 'ACADEMICS', ARRAY['jupeb']::text[], 'jupeb/catalogue', NULL,
    'State what the Board offers and how students are grouped.',
    ARRAY['Open {menu:jupeb/catalogue}; click `Add subject`, `Add combination` or `Add a unit` (the course under a subject); `Disable` what is not offered.',
          'Open {menu:jupeb/classes}; click `Add class`; assign students and lecturers.'],
    'Registration offers only active combinations.', '{}'::text[], 12);
SELECT manual.seed('jupeb-timetable', 'Build the timetable', 'ACADEMICS', ARRAY['jupeb']::text[], 'jupeb/timetable', NULL,
    'Timetable every class by room without clashes.',
    ARRAY['Open {menu:jupeb/timetable}.',
          'Click `Add a room` (`Name`, `Code`, `Seats`).',
          'Click `Add a slot`: `Class`, `Subject`, `Course`, `Day`, `Starts`, `Ends`, `Room`; `Save` (a clash is refused).',
          'Click `Copy` to carry the timetable `Into the semester` or `Into the session`; `Excel` or `PDF`.'],
    'Students and lecturers read the timetable; lectures due are drawn from it.', '{}'::text[], 13);
SELECT manual.seed('jupeb-attendance', 'Take attendance and warn students', 'STUDENTS', ARRAY['jupeb']::text[], 'jupeb/attendance', NULL,
    'Keep the register per lecture and the standing it gives.',
    ARRAY['Open {menu:jupeb/attendance}.',
          'Click `Open the register` on the lecture due; `Mark all present`, untick absentees, `Mark the rest absent`; `Save`; `Lock`.',
          'Set `Minimum (%)` and `Classes counted before a warning`; click `Warn students below the minimum now`.',
          'Click `Export (Excel)`.'],
    'Standing is computed; warned students are told.', '{}'::text[], 14);
SELECT manual.seed('jupeb-ca', 'Set continuous assessment parts and lock the sheet', 'RESULTS', ARRAY['jupeb']::text[], 'jupeb/ca', NULL,
    'State the CA parts per subject and keep lecturers'' entries.',
    ARRAY['Open {menu:jupeb/ca}.',
          'Choose `Session` and `Class`; click `Add a part`; `Save the parts`.',
          'Open a sheet; read the entries; click `Lock` (or `Unlock` with `Why`).'],
    'Lecturers enter only the parts set; a locked sheet does not change.', '{}'::text[], 15);
SELECT manual.seed('jupeb-exam-year', 'Register candidates with the Board and publish the examination', 'EXAMS', ARRAY['jupeb']::text[], 'jupeb/examination', NULL,
    'Send the Board the candidate list, set the papers and the admit cards.',
    ARRAY['Open {menu:jupeb/examination}.',
          'Click `Export ready (Excel)` for the Board; `Mark sent`; later `Export changed` and `Correction sent`; `Confirmed by the Board` with `The Board''s reference`.',
          'Click `Add a paper` (`Subject`, `Paper`, `Date`, `Starts`, `Ends`, `Centre`); `Save`.',
          'Click `Publish to the students`; they print the admit card.'],
    'The Board has the list; students have admit cards.', '{}'::text[], 16);
SELECT manual.seed('jupeb-cbt-practice', 'Run JUPEB CBT and practice tests', 'EXAMS', ARRAY['jupeb']::text[], 'jupeb/cbt', NULL,
    'Examine on the engine and let students practise.',
    ARRAY['Open {menu:jupeb/bank}; fill and moderate the subject''s bank.',
          'Open {menu:jupeb/cbt}; `Create examination`; `Save the paper`; `Publish to candidates`; after it `Close now`, `Complete`, `Start the review`, `Approve`.',
          'Open {menu:jupeb/practice}; click `New practice test` or `New mock examination`; `Add a question` or `Template`; set `Open to the students`; `Release results` for a mock.'],
    'CBT results feed the CA; practice runs apart from it.', '{}'::text[], 17);
SELECT manual.seed('jupeb-results-reports', 'Publish results, read reports and announce', 'RESULTS', ARRAY['jupeb']::text[], 'jupeb/results', NULL,
    'Release results, run the office''s reports and tell students.',
    ARRAY['Open {menu:jupeb/results}; review and publish.',
          'Open {menu:jupeb/reports}; choose `Session`; `Excel` or `PDF`.',
          'Open {menu:jupeb/announcements}; write `Title`, `Message`, `Show until`; `Publish`.'],
    'Students read results and notices on their portal.', '{}'::text[], 18);
SELECT manual.seed('jupeb-settings-calendar', 'Set the JUPEB session and calendar', 'SETTINGS', ARRAY['jupeb']::text[], 'jupeb/settings', NULL,
    'Open the session the Office works in and plan its calendar.',
    ARRAY['Open {menu:jupeb/settings}; set the current session and the windows.',
          'Open {menu:jupeb/calendar}; `Add an event` (`Event`, `From`, `To`, `The portal works from it as`); `Confirm the calendar`.',
          'Click `Plan the next session from this` at the year''s end.'],
    'Semesters, lectures and deadlines follow the calendar.', '{}'::text[], 19);
SELECT manual.seed('jupeb-idcards-import', 'Print identity cards and import old-portal students', 'STUDENTS', ARRAY['jupeb']::text[], 'jupeb/idcards', NULL,
    'Issue cards and bring over the old portal''s students.',
    ARRAY['Open {menu:jupeb/idcards}; `Choose all with a photograph`; `Print the chosen`; `Replace the card` with `Why`.',
          'Open {menu:jupeb/import}; upload the old portal''s list; `Download login details (Excel)` for the sign-ins created.'],
    'Students hold cards and sign in.', '{}'::text[], 20);
SELECT manual.seed('cce-upload-list', 'Upload the JAMB CCE candidate list', 'ADMISSIONS', ARRAY['academic']::text[], 'cce/upload', NULL,
    'Bring JAMB''s CCE list in and validate it.',
    ARRAY['Open {menu:cce/upload}.',
          'Click `Download the template`; choose `The CCE list (Excel .xlsx or .csv)`; click `Upload a list`.',
          'Read the rows (new, updated, duplicates, invalid) and `Why it is not loaded`.',
          'Apply; `Withdraw` with `The reason` if wrong. Open {menu:cce/imports} for the history.'],
    'Candidates may register with JAMB number and date of birth.', '{}'::text[], 10);
SELECT manual.seed('cce-processing', 'Process CCE admissions', 'ADMISSIONS', ARRAY['cce', 'academic']::text[], 'cce/processing', NULL,
    'Review applications in two hands and publish.',
    ARRAY['Open {menu:cce/applications}; `View` an application; read the fee, the O''Level and the documents.',
          'Open {menu:cce/processing}; click `Accept`, `Not admit` or `Reject` (a second officer confirms; nobody approves their own).',
          'The Academic Office publishes; open {menu:cce/admission-list}; `Export (Excel)`.'],
    'Applicants read the status; admitted ones pay acceptance and are activated.', '{}'::text[], 11);
SELECT manual.seed('cce-students', 'Activate and keep CCE students', 'STUDENTS', ARRAY['cce']::text[], 'cce/students', NULL,
    'See the Centre''s students and their standing.',
    ARRAY['Open {menu:cce/students}.',
          'Search `Search the CCE students`; filter `State`.',
          'Open a student for registration, fees and attendance.'],
    'Every CCE student with the CCE session they are in.', '{}'::text[], 12);
SELECT manual.seed('cce-session-calendar', 'Set the CCE session, calendar and classes', 'SETTINGS', ARRAY['cce', 'academic']::text[], 'cce/calendar', NULL,
    'Run the Centre one session behind, on its own calendar.',
    ARRAY['Open {menu:cce/session} (Academic Office): state `Follow undergraduate by` or `Or name the CCE session`; `Save`.',
          'Open {menu:cce/calendar}; set the semesters, registration and lecture dates; `Set this semester`.',
          'Open {menu:cce/classes}; `Add one class` per course (`Class`, `Course`, `Lecturer`); `Open the classes`.'],
    'Registration and the evening timetable follow the CCE calendar.', '{}'::text[], 13);
SELECT manual.seed('cce-timetable-attendance', 'Build the evening timetable and take attendance', 'ACADEMICS', ARRAY['cce']::text[], 'cce/timetable', NULL,
    'Timetable the evening classes and keep registers.',
    ARRAY['Open {menu:cce/timetable}; `Add a period` (`Day`, times, room); a daytime clash is refused.',
          'Open {menu:cce/teaching} (lecturers) or {menu:cce/attendance}; `Open the register`; `Mark`; `Save the register`; `Lock it`.',
          'Click `Set the policy` for the minimum attendance and whether it bars examinations.'],
    'Attendance standing is computed per student.', '{}'::text[], 14);
SELECT manual.seed('cce-registration-fees', 'Run CCE course registration and school fees', 'PAYMENTS', ARRAY['cce']::text[], 'cce/registrations', NULL,
    'Open registration on the CCE calendar and state the CCE fee lines.',
    ARRAY['Open {menu:cce/school-fees}; `State them` (the CCE lines only); the Bursary confirms.',
          'Open {menu:cce/registrations}; read who registered; act on refusals.'],
    'CCE students pay CCE lines and register CCE classes only.', '{}'::text[], 15);
SELECT manual.seed('cce-exams-progression', 'Run CCE examinations and progression', 'RESULTS', ARRAY['cce']::text[], 'cce/exams', NULL,
    'Examine the Centre''s classes in a CCE examination session and keep positions.',
    ARRAY['Open {menu:cce/exams}; open the CCE examination session; release sheets to the CCE classes.',
          'Open {menu:cce/progression}; search `Number or surname`; read `Standing` and the expected completion.'],
    'CCE results run their own chain; positions follow the CCE calendar.', '{}'::text[], 16);
SELECT manual.seed('cce-reports', 'Read CCE reports', 'REPORTS', ARRAY['cce', 'academic']::text[], 'cce/reports', NULL,
    'Count applications, students and fees of the Centre.',
    ARRAY['Open {menu:cce/reports}.',
          'Choose the session; click `Applications (Excel)`, `CCE students (Excel)` or `The CCE list (Excel)`.'],
    'Figures read from the Centre''s records.', '{}'::text[], 17);
SELECT manual.seed('pg-admissions', 'Decide a postgraduate admission (the School''s final word)', 'ADMISSIONS', ARRAY['pgschool', 'pgsecretary']::text[], 't/pgadmissions', NULL,
    'After the department''s recommendation, admit or not.',
    ARRAY['Open {menu:t/pgadmissions}.',
          'Open the application; read `Details`, the documents (`Documents verified`, `Documents missing`) and the department''s recommendation.',
          'Click `Schedule the screening` (`Day and time`, `Venue`) where a physical screening is held; `Set the screening policy` once per session.',
          'Click `Admit (offer a place)`, `Not admitted`, `Return to the department` or `Return to applicant for correction` with the `Decision` note.',
          'Click `Record acceptance` when the fee is paid, then `Admit onto the register`.'],
    'The department recommends; only the School admits. The applicant reads the decision.', '{}'::text[], 10);
SELECT manual.seed('pg-calendar-courses', 'Set the School''s calendar and courses', 'SETTINGS', ARRAY['pgschool', 'pgsecretary']::text[], 't/pgcalendar', NULL,
    'Open the School''s session, its windows and the courses offered.',
    ARRAY['Open {menu:t/pgcalendar}; `Setup new session`; `Save session`; `Set windows` (`Opens`, `Closes`); `Make current`.',
          'Open {menu:t/pgcourses}; `Add course` (`Course code`, `Title`, `Units`, `Semester`, `Type`) or `Download template` and upload.'],
    'Students register the School''s courses within the windows.', '{}'::text[], 11);
SELECT manual.seed('pg-registration-results', 'Endorse registrations and enter results', 'RESULTS', ARRAY['pgschool', 'pgsecretary']::text[], 't/pgscores', NULL,
    'Approve the students'' registrations and record course results.',
    ARRAY['Open {menu:t/pgscores}; choose `Session`, `Semester`, `Programme`; click `Endorse registration`.',
          'Open a course; enter the results; `Save`.',
          'Open {menu:t/broadsheet} for the broadsheet; {menu:t/graduation} for awards.'],
    'Results stand on the School''s broadsheet.', '{}'::text[], 12);
SELECT manual.seed('pgschool-research', 'Run the research desk: proposals, panels and viva', 'ACADEMICS', ARRAY['pgschool']::text[], 't/pgresearch', NULL,
    'Move each candidate''s research through its stages.',
    ARRAY['Open {menu:t/pgresearch}.',
          'Open the candidate; `Accept` or `Return` the proposal or draft; `Add` a panel member.',
          'Open {menu:t/pgexaminers}; `Appoint examiner` (`Name`, `Institution`, `Field / specialization`, `Tenure from`, `Tenure to`).',
          'Open {menu:t/pgclearance}; click `Clear for binding` when the corrections are done.'],
    'The candidate proceeds to graduation when cleared.', '{}'::text[], 13);
SELECT manual.seed('pgsecretary-research', 'Schedule seminars, panels and the viva; clear theses', 'ACADEMICS', ARRAY['pgsecretary']::text[], 't/pgseminars', NULL,
    'Run the research calendar for the School.',
    ARRAY['Open {menu:t/pgseminars}; open the candidate whose proposal is approved; schedule the seminar.',
          'Open {menu:t/pgpanels}; `Add` the panel; record the viva.',
          'Open {menu:t/pgexaminers}; `Appoint examiner`.',
          'Open {menu:t/pgclearance}; `Clear for binding`.'],
    'Each stage is on the candidate''s record.', '{}'::text[], 13);
SELECT manual.seed('pg-students-matric', 'Keep PG students and matriculate them', 'STUDENTS', ARRAY['pgschool', 'pgsecretary']::text[], 't/pgstudents', NULL,
    'See the register and change a status.',
    ARRAY['Open {menu:t/pgstudents}; filter `Programme`, `Entry session`, `Standing`; `Change status` with the reason.',
          'At the Secretary''s desk open the registration list and click `Matriculate` for the session''s new students.'],
    'Students carry the status and the matriculation number.', '{}'::text[], 14);
SELECT manual.seed('pg-board', 'Take results through the School Board', 'RESULTS', ARRAY['pgschool']::text[], 't/pgboard', NULL,
    'Record the Board''s recommendation and the award.',
    ARRAY['Open {menu:t/pgboard}; click `Recommend` on the business; `Record Award`.'],
    'The Secretary sends the recommended results to Senate.', '{}'::text[], 15);
SELECT manual.seed('pgsecretary-senate', 'Send results to Senate and run examinations', 'RESULTS', ARRAY['pgsecretary']::text[], 't/pgsenate', NULL,
    'Carry the Board''s results to Senate and keep the examination desk.',
    ARRAY['Open {menu:t/pgsenate}; send the recommended results.',
          'Open {menu:t/pgexams} for the course examinations; {menu:t/pgregistration} to endorse registrations and `Matriculate`.'],
    'Awards are on Senate''s authority.', '{}'::text[], 15);
SELECT manual.seed('hostel-inventory', 'Set up hostels, blocks and rooms', 'SETTINGS', ARRAY['housing', 'dsa']::text[], 't/hostel-inventory', NULL,
    'Build the bed inventory.',
    ARRAY['Open {menu:t/hostel-inventory}.',
          'Click `Add a hostel` (`Code`, `Name`, `Campus`, `Category`); `Add a block` (`Block code`); `Add a room` or `Generate rooms` (`Beds per room`, `Capacity (beds)`).',
          'Click `Add an asset` for furniture (`Asset tag`, `Asset type`, `Condition`).',
          'Click `Bed list (Excel)`. For many rooms open {menu:t/hostel-import} (`File`, `Sheet`, `Header row`).'],
    'Every bed exists and may be allocated.', '{}'::text[], 10);
SELECT manual.seed('hostel-window', 'Open the hostel application window and its rules', 'SETTINGS', ARRAY['housing', 'dsa']::text[], 't/hostel-window', NULL,
    'Set when students apply, the fee, the hold and the allocation method.',
    ARRAY['Open {menu:t/hostel-window}.',
          'Click `Create the window`: `Semester`, `Applications open`, `Applications close`, `Stay from`, `Stay to`, `Accommodation fee (₦)`, `Hold window (hours)` (48), `Maximum applications`, `Allocation method`.',
          'Click `Save and open applications`; later `Save and close applications`.'],
    'Students apply; an offered bed is held the hours set for payment.', '{}'::text[], 11);
SELECT manual.seed('hostel-allocate', 'Allocate beds and run the waitlist', 'STUDENTS', ARRAY['housing', 'dsa']::text[], 't/hostel-applications', NULL,
    'Approve applications and give beds.',
    ARRAY['Open {menu:t/hostel-applications}; filter `Standing`, `Faculty`, `Level`.',
          'Click `Approve` or `Reject` with `Reason`; `Allocate the bed` (`Free bed`) on one; or on the dashboard `Generate Allocation` then `Confirm and allocate`.',
          'Click `Lapse expired holds` for unpaid offers; the waitlist moves up.'],
    'Each allocated student pays within the hold and checks in.', '{}'::text[], 12);
SELECT manual.seed('hostel-special', 'Allocate special, SU and security rooms', 'STUDENTS', ARRAY['housing', 'dsa']::text[], 't/hostel-special', NULL,
    'Give a room outside the queue with the reason on record.',
    ARRAY['Open {menu:t/hostel-special}.',
          'Click `Allocate a special room`: `Category` (medical, Students'' Union, security), `Occupant` or `Student number`, `Bed`, `Start date`, `End date`, `Reason, as it will read in the record`.',
          'Click `Allocate`.'],
    'The bed is held for the occupant for the dates.', '{}'::text[], 13);
SELECT manual.seed('hostel-occupancy', 'Check students in and out', 'STUDENTS', ARRAY['housing', 'dsa']::text[], 't/hostel-occupancy', NULL,
    'Keep occupancy true.',
    ARRAY['Open {menu:t/hostel-occupancy}; click `To check in`; open the student; check in (the QR on the receipt is scanned).',
          'Click `Checkout requested`; open {menu:t/hostel-clearance}; `Inspect` the room; `Update` the clearance with `Note to the student`; `Save`.',
          'Transfers: open the request under {menu:t/hostel-clearance}; approve to the new bed.'],
    'Beds read occupied or free as they are; clearance is on the record.', '{}'::text[], 14);
SELECT manual.seed('hostel-discipline', 'Record an incident, a sanction or a room swap', 'STUDENTS', ARRAY['housing', 'dsa']::text[], 't/hostel-discipline', NULL,
    'Decide discipline and swaps.',
    ARRAY['Open {menu:t/hostel-discipline}.',
          'Click `Report an incident` (`Incident`, the students); `Decide the sanction` (`Sanction`, `Fine (₦)`, `Barred from a bed until`, `Reason, as the student will read it`) or `Dismiss the incident`.',
          'Click `Decide the appeal`; `Waive` a fine with reason.',
          'On a swap request click `Approve` or `Refuse the swap`.'],
    'The student reads the decision; a fine is a fee line.', '{}'::text[], 15);
SELECT manual.seed('hostel-reports', 'Read occupancy accountability and hostel fees', 'REPORTS', ARRAY['housing', 'dsa']::text[], 't/hostel-accountability', NULL,
    'Account for every bed and every fee.',
    ARRAY['Open {menu:t/hostel-accountability}; filter `Session`, `Hostel`, `Category`, `Fee status`; `Excel` or `PDF`.',
          'The fee rules and revenue are the Bursary''s (`Hostel Fees & Revenue`); the Dean of Student Affairs reads them under `Hostel Fees (read)`.'],
    'Beds, occupants and payments agree.', '{}'::text[], 16);


-- ── 6 · grants ───────────────────────────────────────────────────────────────────
GRANT USAGE ON SCHEMA manual TO app_platform, app_iam, app_student, app_auditor;
GRANT SELECT, INSERT, UPDATE ON manual.procedure, manual.procedure_version, manual.edition, manual.view TO app_platform, app_iam, app_student;
GRANT SELECT ON manual.procedure, manual.procedure_version, manual.edition, manual.view TO app_auditor;

COMMIT;
