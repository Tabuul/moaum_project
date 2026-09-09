-- ═══════════════════════════════════════════════════════════════════════════
-- V046 — tenders: evaluation and award
--
--   A procurement's method is set by its value: under ₦2.5m goes to quotation,
--   ₦2.5m–₦25m to a restricted tender, above ₦25m to open competitive bidding.
--   Bids are scored on a technical threshold before price is looked at, so the
--   lowest bid is not automatically the winner: a bid below the threshold, or
--   one with an expired tax clearance, is not responsive, and the reason is
--   recorded against it. Award goes to the lowest responsive bid unless the
--   Board records why it does not, and only a responsive bid can be awarded.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE expenditure.tender (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference           text NOT NULL UNIQUE,
    subject             text NOT NULL,
    cost_centre         text NULL,
    estimate            numeric(16,2) NOT NULL,
    method              text NOT NULL,
    technical_threshold int  NOT NULL DEFAULT 70,
    stage               text NOT NULL DEFAULT 'ADVERTISED',
    opened_by           uuid NOT NULL,
    opened_at           timestamptz NOT NULL DEFAULT now(),
    awarded_bid         uuid NULL,
    awarded_why         text NULL,
    cancelled_why       text NULL,
    CONSTRAINT ck_tender_estimate CHECK (estimate > 0),
    CONSTRAINT ck_tender_method CHECK (method IN ('QUOTATION','RESTRICTED','OPEN')),
    CONSTRAINT ck_tender_stage CHECK (stage IN ('ADVERTISED','EVALUATED','AWARDED','CANCELLED'))
);
CREATE INDEX ix_tender_stage ON expenditure.tender (stage, opened_at DESC);
SELECT audit.attach('expenditure.tender');

CREATE TABLE expenditure.bid (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tender_id       uuid NOT NULL REFERENCES expenditure.tender(id),
    bidder          text NOT NULL,
    price           numeric(16,2) NOT NULL,
    technical_score int  NULL,
    responsive      boolean NULL,
    reason          text NULL,
    submitted_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_bid_price CHECK (price > 0)
);
CREATE INDEX ix_bid_tender ON expenditure.bid (tender_id);
SELECT audit.attach('expenditure.bid');

CREATE OR REPLACE FUNCTION expenditure.tender_method(p_estimate numeric)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_estimate < 2500000 THEN 'QUOTATION' WHEN p_estimate <= 25000000 THEN 'RESTRICTED' ELSE 'OPEN' END;
$$;

CREATE OR REPLACE FUNCTION expenditure.open_tender(p_subject text, p_cost_centre text, p_estimate numeric, p_threshold int)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_ref text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a tender is opened by a person' USING ERRCODE = '23514'; END IF;
    IF p_estimate IS NULL OR p_estimate <= 0 THEN RAISE EXCEPTION 'a tender carries an estimate' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_subject), '') = '' THEN RAISE EXCEPTION 'a tender says what is being procured' USING ERRCODE = '23514'; END IF;
    v_ref := 'TN/' || to_char(current_date, 'YYYY') || '/' ||
             lpad(platform.next_number('TENDER', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0');
    INSERT INTO expenditure.tender (reference, subject, cost_centre, estimate, method, technical_threshold, opened_by)
    VALUES (v_ref, btrim(p_subject), nullif(btrim(coalesce(p_cost_centre, '')), ''), p_estimate,
            expenditure.tender_method(p_estimate), coalesce(p_threshold, 70), who);
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION expenditure.add_bid(p_tender uuid, p_bidder text, p_price numeric)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE t expenditure.tender; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_id uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a bid is recorded by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM expenditure.tender WHERE id = p_tender;
    IF NOT FOUND OR t.stage <> 'ADVERTISED' THEN RAISE EXCEPTION 'tender is not open for bids' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_bidder), '') = '' OR p_price IS NULL OR p_price <= 0 THEN
        RAISE EXCEPTION 'a bid names the bidder and a price' USING ERRCODE = '23514';
    END IF;
    INSERT INTO expenditure.bid (tender_id, bidder, price) VALUES (p_tender, btrim(p_bidder), p_price) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- score a bid; responsive is the technical threshold unless a reason overrides it (e.g. expired tax clearance)
CREATE OR REPLACE FUNCTION expenditure.score_bid(p_bid uuid, p_technical int, p_responsive boolean, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE b expenditure.bid; t expenditure.tender; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_resp boolean;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a bid is evaluated by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM expenditure.bid WHERE id = p_bid;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such bid' USING ERRCODE = '23503'; END IF;
    SELECT * INTO t FROM expenditure.tender WHERE id = b.tender_id;
    IF t.stage NOT IN ('ADVERTISED','EVALUATED') THEN RAISE EXCEPTION 'this tender is closed to evaluation' USING ERRCODE = '23514'; END IF;
    v_resp := CASE WHEN p_responsive IS NOT NULL THEN p_responsive
                   WHEN p_technical IS NULL THEN false
                   ELSE p_technical >= t.technical_threshold END;
    IF NOT v_resp AND coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a bid found not responsive carries the reason it failed' USING ERRCODE = '23514';
    END IF;
    UPDATE expenditure.bid SET technical_score = p_technical, responsive = v_resp, reason = nullif(btrim(coalesce(p_reason, '')), '')
     WHERE id = p_bid;
    UPDATE expenditure.tender SET stage = 'EVALUATED' WHERE id = b.tender_id AND stage = 'ADVERTISED';
END $$;

CREATE OR REPLACE FUNCTION expenditure.award_tender(p_tender uuid, p_bid uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t expenditure.tender; b expenditure.bid; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a tender is awarded by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM expenditure.tender WHERE id = p_tender FOR UPDATE;
    IF NOT FOUND OR t.stage <> 'EVALUATED' THEN RAISE EXCEPTION 'tender % is not evaluated and ready to award', p_tender USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM expenditure.bid WHERE id = p_bid AND tender_id = p_tender;
    IF NOT FOUND THEN RAISE EXCEPTION 'that bid is not on this tender' USING ERRCODE = '23503'; END IF;
    IF b.responsive IS NOT TRUE THEN
        RAISE EXCEPTION 'a tender is awarded only to a responsive bid' USING ERRCODE = '23514',
            HINT = 'A bid below the technical threshold or with an invalid clearance cannot be awarded.';
    END IF;
    -- if this is not the lowest responsive bid, the Board must say why
    IF EXISTS (SELECT 1 FROM expenditure.bid o WHERE o.tender_id = p_tender AND o.responsive IS TRUE AND o.price < b.price)
       AND coalesce(btrim(p_why), '') = '' THEN
        RAISE EXCEPTION 'a lower responsive bid exists; the award records why it is not taken' USING ERRCODE = '23514';
    END IF;
    UPDATE expenditure.tender SET stage = 'AWARDED', awarded_bid = p_bid, awarded_why = nullif(btrim(coalesce(p_why, '')), '')
     WHERE id = p_tender;
END $$;

CREATE OR REPLACE FUNCTION expenditure.cancel_tender(p_tender uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a tender is cancelled by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_why), '') = '' THEN RAISE EXCEPTION 'a cancellation is recorded with its reason' USING ERRCODE = '23514'; END IF;
    UPDATE expenditure.tender SET stage = 'CANCELLED', cancelled_why = btrim(p_why) WHERE id = p_tender AND stage NOT IN ('AWARDED','CANCELLED');
    IF NOT FOUND THEN RAISE EXCEPTION 'tender cannot be cancelled from its current stage' USING ERRCODE = '23514'; END IF;
END $$;
