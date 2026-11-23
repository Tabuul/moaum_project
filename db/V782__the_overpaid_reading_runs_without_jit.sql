-- V782. The overpaid school fees reading runs with jit = off.
--
-- What CI showed. V781 (the Overpaid School Fees desk) was pushed as 403db98c and its CI run was cancelled by the time limits of two
-- jobs: the Database job's property suite took 23 minutes against 6–8, and the API job's OverpaidReconciliationIT had not finished
-- after six minutes against 15 seconds on the developer's machine. The portal's own log said why: finance.overpaid_refresh worked
-- out a session in 10,530 ms, then 10,707 ms, then 10,591 ms — for sessions with no student, two students and eight students.
-- A cost that does not follow the work is a compile, not a read.
--
-- Why. CI's database is PostgreSQL 17 from the Docker image, whose JIT is available and on (jit_above_cost 100,000, jit_optimize_above_cost
-- 500,000); the developer's Windows build of PostgreSQL has no JIT (pg_jit_available() is false), so nothing here ever compiled. On a
-- database whose tables have never been analysed (every CI run, and a database just restored) the planner's estimate for the main
-- statement of finance.overpaid_read — the five leaf reads (V781's fee_profiles_of … possible_double_charges_of) behind a materialised
-- CTE, joined to the decisions, the holds and the bank's list — is a total cost of 1.6e10 (281,813 rows estimated; auto_explain on a
-- migrated, never-analysed copy), which is above every JIT threshold, so each call compiled and optimised the whole statement: 10 s
-- on a two-core runner, again on every call because a custom plan is made for each call. On the live database the same call has a
-- good estimate but the same shape; V652 and V663 found the same on the live-shaped copy ("the JIT compile took 1–2 s of a 0.x s
-- read") and turned JIT off for the reads concerned. This does the same for the overpaid reading and for every function that runs it
-- or stands on it.
--
-- What it changes. Nothing a student, an officer or an auditor can see but time: ALTER FUNCTION … SET jit = off on the functions named
-- below (the setting applies to every statement run inside the function and is put back when it returns, so a caller's own statements
-- are untouched). No function's text, signature, result or locking changes. A function with a SET clause is not inlined into a calling
-- statement, so only reads that are never inlined are listed: the plpgsql functions, and the set-returning or aggregate SQL functions
-- the API and the desk call as a whole.
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V782: the overpaid reading runs with jit = off', true);

DO $v782$
DECLARE
    v_names text[] := ARRAY[
        -- V781's reads of a session and of the students asked for
        'fee_profiles_of', 'fee_sums_of', 'session_charges_of', 'session_payments_of', 'possible_double_charges_of',
        'overpaid_of', 'overpaid_read', 'overpaid',
        -- the kept list, the desk and the dashboard's figures
        'overpaid_refresh', 'overpaid_refresh_due', 'overpaid_desk', 'overpaid_figures',
        -- the requests, their approval and what a credit writes
        'overpaid_credits_request', 'overpaid_credits_decide', 'overpaid_credits_withdraw', 'overpaid_credit_post',
        -- the readings the Fees tab, the wallet and the refund desk stand on
        'withdrawal_sources', 'student_excess', 'overpayment_shortfall',
        -- the older acts and reads V781 restated, each of which reads the overpaid money of a student or a session
        'decide_overpayments', 'legacy_credit_excess', 'legacy_credit_initiate', 'legacy_credit_resubmit', 'legacy_credit_decide',
        'legacy_credit_rows', 'legacy_reconciliation_figures'];
    v_name text; r record; v_done int := 0;
BEGIN
    FOREACH v_name IN ARRAY v_names LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'finance'::regnamespace AND p.proname = v_name) THEN
            RAISE EXCEPTION 'V782: finance.% is not there (the overpaid reading is not as V781 left it)', v_name;
        END IF;
        FOR r IN SELECT p.oid::regprocedure AS fn FROM pg_proc p WHERE p.pronamespace = 'finance'::regnamespace AND p.proname = v_name LOOP
            EXECUTE format('ALTER FUNCTION %s SET jit = off', r.fn);
            v_done := v_done + 1;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'V782: jit = off set on % function(s) of the overpaid reading', v_done;
END $v782$;

COMMIT;
