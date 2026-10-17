-- V529: unusual exports told to Internal Audit, and the documents the server builds on the export log.
--
-- V523 put every report exported through the browser's export engine on platform.export_log, but nobody was told of anything on
-- it. Now an export is unusual when it is large (row_count at or above the watch's large_rows, 1,000 by default) or when the same
-- person has made burst_count exports (15) within burst_minutes (60): the holders of Internal Audit's offices (audit, deputyaudit)
-- are told by e-mail and on the portal (EXPORT_UNUSUAL), with who, which office, the report, the rows, the serial and why, once for
-- each large export and once as a person reaches the burst — never the person who made it. The telling never costs the log its
-- row: if it fails, the export stays recorded. Internal Audit (and super) set the watch on the Export Log screen; every change to it
-- is on the audit spine.
--
-- And the reports the portal's own server builds — the paid applicants list, the JUPEB examination list, the postgraduate summary,
-- a lecturer's score sheet and marked sheet, a kept copy sent by e-mail and the CCE batch report — are recorded too, as PDF or CSV
-- as well as Excel and print.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'super', true);
SELECT set_config('moaum.reason', 'V529: unusual exports told to Internal Audit', true);

-- the documents the server builds: PDF and CSV as well
ALTER TABLE platform.export_log DROP CONSTRAINT export_log_format_check;
ALTER TABLE platform.export_log ADD CONSTRAINT export_log_format_check CHECK (format IN ('XLSX', 'PRINT', 'PDF', 'CSV'));

CREATE OR REPLACE FUNCTION platform.log_export(p_report text, p_format text, p_rows integer, p_filters jsonb, p_screen text, p_serial text)
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
    -- V529: a PDF or CSV the server builds as well as an Excel workbook or a print
    IF upper(coalesce(p_format, '')) NOT IN ('XLSX', 'PRINT', 'PDF', 'CSV') THEN
        RAISE EXCEPTION 'EXPORT_LOG_FORMAT: an export is an Excel workbook (XLSX), a print (PRINT), a PDF or a CSV file' USING ERRCODE = '23514';
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

