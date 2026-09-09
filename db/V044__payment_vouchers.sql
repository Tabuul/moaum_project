-- ═══════════════════════════════════════════════════════════════════════════
-- V044 — payment vouchers and the pre-payment gate (EXA)
--
--   Every University payment passes Internal Audit before money moves. The
--   Bursary raises a voucher; it goes to the Director of Internal Audit, then
--   the Deputy Director, then an auditor who attests the checks a portal cannot
--   evidence; then it returns to the Bursary to pay. BR-006 applies exactly as
--   it does to a mark: the officer who prepared or authorised a voucher may not
--   audit it, and no person may act twice in its chain, however many offices
--   they hold — the check is on the person, on one act table.
--
--   A query is the same object as a returned result set: a finding that cannot
--   be empty, sent to a named office, travelling with the voucher, and the
--   voucher cannot move until it is answered.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE expenditure.voucher (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference    text NOT NULL UNIQUE,
    title        text NOT NULL,
    kind         text NOT NULL,
    source       text NOT NULL,
    cost_centre  text NULL,
    payee        text NOT NULL,
    amount       numeric(14,2) NOT NULL,
    stage        text NOT NULL DEFAULT 'WITH_DIRECTOR',
    raised_by    uuid NOT NULL,
    raised_at    timestamptz NOT NULL DEFAULT now(),
    paid_at      timestamptz NULL,
    paid_by      uuid NULL,
    rejected_why text NULL,
    CONSTRAINT ck_pv_amount CHECK (amount > 0),
    CONSTRAINT ck_pv_stage CHECK (stage IN ('WITH_DIRECTOR','WITH_DEPUTY','WITH_AUDITOR','CLEARED','PAID','REJECTED'))
);
CREATE INDEX ix_pv_stage ON expenditure.voucher (stage, raised_at DESC);
SELECT audit.attach('expenditure.voucher');

