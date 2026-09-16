-- ═══════════════════════════════════════════════════════════════════════════
-- V146 — put finance.gl_posting on the audit spine
--
--   V145 attached the chart of accounts and the journal, but not the posting
--   lines, so check.sql's "every state table is attached to the spine" failed.
--   A posting is financial state (a debit or a credit), written only by
--   finance.gl_post in the same transaction as its journal — which is already
--   attached and so already demands the actor context. Attaching the lines too
--   therefore adds no new requirement, and gives the books a per-line trail.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT audit.attach('finance.gl_posting');

COMMIT;
