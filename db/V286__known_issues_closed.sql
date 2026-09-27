-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V286 — the known issues of the status report closed on the database side
--
--   · platform.chain_verification: the nightly recomputation of the audit chain leaves its result
--     here (per period and shard), so "verified nightly" is a fact the Security page reads, and a
--     break reaches the Registrar and the Directorate of ICT.
--   · people.change_status tells the student: every change of status on the register — withdrawal,
--     graduation, suspension, reinstatement — was silent; it now goes to the student by email and
--     SMS with the instrument and the reason.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V286: the known issues closed — chain verification log, status changes told', true);

CREATE TABLE IF NOT EXISTS platform.chain_verification (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_at      timestamptz NOT NULL DEFAULT now(),
    trigger     text NOT NULL DEFAULT 'NIGHTLY',
    period      date,
    shard       smallint,
    entries     bigint NOT NULL DEFAULT 0,
    ok          boolean NOT NULL,
    first_break uuid,
    broke_at    timestamptz,
    run_ref     uuid NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_chain_verification_run ON platform.chain_verification (run_at DESC);
COMMENT ON TABLE platform.chain_verification IS 'Each run of audit.verify_chain, nightly or on demand, per period and shard: whether the chain held, and where it first broke (V286). The verifier''s own log; not itself on the spine.';
SELECT audit.exempt('platform.chain_verification', 'The chain verifier''s own log: derived from the spine it checks; re-derived at every run.');
GRANT SELECT, INSERT ON platform.chain_verification TO app_student;

CREATE OR REPLACE FUNCTION people.change_status(p_student uuid, p_to text, p_instrument text, p_effective date, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_from text; reach record; word text;
BEGIN
    SELECT status INTO v_from FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no student %', p_student USING ERRCODE = 'no_data_found';
    END IF;
    IF p_instrument IS NULL OR btrim(p_instrument) = '' THEN
        RAISE EXCEPTION 'a change of status is made on an instrument — the Senate minute, the letter, the Registrar''s decision — and none was cited'
            USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
    VALUES (gen_random_uuid(), p_student, v_from, p_to, p_instrument, p_effective, p_reason);
    UPDATE people.student SET status = p_to WHERE id = p_student;
    -- the student is told (V286): the change, the instrument it was made on, the reason, and the day it takes effect
    word := CASE p_to WHEN 'GRADUATED' THEN 'You have graduated.' WHEN 'WITHDRAWN' THEN 'You have been withdrawn from the University.'
                      WHEN 'VOLUNTARY_WITHDRAWAL' THEN 'Your record was closed as a voluntary withdrawal.' WHEN 'SUSPENDED' THEN 'You have been suspended.'
                      WHEN 'RUSTICATED' THEN 'You have been rusticated.' WHEN 'EXPELLED' THEN 'You have been expelled.' WHEN 'DEFERRED' THEN 'Your studies are deferred.'
                      WHEN 'ACTIVE' THEN 'You are an active student on the register.' WHEN 'PROBATION' THEN 'You are on probation.' WHEN 'DORMANT' THEN 'Your record is dormant.'
                      WHEN 'TRANSFERRED_OUT' THEN 'Your transfer out of the University is recorded.' ELSE 'Your status is now ' || lower(replace(p_to, '_', ' ')) || '.' END;
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your status on the University register: ' || initcap(replace(p_to, '_', ' ')),
        word || E'\n\nFrom: ' || initcap(replace(coalesce(v_from, ''), '_', ' ')) || E'\nTo: ' || initcap(replace(p_to, '_', ' ')) || E'\nOn the instrument: ' || p_instrument
        || E'\nEffective: ' || to_char(coalesce(p_effective, current_date), 'DD Month YYYY') || coalesce(E'\nReason: ' || nullif(btrim(p_reason), ''), '')
        || E'\n\nIf you believe this is in error, write to the Registrar quoting the instrument.' || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi',
        'student', p_student);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your status on the register',
        'MOAUM: your status on the register is now ' || lower(replace(p_to, '_', ' ')) || ' (' || left(p_instrument, 60) || '). See the portal.', 'student', p_student);
END $fn$;

COMMIT;
