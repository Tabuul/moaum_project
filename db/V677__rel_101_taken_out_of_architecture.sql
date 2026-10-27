-- ═══════════════════════════════════════
-- V677 — REL 101 Hebrew Grammar taken out of B.Sc. Architecture's 100 Level structure
--
-- The University's word of 27 October 2026 ("remove REL 101 from architecture"). REL 101 Hebrew Grammar, a Religious Studies course,
-- was bound on 5 October 2026 as a 100 Level core course of B. Sc. ARCHITECTURE (C51900); it is not in the Department of
-- Architecture's programme structure. On the live-shaped copy of 21 October 2026 no Architecture student had registered it.
--
-- Ended the way Course Management ends a binding: catalogue.unbind_offer — the binding kept on catalogue.course_offer_history with who
-- ended it and why; a registration made on it is kept as it was made (V620). The course itself, and the other programmes that take it
-- (Religious Studies, Religion and Philosophy, History, Theatre Arts, Philosophy, Education Religious Studies), are untouched. Where
-- the binding is not there, nothing is done.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V677: REL 101 Hebrew Grammar taken out of B.Sc. Architecture', true);

DO $$
DECLARE v_outcome text;
BEGIN
    IF EXISTS (SELECT 1 FROM catalogue.course_offer WHERE course_code = 'REL 101' AND programme_code = 'C51900' AND level = 100) THEN
        v_outcome := catalogue.unbind_offer('REL 101', 'C51900', 100,
            'The University''s word of 27 October 2026: REL 101 Hebrew Grammar is not a course of B.Sc. Architecture (V677)');
        RAISE NOTICE 'V677: REL 101 taken out of B.Sc. Architecture at 100 Level (%)', v_outcome;
    ELSE
        RAISE NOTICE 'V677: REL 101 is not bound to B.Sc. Architecture here; nothing to do';
    END IF;
END $$;

COMMIT;
