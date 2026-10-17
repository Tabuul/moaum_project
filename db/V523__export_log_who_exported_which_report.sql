-- V523: the export log — who exported which report, when, from which office, with which filters and how many rows.
--
-- Every report the portal hands a user to download or print goes through one engine (frontend lib/exportbrand: brandedXlsx and
-- brandedPrint, V320), which brands it and gives it a serial. The audit trail records changes, not reads, so until now nobody
-- could say who took a copy of the student register, the payments or a result sheet out of the portal. Now each export is
-- recorded as it is made: the person and the office they acted in (from the request's audit context, never from the screen),
-- the report's title, the format (an Excel workbook, or a print / PDF), the number of rows, the filters it was drawn with, the
-- screen it came from and the serial printed on the document — so a copy found anywhere can be traced to who made it.
--
-- The log is append-only (no update, no delete) and on the audit spine, so the sealed chain holds each entry too. Internal
-- Audit (and the Deputy Director of Audit and super) read it on the Export Log screen.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'super', true);
SELECT set_config('moaum.reason', 'V523: the export log', true);

CREATE TABLE platform.export_log (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at        timestamptz NOT NULL DEFAULT now(),
    person_id uuid NOT NULL,
    office    text NOT NULL REFERENCES ref.office (code),
    report    text NOT NULL CHECK (btrim(report) <> '' AND length(report) <= 300),
    format    text NOT NULL CHECK (format IN ('XLSX', 'PRINT')),
    row_count integer NOT NULL CHECK (row_count >= 0),
    filters   jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(filters) = 'object' AND length(filters::text) <= 4000),
    screen    text NULL CHECK (length(screen) <= 500),
    serial    text NULL CHECK (length(serial) <= 120)
);
COMMENT ON TABLE platform.export_log IS
  'V523: every report exported through the portal''s export engine — the person and office (from the audit context), the report, XLSX or PRINT (print / PDF), the rows, the filters, the screen and the serial on the document; append-only';
CREATE INDEX ix_export_log_at ON platform.export_log (at DESC);
CREATE INDEX ix_export_log_person ON platform.export_log (person_id, at DESC);
SELECT audit.attach('platform.export_log');

-- nothing is changed or taken out of the log
CREATE FUNCTION platform.export_log_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'EXPORT_LOG_APPEND_ONLY: the export log is kept as it was written'
        USING ERRCODE = '42501';
END $$;
CREATE TRIGGER trg_export_log_append_only BEFORE UPDATE OR DELETE ON platform.export_log
    FOR EACH ROW EXECUTE FUNCTION platform.export_log_append_only();

-- an export, recorded for the person and office acting (the request's audit context); the screen says only what it exported
CREATE FUNCTION platform.log_export(p_report text, p_format text, p_rows integer, p_filters jsonb, p_screen text, p_serial text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_filters jsonb := CASE WHEN jsonb_typeof(p_filters) = 'object' THEN p_filters ELSE '{}'::jsonb END;
        v_id uuid;
BEGIN
    IF v_actor IS NULL OR v_office IS NULL THEN
        RAISE EXCEPTION 'EXPORT_LOG_NO_ACTOR: an export is recorded for a signed-in person' USING ERRCODE = '42501';
    END IF;
    IF p_report IS NULL OR btrim(p_report) = '' THEN
        RAISE EXCEPTION 'EXPORT_LOG_NO_REPORT: name the report exported' USING ERRCODE = '23514';
    END IF;
    IF upper(coalesce(p_format, '')) NOT IN ('XLSX', 'PRINT') THEN
        RAISE EXCEPTION 'EXPORT_LOG_FORMAT: an export is an Excel workbook (XLSX) or a print / PDF (PRINT)' USING ERRCODE = '23514';
    END IF;
    -- a screen's filters are kept as they were given, up to the column's bound; more than that is cut to what fits
    IF length(v_filters::text) > 4000 THEN
        v_filters := jsonb_build_object('truncated', left(v_filters::text, 3900));
    END IF;
    PERFORM set_config('moaum.reason', 'exported ' || left(btrim(p_report), 200), true);
    INSERT INTO platform.export_log (person_id, office, report, format, row_count, filters, screen, serial)
    VALUES (v_actor, v_office, left(btrim(p_report), 300), upper(p_format), greatest(coalesce(p_rows, 0), 0), v_filters,
            nullif(left(btrim(coalesce(p_screen, '')), 500), ''), nullif(left(btrim(coalesce(p_serial, '')), 120), ''))
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

COMMIT;
