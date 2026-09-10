-- ═══════════════════════════════════════════════════════════════════════════
-- V076 — procurement requisitions, stores & fixed assets, and research grants
--
--   A requisition sets the procurement method from its value and cannot override
--   it: under 2.5m goes to quotation, 2.5m–25m to restricted tender, above 25m to
--   open competitive bidding. Stores holds consumable inventory and the fixed-asset
--   register — each asset carrying the date it was last physically verified, which
--   is what the audit directorate reads. Research grants are the money the University
--   administers on behalf of a sponsor. Every act is attributed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── procurement requisitions ──
CREATE TABLE expenditure.requisition (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference     text NOT NULL UNIQUE,
    item          text NOT NULL,
    description   text NULL,
    cost_centre   text NOT NULL,
    value         numeric(16,2) NOT NULL,
    state         text NOT NULL DEFAULT 'RAISED',
    note          text NULL,
    raised_by     uuid NULL,
    raised_at     timestamptz NOT NULL DEFAULT now(),
    decided_by    uuid NULL,
    decided_at    timestamptz NULL,
    decision_note text NULL,
    CONSTRAINT ck_rq_state CHECK (state IN ('RAISED','APPROVED','PO_RAISED','CLOSED','REJECTED')),
    CONSTRAINT ck_rq_value CHECK (value > 0),
    CONSTRAINT ck_rq_two_people CHECK (decided_by IS NULL OR decided_by <> raised_by OR state = 'REJECTED')
);
CREATE INDEX ix_rq_state ON expenditure.requisition (state, raised_at DESC);
SELECT audit.attach('expenditure.requisition');

-- the method is set by value and cannot be overridden
CREATE OR REPLACE FUNCTION expenditure.procurement_method(p_value numeric)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_value < 2500000 THEN 'QUOTATION'
                WHEN p_value <= 25000000 THEN 'RESTRICTED_TENDER'
                ELSE 'OPEN_BIDDING' END
$$;

-- ── stores: consumable inventory ──
CREATE TABLE expenditure.store_item (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code          text NOT NULL UNIQUE,
    name          text NOT NULL,
    unit          text NOT NULL DEFAULT 'each',
    quantity      numeric(14,2) NOT NULL DEFAULT 0,
    reorder_level numeric(14,2) NULL,
    location      text NULL,
    note          text NULL,
    CONSTRAINT ck_si_qty CHECK (quantity >= 0)
);
SELECT audit.attach('expenditure.store_item');

-- ── the fixed-asset register ──
CREATE TABLE expenditure.asset (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tag              text NOT NULL UNIQUE,
    name             text NOT NULL,
    category         text NULL,
    location         text NULL,
    acquired_on      date NULL,
    cost             numeric(16,2) NULL,
    condition        text NOT NULL DEFAULT 'GOOD',
    last_verified_on date NULL,
    note             text NULL,
    CONSTRAINT ck_as_condition CHECK (condition IN ('GOOD','FAIR','POOR','DISPOSED'))
);
CREATE INDEX ix_asset_verified ON expenditure.asset (last_verified_on);
SELECT audit.attach('expenditure.asset');

-- ── research grants ──
CREATE TABLE expenditure.research_grant (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference              text NOT NULL UNIQUE,
    title                  text NOT NULL,
    principal_investigator text NOT NULL,
    sponsor                text NOT NULL,
    amount                 numeric(16,2) NOT NULL,
    currency               text NOT NULL DEFAULT 'NGN',
    starts_on              date NULL,
    ends_on                date NULL,
    state                  text NOT NULL DEFAULT 'ACTIVE',
    note                   text NULL,
    CONSTRAINT ck_rg_state CHECK (state IN ('PROPOSED','ACTIVE','COMPLETED','CLOSED','SUSPENDED')),
    CONSTRAINT ck_rg_amount CHECK (amount >= 0)
);
CREATE INDEX ix_rg_state ON expenditure.research_grant (state);
SELECT audit.attach('expenditure.research_grant');

COMMIT;
