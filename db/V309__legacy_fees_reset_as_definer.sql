-- V309 — the old-portal fees reset runs as the schema owner.
--
-- finance.reset_legacy_payments (V305) deletes the import's own payment rows. It ran with the
-- caller's privileges, which works only because the API connects as the database owner today;
-- an application role holds DELETE nowhere (verify.sql asserts it), so the same call from a
-- module role would be refused. The function now runs as its owner with a fixed search_path,
-- exactly as the audit trigger does; the guards inside it (a named actor, the word RESET,
-- only channel 'Legacy' and MOAUM-LEG- references, deferment-linked rows kept) are unchanged.

BEGIN;

ALTER FUNCTION finance.reset_legacy_payments(text, text)
    SECURITY DEFINER
    SET search_path = pg_catalog, finance, people, public;

COMMIT;