-- one row per act on a voucher; this is what BR-006 reads to refuse a second act by the same person
CREATE TABLE expenditure.voucher_act (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    voucher_id uuid NOT NULL REFERENCES expenditure.voucher(id),
    actor_id   uuid NOT NULL,
    office     text NOT NULL,
    act        text NOT NULL,
    from_stage text NOT NULL,
    to_stage   text NOT NULL,
    note       text NULL,
    at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pva_voucher ON expenditure.voucher_act (voucher_id, at);
SELECT audit.attach('expenditure.voucher_act');

CREATE TABLE expenditure.voucher_query (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    voucher_id uuid NOT NULL REFERENCES expenditure.voucher(id),
    finding    text NOT NULL,
    sent_to    text NOT NULL,
    raised_by  uuid NOT NULL,
    raised_at  timestamptz NOT NULL DEFAULT now(),
    answer     text NULL,
    answered_at timestamptz NULL,
    answered_by uuid NULL,
    CONSTRAINT ck_pvq_finding CHECK (btrim(finding) <> '')
);
CREATE INDEX ix_pvq_open ON expenditure.voucher_query (voucher_id) WHERE answer IS NULL;
SELECT audit.attach('expenditure.voucher_query');

-- the office that moves a voucher off each stage, and the stage it moves to
CREATE OR REPLACE FUNCTION expenditure.pv_next(p_stage text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_stage WHEN 'WITH_DIRECTOR' THEN 'WITH_DEPUTY' WHEN 'WITH_DEPUTY' THEN 'WITH_AUDITOR'
                        WHEN 'WITH_AUDITOR' THEN 'CLEARED' END;
$$;

CREATE OR REPLACE FUNCTION expenditure.raise_voucher(p_title text, p_kind text, p_source text, p_cost_centre text, p_payee text, p_amount numeric)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_ref text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a voucher is raised by a person' USING ERRCODE = '23514'; END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'a voucher is for an amount' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_title), '') = '' OR coalesce(btrim(p_payee), '') = '' THEN
        RAISE EXCEPTION 'a voucher says what it is for and who it pays' USING ERRCODE = '23514';
    END IF;
    v_ref := 'PV/' || to_char(current_date, 'YYYY') || '/' ||
             lpad(platform.next_number('VOUCHER', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0');
    INSERT INTO expenditure.voucher (reference, title, kind, source, cost_centre, payee, amount, raised_by)
    VALUES (v_ref, btrim(p_title), p_kind, p_source, nullif(btrim(coalesce(p_cost_centre, '')), ''), btrim(p_payee), p_amount, who);
    RETURN v_ref;
END $$;

-- advance one desk; refuses while a query is open, refuses the wrong office, and refuses BR-006
CREATE OR REPLACE FUNCTION expenditure.advance_voucher(p_id uuid, p_note text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v expenditure.voucher; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), ''); v_next text; v_needs text;
BEGIN
    SELECT * INTO v FROM expenditure.voucher WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such voucher' USING ERRCODE = '23503'; END IF;
    IF who IS NULL THEN RAISE EXCEPTION 'a voucher is signed by a person' USING ERRCODE = '23514'; END IF;
    v_next := expenditure.pv_next(v.stage);
    IF v_next IS NULL THEN RAISE EXCEPTION 'voucher % is not on a stage that advances', v.reference USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM expenditure.voucher_query WHERE voucher_id = p_id AND answer IS NULL) THEN
        RAISE EXCEPTION 'a query stands against % and it cannot move until answered', v.reference USING ERRCODE = '23514';
    END IF;
    v_needs := CASE v.stage WHEN 'WITH_DIRECTOR' THEN 'audit' WHEN 'WITH_DEPUTY' THEN 'deputyaudit' ELSE 'audit,deputyaudit' END;
    IF office IS NULL OR (office <> 'super' AND position(office in v_needs) = 0) THEN
        RAISE EXCEPTION 'this desk is signed by % , not by %', v_needs, coalesce(office, 'nobody') USING ERRCODE = '23514';
    END IF;
    IF who = v.raised_by OR EXISTS (SELECT 1 FROM expenditure.voucher_act WHERE voucher_id = p_id AND actor_id = who) THEN
        RAISE EXCEPTION 'no person acts twice on a voucher (BR-006)' USING ERRCODE = '23514',
            HINT = 'The officer who prepared or authorised a voucher may not audit it, however many offices they hold.';
    END IF;
    INSERT INTO expenditure.voucher_act (voucher_id, actor_id, office, act, from_stage, to_stage, note)
    VALUES (p_id, who, coalesce(office, ''), 'ADVANCE', v.stage, v_next, nullif(btrim(coalesce(p_note, '')), ''));
    UPDATE expenditure.voucher SET stage = v_next WHERE id = p_id;
    RETURN v_next;
END $$;

CREATE OR REPLACE FUNCTION expenditure.query_voucher(p_id uuid, p_finding text, p_sent_to text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_id uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a query is raised by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_finding), '') = '' THEN RAISE EXCEPTION 'a query carries a finding, and none was given' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_sent_to), '') = '' THEN RAISE EXCEPTION 'a query names the office it is sent to' USING ERRCODE = '23514'; END IF;
    INSERT INTO expenditure.voucher_query (voucher_id, finding, sent_to, raised_by)
    VALUES (p_id, btrim(p_finding), btrim(p_sent_to), who) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION expenditure.answer_query(p_query uuid, p_answer text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a query is answered by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_answer), '') = '' THEN RAISE EXCEPTION 'an answer to a query is not empty' USING ERRCODE = '23514'; END IF;
    UPDATE expenditure.voucher_query SET answer = btrim(p_answer), answered_at = now(), answered_by = who
     WHERE id = p_query AND answer IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'no open query to answer' USING ERRCODE = '23514'; END IF;
END $$;

CREATE OR REPLACE FUNCTION expenditure.pay_voucher(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v expenditure.voucher; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO v FROM expenditure.voucher WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such voucher' USING ERRCODE = '23503'; END IF;
    IF v.stage <> 'CLEARED' THEN RAISE EXCEPTION 'voucher % is not cleared for payment', v.reference USING ERRCODE = '23514'; END IF;
    IF who IS NULL OR (office <> 'bursar' AND office <> 'super') THEN
        RAISE EXCEPTION 'a voucher is paid by the Bursary' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM expenditure.voucher_query WHERE voucher_id = p_id AND answer IS NULL) THEN
        RAISE EXCEPTION 'a query stands against % and it cannot be paid until answered', v.reference USING ERRCODE = '23514';
    END IF;
    UPDATE expenditure.voucher SET stage = 'PAID', paid_at = now(), paid_by = who WHERE id = p_id;
END $$;

CREATE OR REPLACE FUNCTION expenditure.reject_voucher(p_id uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a voucher is rejected by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_why), '') = '' THEN RAISE EXCEPTION 'a rejection is recorded with its reason' USING ERRCODE = '23514'; END IF;
    UPDATE expenditure.voucher SET stage = 'REJECTED', rejected_why = btrim(p_why)
     WHERE id = p_id AND stage NOT IN ('PAID','REJECTED');
    IF NOT FOUND THEN RAISE EXCEPTION 'voucher cannot be rejected from its current stage' USING ERRCODE = '23514'; END IF;
END $$;
