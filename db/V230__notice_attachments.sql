-- ═══════════════════════════════════════════════════════════════════════════
-- V230 — a notice may carry attachments
--
--   The outbox (platform.notice, V025) carries a subject and a body. A return
--   sent to Council, NUC or a Dean goes with the file itself — the kept copy
--   as a PDF and as an Excel workbook — so a notice may now carry attachments,
--   queued in the same transaction and taken by the dispatcher with the
--   notice. Attachments belong to the notice they were queued with; a notice
--   deleted takes them. State, so on the spine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE platform.notice_attachment (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    notice_id    uuid NOT NULL REFERENCES platform.notice(id) ON DELETE CASCADE,
    filename     text NOT NULL,
    content_type text NOT NULL,
    content      bytea NOT NULL,
    size_bytes   int  NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_notice_attachment_size CHECK (size_bytes BETWEEN 1 AND 15000000),
    CONSTRAINT ck_notice_attachment_name CHECK (filename !~ '[/\\]' AND length(filename) BETWEEN 1 AND 200)
);
CREATE INDEX ix_notice_attachment_notice ON platform.notice_attachment (notice_id);
SELECT audit.attach('platform.notice_attachment');

COMMENT ON TABLE platform.notice_attachment IS
  'A file queued with a notice: taken by the dispatcher with the notice, sent as a mail attachment.';

COMMIT;