-- the watch: what makes an export unusual
CREATE TABLE platform.export_watch (
    id             integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    enabled        boolean NOT NULL DEFAULT true,
    large_rows     integer NOT NULL DEFAULT 1000 CHECK (large_rows BETWEEN 10 AND 1000000),
    burst_count    integer NOT NULL DEFAULT 15 CHECK (burst_count BETWEEN 2 AND 1000),
    burst_minutes  integer NOT NULL DEFAULT 60 CHECK (burst_minutes BETWEEN 5 AND 1440),
    updated_by     uuid NULL,
    updated_office text NULL,
    updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE platform.export_watch IS
  'V529: when an export is unusual — at least large_rows rows, or the same person''s burst_count exports within burst_minutes — and so told to Internal Audit; set by Internal Audit or super';
INSERT INTO platform.export_watch (id) VALUES (1);
SELECT audit.attach('platform.export_watch');

-- whether an export on the log is unusual, under the watch as it stands
CREATE FUNCTION platform.export_unusual(p_id uuid)
RETURNS TABLE(large boolean, burst boolean, in_window integer) LANGUAGE sql STABLE AS $$
    SELECT l.row_count >= w.large_rows,
           n.k >= w.burst_count,
           n.k
      FROM platform.export_log l
      CROSS JOIN platform.export_watch w
      CROSS JOIN LATERAL (SELECT count(*)::int AS k FROM platform.export_log x
                           WHERE x.person_id = l.person_id AND x.at <= l.at AND x.at > l.at - make_interval(mins => w.burst_minutes)) n
     WHERE l.id = p_id AND w.id = 1
$$;

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('EXPORT_UNUSUAL', 'Unusual export',
 'To Internal Audit (the Director and the Deputy Director of Audit) when someone exports a large report, or many reports in a short time; once for each large export and once as a person reaches the limit',
 'Unusual export: [REPORT] by [WHO]',
 E'Dear [FIRST_NAME],\n\n[WHO], acting as [OFFICE], exported "[REPORT]" ([FORMAT], [ROWS] rows) on [AT]: [WHY].\n\nThe serial on the document is [SERIAL]. Nothing has been stopped; this is for you to look at.\n\nThe export log: [SCREEN]\n\n[UNIVERSITY_SHORT]',
 NULL,
 'Unusual export: [REPORT]',
 '[WHO] ([OFFICE]) exported "[REPORT]" — [FORMAT], [ROWS] rows, [AT]: [WHY]. Serial [SERIAL].',
 ARRAY['FIRST_NAME','WHO','OFFICE','REPORT','FORMAT','ROWS','AT','WHY','SERIAL','SCREEN','PORTAL_URL','UNIVERSITY_SHORT'], true, 'HIGH')
ON CONFLICT (key) DO NOTHING;

-- an unusual export is told to Internal Audit as it is recorded; the telling never costs the log its row
CREATE FUNCTION platform.export_watch_tell() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE w platform.export_watch; v_n int; v_large boolean; v_burst boolean; v_vars jsonb; r record;
BEGIN
    SELECT * INTO w FROM platform.export_watch WHERE id = 1;
    IF NOT FOUND OR NOT w.enabled THEN
        RETURN NULL;
    END IF;
    v_large := NEW.row_count >= w.large_rows;
    SELECT count(*) INTO v_n FROM platform.export_log x
     WHERE x.person_id = NEW.person_id AND x.at <= NEW.at AND x.at > NEW.at - make_interval(mins => w.burst_minutes);
    v_burst := v_n = w.burst_count;   -- told once, as the person reaches the limit
    IF NOT v_large AND NOT v_burst THEN
        RETURN NULL;
    END IF;
    BEGIN
        v_vars := jsonb_build_object(
            'WHO', coalesce((SELECT p.surname || ', ' || p.given_names || coalesce(' (' || p.staff_number || ')', '') FROM iam.person p WHERE p.id = NEW.person_id),
                            (SELECT st.surname || ', ' || st.other_names || coalesce(' (' || coalesce(st.matric_no, st.admission_no) || ')', '')
                               FROM people.student st WHERE st.person_id = NEW.person_id LIMIT 1),
                            'someone not on the staff register'),
            'OFFICE', coalesce((SELECT o.label FROM ref.office o WHERE o.code = NEW.office), NEW.office),
            'REPORT', NEW.report,
            'FORMAT', CASE NEW.format WHEN 'XLSX' THEN 'Excel' WHEN 'PRINT' THEN 'print / PDF' ELSE NEW.format END,
            'ROWS', to_char(NEW.row_count, 'FM999,999,999'),
            'AT', to_char(NEW.at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY, HH24:MI'),
            'WHY', concat_ws(', and ',
                             CASE WHEN v_large THEN format('%s rows, at or above the watch''s %s', to_char(NEW.row_count, 'FM999,999,999'), to_char(w.large_rows, 'FM999,999,999')) END,
                             CASE WHEN v_burst THEN format('their %s exports within %s minutes', v_n, w.burst_minutes) END),
            'SERIAL', coalesce(NEW.serial, 'none'),
            'SCREEN', coalesce(platform.portal_url(), '') || '/audit/exports?unusual=1');
        FOR r IN SELECT DISTINCT a.person_id
                   FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
                  WHERE a.office_code IN ('audit', 'deputyaudit') AND p.ended_on IS NULL AND a.person_id <> NEW.person_id
                    AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
            PERFORM platform.tell_person(r.person_id, 'EXPORT_UNUSUAL', NULL, v_vars,
                                         CASE WHEN v_large THEN 'export-large:' ELSE 'export-burst:' END || NEW.id::text);
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'the unusual export % was not told to Internal Audit: %', NEW.id, SQLERRM;
    END;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_export_watch_tell AFTER INSERT ON platform.export_log
    FOR EACH ROW EXECUTE FUNCTION platform.export_watch_tell();

COMMIT;
