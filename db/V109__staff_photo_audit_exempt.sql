-- ── V109 — exempt the staff photograph blob from the audit spine ────────────
-- Recovery for a migrate-ledger halt. V107, as it first applied to production,
-- created hrm.staff_photo but did not exempt it from the audit spine. The
-- exemption was added to V107 afterwards, which changed the file's checksum and
-- halted the ledger (the API's pre-deploy migrate then failed on every deploy,
-- so nothing after V107 went live). V107 has been restored to the exact bytes
-- production applied, and the one thing the edit added — the staff_photo
-- exemption — moved here, so an existing database and a fresh one converge:
-- the photograph's heavy bytes are kept off the spine like every other blob,
-- its metadata carried on the audited hrm.staff_profile.
--
-- audit.exempt upserts (ON CONFLICT (relid) DO UPDATE), so this is safe whether
-- or not the table was already exempt.
SELECT audit.exempt('hrm.staff_photo',
    'The staff photograph itself, up to 2 MB; a heavy blob kept off the spine like every other, replaced whole by its owner through hrm.set_my_staff_photo.');
