-- V658: collaboration and partnership management — the University's master prompt of 25 October 2026 ("UNIVERSITY COLLABORATION &
-- PARTNERSHIP MANAGEMENT SYSTEM"): local and international organisations propose a collaboration on a public form; the University
-- acknowledges it, screens, routes and assigns it, reviews it with the offices concerned, asks for more where needed, checks it,
-- decides, develops and executes an agreement, and follows the partnership through to its outcomes and closure. One central record,
-- one controlled workflow, the University's answers of 25 October 2026:
--   · a new office owns every proposal — linkages, "Director, Linkages & Partnerships" — with configurable desks inside it (Research &
--     Innovation, International Relations, Industry Liaison, Advancement & Development, Community & Government Engagement, general);
--     the existing offices review what they are asked to (a Dean their faculty's, a Head their department's, the Registrar, the
--     Bursar, the DVC, the PG School, ICT, Student Affairs, the Academic Office), and a new office, legal ("University Legal Officer"),
--     reviews agreements;
--   · the Vice-Chancellor approves (the DVC may act for the VC): a proposal for development, and an agreement before it is signed;
--   · the public reference is PTN/YYYY/NNNNNN, an agreement's PTN-AGR/YYYY/NNNNNN, from platform.next_number (never MAX()+1).
-- Nothing here is a legal conclusion: the compliance flags are flags for review; submitting creates no partnership and no commitment.
--
--   · partnership.setting: the public form open or closed, the response times (acknowledgement, screening, review, complex review,
--     the time given to answer a request), the text limits, the file limits, how long a draft is kept, the agreement expiry alert.
--   · partnership.category_group / category: the collaboration categories (Research … Other), configurable; partnership.desk /
--     desk_officer: the Linkages desks and their officers (a desk's lead takes a proposal routed to it); partnership.routing_rule:
--     the first active rule by priority that matches a proposal's category, group, international or local, organisation type or
--     funding names its desk, else the general desk.
--   · partnership.grant: what each office may do (VIEW … MANAGE_PARTNERSHIP_SETTINGS), checked by the API and by the functions;
--     what an office sees (partnership.visible): all where it holds VIEW_ALL_PARTNERSHIPS, else the proposals it owns or is asked
--     to review — a Dean only for the faculty, a Head only for the department named on the request.
--   · partnership.proposal: the central record (the applicant, the organisation, the existing connection, the proposal, funding and
--     resources, international, legal and compliance answers, declarations), its status (DRAFT … CANCELLED), desk, owner, due date,
--     flags and risk; a confidential disclosure of a conflict of interest read only by those allowed (partnership.may_confidential).
--   · partnership.attachment (in the file store), partnership.event (the timeline; applicant-visible or internal), partnership.message
--     (an internal note never leaves the University; a message to the applicant is e-mailed), partnership.info_request,
--     partnership.reviewer, partnership.due_diligence (dd_item checklist), partnership.agreement, partnership.activity,
--     partnership.outcome (outcome_kind).

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'super', true),
       set_config('moaum.reason', 'V658: collaboration and partnership management (the University, 25 October 2026)', true);

CREATE SCHEMA IF NOT EXISTS partnership;
COMMENT ON SCHEMA partnership IS 'V658: collaboration and partnership proposals, from the public enquiry to the active partnership and its closure';

-- ── 1 · the offices ─────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES
    ('linkages', 'Director, Linkages & Partnerships', 'institution'),
    ('legal', 'University Legal Officer', 'institution')
ON CONFLICT (code) DO NOTHING;

-- ── 2 · the settings ────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE partnership.setting (
    id                  integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    public_open         boolean NOT NULL DEFAULT true,
    acknowledge_days    integer NOT NULL DEFAULT 5 CHECK (acknowledge_days BETWEEN 1 AND 60),
    screening_days      integer NOT NULL DEFAULT 10 CHECK (screening_days BETWEEN 1 AND 120),
    review_days         integer NOT NULL DEFAULT 30 CHECK (review_days BETWEEN 1 AND 365),
    complex_review_days integer NOT NULL DEFAULT 60 CHECK (complex_review_days BETWEEN 1 AND 365),
    info_days           integer NOT NULL DEFAULT 14 CHECK (info_days BETWEEN 1 AND 120),
    summary_max         integer NOT NULL DEFAULT 1000 CHECK (summary_max BETWEEN 200 AND 5000),
    text_max            integer NOT NULL DEFAULT 4000 CHECK (text_max BETWEEN 500 AND 20000),
    benefits_max        integer NOT NULL DEFAULT 2000 CHECK (benefits_max BETWEEN 200 AND 10000),
    max_files           integer NOT NULL DEFAULT 5 CHECK (max_files BETWEEN 1 AND 20),
    -- a file travels as text through the portal's front door, which reads 10 MB of a request at most: 7 MB of file is the ceiling
    max_file_mb         integer NOT NULL DEFAULT 5 CHECK (max_file_mb BETWEEN 1 AND 7),
    draft_days          integer NOT NULL DEFAULT 30 CHECK (draft_days BETWEEN 1 AND 180),
    expiry_alert_days   integer NOT NULL DEFAULT 90 CHECK (expiry_alert_days BETWEEN 7 AND 365),
    contact_email       text NULL CHECK (contact_email IS NULL OR contact_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    contact_phone       text NULL,
    set_by              uuid NULL,
    set_office          text NULL,
    set_at              timestamptz NOT NULL DEFAULT now(),
    reason              text NULL
);
INSERT INTO partnership.setting (id) VALUES (1);
SELECT audit.attach('partnership.setting');
COMMENT ON TABLE partnership.setting IS
  'V658: the public form open or closed, the expected response times in working days (acknowledgement, screening, review, complex review, a request answered), the text and file limits, how long an unsent draft is kept and when an agreement''s expiry is first told. Changed by partnership.set_settings.';

-- ── 3 · the categories, desks and routing ───────────────────────────────────────────────────────────────────────────────
CREATE TABLE partnership.category_group (
    code   text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
    label  text NOT NULL CHECK (btrim(label) <> ''),
    sort   integer NOT NULL DEFAULT 100,
    active boolean NOT NULL DEFAULT true
);
SELECT audit.attach('partnership.category_group');
CREATE TABLE partnership.category (
    code   text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,60}$'),
    grp    text NOT NULL REFERENCES partnership.category_group (code),
    label  text NOT NULL CHECK (btrim(label) <> ''),
    sort   integer NOT NULL DEFAULT 100,
    active boolean NOT NULL DEFAULT true
);
SELECT audit.attach('partnership.category');
COMMENT ON TABLE partnership.category IS 'V658: a collaboration category the public form offers, under its group; configured by the Linkages office (partnership.set_category)';

INSERT INTO partnership.category_group (code, label, sort) VALUES
    ('RESEARCH', 'Research', 10), ('ACADEMIC', 'Academic', 20), ('STUDENT_MOBILITY', 'Student mobility', 30),
    ('STAFF_MOBILITY', 'Staff mobility', 40), ('INDUSTRY', 'Industry', 50), ('FUNDING', 'Funding', 60),
    ('COMMUNITY', 'Community', 70), ('RESOURCES', 'Resources', 80), ('EVENTS', 'Events', 90), ('OTHER', 'Other', 100);
INSERT INTO partnership.category (code, grp, label, sort) VALUES
    ('RESEARCH_COLLABORATION', 'RESEARCH', 'Research collaboration', 1), ('JOINT_RESEARCH', 'RESEARCH', 'Joint research', 2),
    ('RESEARCH_PROJECT', 'RESEARCH', 'Research project', 3), ('RESEARCH_FUNDING', 'RESEARCH', 'Research funding', 4),
    ('RESEARCH_FACILITIES', 'RESEARCH', 'Research facilities', 5), ('JOINT_PUBLICATION', 'RESEARCH', 'Joint publication', 6),
    ('RESEARCH_DATA', 'RESEARCH', 'Research data collaboration', 7),
    ('JOINT_PROGRAMME', 'ACADEMIC', 'Joint academic programme', 1), ('DUAL_DEGREE', 'ACADEMIC', 'Dual degree', 2),
    ('CURRICULUM_DEVELOPMENT', 'ACADEMIC', 'Curriculum development', 3), ('TEACHING_COLLABORATION', 'ACADEMIC', 'Teaching collaboration', 4),
    ('ACADEMIC_EXCHANGE', 'ACADEMIC', 'Academic exchange', 5), ('VISITING_SCHOLARS', 'ACADEMIC', 'Visiting scholars', 6),
    ('STUDENT_EXCHANGE', 'STUDENT_MOBILITY', 'Student exchange', 1), ('INTERNSHIP', 'STUDENT_MOBILITY', 'Internship', 2),
    ('PLACEMENT', 'STUDENT_MOBILITY', 'Placement', 3), ('EMPLOYABILITY', 'STUDENT_MOBILITY', 'Employability', 4),
    ('INTERNATIONAL_MOBILITY', 'STUDENT_MOBILITY', 'International mobility', 5),
    ('STAFF_EXCHANGE', 'STAFF_MOBILITY', 'Staff exchange', 1), ('CAPACITY_BUILDING', 'STAFF_MOBILITY', 'Capacity building', 2),
    ('STAFF_TRAINING', 'STAFF_MOBILITY', 'Training', 3), ('VISITING_STAFF', 'STAFF_MOBILITY', 'Visiting staff', 4),
    ('INDUSTRY_PARTNERSHIP', 'INDUSTRY', 'Industry partnership', 1), ('CONSULTANCY', 'INDUSTRY', 'Consultancy', 2),
    ('TECHNOLOGY_TRANSFER', 'INDUSTRY', 'Technology transfer', 3), ('INNOVATION', 'INDUSTRY', 'Innovation', 4),
    ('COMMERCIALISATION', 'INDUSTRY', 'Commercialisation', 5), ('ENTREPRENEURSHIP', 'INDUSTRY', 'Entrepreneurship', 6),
    ('GRANTS', 'FUNDING', 'Grants', 1), ('DONOR_FUNDED_PROJECT', 'FUNDING', 'Donor-funded project', 2),
    ('SPONSORED_PROJECT', 'FUNDING', 'Sponsored project', 3), ('JOINT_FUNDING_APPLICATION', 'FUNDING', 'Joint funding application', 4),
    ('COMMUNITY_ENGAGEMENT', 'COMMUNITY', 'Community engagement', 1), ('GOVERNMENT_PARTNERSHIP', 'COMMUNITY', 'Government partnership', 2),
    ('SOCIAL_DEVELOPMENT', 'COMMUNITY', 'Social development', 3), ('PUBLIC_SECTOR', 'COMMUNITY', 'Public-sector collaboration', 4),
    ('LABORATORY_COOPERATION', 'RESOURCES', 'Laboratory cooperation', 1), ('EQUIPMENT_SHARING', 'RESOURCES', 'Equipment sharing', 2),
    ('LIBRARY_COOPERATION', 'RESOURCES', 'Library cooperation', 3), ('DATA_SHARING', 'RESOURCES', 'Data sharing', 4),
    ('CONFERENCE', 'EVENTS', 'Conference', 1), ('WORKSHOP', 'EVENTS', 'Workshop', 2), ('SEMINAR', 'EVENTS', 'Seminar', 3),
    ('ACADEMIC_EVENT', 'EVENTS', 'Academic event', 4),
    ('OTHER', 'OTHER', 'Other', 1);

CREATE TABLE partnership.desk (
    code        text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
    label       text NOT NULL CHECK (btrim(label) <> ''),
    lead_person uuid NULL,
    sort        integer NOT NULL DEFAULT 100,
    active      boolean NOT NULL DEFAULT true
);
SELECT audit.attach('partnership.desk');
COMMENT ON TABLE partnership.desk IS 'V658: a desk of the Linkages & Partnerships office a proposal is routed to; its lead (a person holding the linkages office) takes a proposal routed to it as owner';
INSERT INTO partnership.desk (code, label, sort) VALUES
    ('GENERAL', 'Linkages & Partnerships (general)', 1), ('RESEARCH', 'Research & Innovation', 2),
    ('INTERNATIONAL', 'International Relations', 3), ('INDUSTRY', 'Industry Liaison', 4),
    ('ADVANCEMENT', 'Advancement & Development', 5), ('COMMUNITY', 'Community & Government Engagement', 6);
CREATE TABLE partnership.desk_officer (
    desk_code text NOT NULL REFERENCES partnership.desk (code),
    person_id uuid NOT NULL,
    active    boolean NOT NULL DEFAULT true,
    added_by  uuid NULL,
    added_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (desk_code, person_id)
);
SELECT audit.attach('partnership.desk_officer');
COMMENT ON TABLE partnership.desk_officer IS 'V658: the officers of a Linkages desk — told when a proposal is routed to it, and offered as owners';

CREATE TABLE partnership.routing_rule (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    priority       integer NOT NULL UNIQUE CHECK (priority BETWEEN 1 AND 9999),
    category_group text NULL REFERENCES partnership.category_group (code),
    category       text NULL REFERENCES partnership.category (code),
    international  boolean NULL,
    org_type       text NULL,
    funding_status text NULL,
    desk_code      text NOT NULL REFERENCES partnership.desk (code),
    active         boolean NOT NULL DEFAULT true,
    note           text NULL
);
SELECT audit.attach('partnership.routing_rule');
COMMENT ON TABLE partnership.routing_rule IS 'V658: a routing rule — the first active one by priority whose stated conditions (category, group, international or local, organisation type, funding status) all match names the desk; none matching, the general desk';
INSERT INTO partnership.routing_rule (priority, category_group, category, international, org_type, funding_status, desk_code, note) VALUES
    (10, NULL, 'DONOR_FUNDED_PROJECT', NULL, NULL, NULL, 'ADVANCEMENT', 'A donor-funded project: Advancement & Development'),
    (20, NULL, NULL, NULL, 'FOUNDATION_DONOR', NULL, 'ADVANCEMENT', 'A foundation or donor: Advancement & Development'),
    (30, 'INDUSTRY', NULL, NULL, NULL, NULL, 'INDUSTRY', 'Industry: Industry Liaison'),
    (40, 'STUDENT_MOBILITY', NULL, true, NULL, NULL, 'INTERNATIONAL', 'Student mobility with a partner abroad: International Relations'),
    (45, 'STAFF_MOBILITY', NULL, true, NULL, NULL, 'INTERNATIONAL', 'Staff mobility with a partner abroad: International Relations'),
    (50, 'STUDENT_MOBILITY', NULL, false, NULL, NULL, 'INDUSTRY', 'Internships and placements at home: Industry Liaison'),
    (60, 'RESEARCH', NULL, NULL, NULL, NULL, 'RESEARCH', 'Research: Research & Innovation'),
    (70, 'FUNDING', NULL, NULL, NULL, NULL, 'RESEARCH', 'Grants and joint funding: Research & Innovation'),
    (80, 'COMMUNITY', NULL, NULL, NULL, NULL, 'COMMUNITY', 'Community and government: Community & Government Engagement'),
    (85, NULL, NULL, NULL, 'GOVERNMENT', NULL, 'COMMUNITY', 'A government agency: Community & Government Engagement'),
    (90, NULL, NULL, true, NULL, NULL, 'INTERNATIONAL', 'Any other proposal with partners abroad: International Relations');

-- ── 4 · who may ─────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE partnership.grant (
    office_code text NOT NULL REFERENCES ref.office (code),
    permission  text NOT NULL CHECK (permission IN ('VIEW_PARTNERSHIP', 'VIEW_ALL_PARTNERSHIPS', 'VIEW_CONFIDENTIAL', 'CREATE_PARTNERSHIP',
        'EDIT_PARTNERSHIP', 'SCREEN_PARTNERSHIP', 'ROUTE_PARTNERSHIP', 'ASSIGN_PARTNERSHIP', 'REVIEW_PARTNERSHIP', 'REQUEST_INFORMATION',
        'VIEW_ATTACHMENTS', 'UPLOAD_DOCUMENTS', 'DUE_DILIGENCE', 'APPROVE_PARTNERSHIP', 'DECLINE_PARTNERSHIP', 'MANAGE_AGREEMENT',
        'CLOSE_PARTNERSHIP', 'EXPORT_PARTNERSHIP', 'VIEW_REPORTS', 'MANAGE_PARTNERSHIP_SETTINGS')),
    PRIMARY KEY (office_code, permission)
);
SELECT audit.attach('partnership.grant');
COMMENT ON TABLE partnership.grant IS
  'V658: what each office may do with collaboration and partnership proposals. The Linkages office runs the workflow (all but approval); the Vice-Chancellor approves and declines (the DVC may act for the VC); the Legal Officer reviews and manages agreements; a reviewing office (a Dean, a Head, the Registrar, the Bursar, the PG School, ICT, Student Affairs, the Academic Office) reviews what it is asked to; Internal Audit reads. Checked by the API and by the functions.';
INSERT INTO partnership.grant (office_code, permission)
SELECT o, p FROM unnest(ARRAY['linkages', 'super']) o,
       unnest(ARRAY['VIEW_PARTNERSHIP', 'VIEW_ALL_PARTNERSHIPS', 'VIEW_CONFIDENTIAL', 'CREATE_PARTNERSHIP', 'EDIT_PARTNERSHIP', 'SCREEN_PARTNERSHIP',
                    'ROUTE_PARTNERSHIP', 'ASSIGN_PARTNERSHIP', 'REVIEW_PARTNERSHIP', 'REQUEST_INFORMATION', 'VIEW_ATTACHMENTS', 'UPLOAD_DOCUMENTS',
                    'DUE_DILIGENCE', 'DECLINE_PARTNERSHIP', 'MANAGE_AGREEMENT', 'CLOSE_PARTNERSHIP', 'EXPORT_PARTNERSHIP', 'VIEW_REPORTS',
                    'MANAGE_PARTNERSHIP_SETTINGS']) p
UNION ALL SELECT 'super', 'APPROVE_PARTNERSHIP'
UNION ALL
SELECT o, p FROM unnest(ARRAY['vc', 'dvc']) o,
       unnest(ARRAY['VIEW_PARTNERSHIP', 'VIEW_ALL_PARTNERSHIPS', 'VIEW_CONFIDENTIAL', 'REVIEW_PARTNERSHIP', 'VIEW_ATTACHMENTS', 'APPROVE_PARTNERSHIP',
                    'DECLINE_PARTNERSHIP', 'EXPORT_PARTNERSHIP', 'VIEW_REPORTS']) p
UNION ALL
SELECT 'legal', p FROM unnest(ARRAY['VIEW_PARTNERSHIP', 'REVIEW_PARTNERSHIP', 'VIEW_ATTACHMENTS', 'UPLOAD_DOCUMENTS', 'DUE_DILIGENCE', 'MANAGE_AGREEMENT']) p
UNION ALL
SELECT o, p FROM unnest(ARRAY['dean', 'hod', 'registrar', 'bursar', 'pgschool', 'ict', 'dsa', 'academic', 'dregistrar']) o,
       unnest(ARRAY['VIEW_PARTNERSHIP', 'REVIEW_PARTNERSHIP', 'VIEW_ATTACHMENTS', 'UPLOAD_DOCUMENTS']) p
UNION ALL
SELECT o, p FROM unnest(ARRAY['audit', 'deputyaudit']) o,
       unnest(ARRAY['VIEW_PARTNERSHIP', 'VIEW_ALL_PARTNERSHIPS', 'VIEW_ATTACHMENTS', 'EXPORT_PARTNERSHIP', 'VIEW_REPORTS']) p
ON CONFLICT DO NOTHING;

-- ── 5 · the central record ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE partnership.proposal (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference              text NULL UNIQUE CHECK (reference IS NULL OR reference ~ '^PTN/[0-9]{4}/[0-9]{6}$'),
    status                 text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'RECEIVED', 'INITIAL_SCREENING', 'AWAITING_INFORMATION', 'ROUTED',
        'ASSIGNED', 'UNDER_REVIEW', 'DUE_DILIGENCE', 'MEETING_PROPOSED', 'UNDER_DEVELOPMENT', 'PENDING_APPROVAL', 'APPROVED_FOR_DEVELOPMENT',
        'AGREEMENT_REVIEW', 'AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE', 'DECLINED', 'CLOSED', 'CANCELLED')),
    source                 text NOT NULL DEFAULT 'PUBLIC' CHECK (source IN ('PUBLIC', 'INTERNAL')),
    token_hash             bytea NULL UNIQUE,
    -- step 1: the applicant
    first_name             text NULL, last_name text NULL, job_title text NULL,
    org_name               text NULL, org_type text NULL CHECK (org_type IS NULL OR org_type IN ('UNIVERSITY', 'RESEARCH_INSTITUTE', 'COMPANY', 'GOVERNMENT',
                                                                              'NGO', 'FOUNDATION_DONOR', 'INTERNATIONAL_ORGANISATION', 'OTHER')),
    org_type_other         text NULL,
    email                  text NULL, phone text NULL, country text NULL, city text NULL, address text NULL, website text NULL, profile_url text NULL,
    language               text NULL, contact_method text NULL CHECK (contact_method IS NULL OR contact_method IN ('EMAIL', 'PHONE', 'VIDEO_CALL', 'IN_PERSON')),
    time_zone              text NULL,
    -- step 2: the existing connection
    proposal_kind          text NULL CHECK (proposal_kind IS NULL OR proposal_kind IN ('NEW', 'EXISTING_DISCUSSION', 'FOLLOW_UP')),
    previous_reference     text NULL,
    has_contact            boolean NULL, contact_name text NULL, contact_unit text NULL, contact_email text NULL,
    collaborated_before    text NULL CHECK (collaborated_before IS NULL OR collaborated_before IN ('YES', 'NO', 'NOT_SURE')),
    previous_collaboration text NULL,
    -- step 3: the proposal
    category               text NULL REFERENCES partnership.category (code),
    secondary_category     text NULL REFERENCES partnership.category (code),
    title                  text NULL, summary text NULL, description text NULL, objectives text NULL, activities text NULL,
    expected_results       text NULL, why_university text NULL,
    faculty_code           text NULL REFERENCES ref.faculty (code),
    dept_code              text NULL REFERENCES ref.department (code),
    unit_text              text NULL, expertise text NULL, staff_contact text NULL,
    start_date             date NULL, duration text NULL,
    collaboration_format   text NULL CHECK (collaboration_format IS NULL OR collaboration_format IN ('ONE_OFF', 'PILOT', 'MULTI_YEAR', 'INSTITUTIONAL_AGREEMENT',
                                                                                                 'JOINT_FUNDING_APPLICATION', 'OTHER')),
    benefits_university    text NULL, benefits_partner text NULL,
    -- step 4: funding and resources
    funding_status         text NULL CHECK (funding_status IS NULL OR funding_status IN ('FULLY_FUNDED', 'PARTLY_FUNDED', 'APPLICATION_PLANNED', 'NONE_IDENTIFIED',
                                                                                     'PREFER_TO_DISCUSS')),
    budget                 numeric(18, 2) NULL CHECK (budget IS NULL OR budget >= 0),
    currency               text NULL CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
    funder                 text NULL,
    joint_grant            text NULL CHECK (joint_grant IS NULL OR joint_grant IN ('YES', 'NO', 'POSSIBLY')),
    funding_deadline       date NULL,
    resources_requested    text[] NOT NULL DEFAULT '{}',
    resources_other        text NULL,
    partner_contribution   text NULL,
    -- step 5: international, legal and compliance (flags for review, never legal conclusions)
    international          boolean NULL,
    countries              text[] NOT NULL DEFAULT '{}',
    international_aspects  text[] NOT NULL DEFAULT '{}',
    agreement_types        text[] NOT NULL DEFAULT '{}',
    personal_data          text NULL CHECK (personal_data IS NULL OR personal_data IN ('YES', 'NO', 'NOT_SURE')),
    sensitive_data         text NULL CHECK (sensitive_data IS NULL OR sensitive_data IN ('YES', 'NO', 'NOT_SURE')),
    sensitive_kinds        text[] NOT NULL DEFAULT '{}',
    ethics                 text NULL CHECK (ethics IS NULL OR ethics IN ('YES', 'NO', 'NOT_SURE')),
    high_risk              jsonb NOT NULL DEFAULT '{}'::jsonb,
    coi                    text NULL CHECK (coi IS NULL OR coi IN ('YES', 'NO', 'CONFIDENTIAL')),
    coi_detail             text NULL,
    own_due_diligence      text NULL CHECK (own_due_diligence IS NULL OR own_due_diligence IN ('YES', 'NO', 'IN_PROGRESS')),
    -- step 7: declarations (never pre-ticked; the five required, marketing apart)
    declared_accurate      boolean NOT NULL DEFAULT false,
    declared_authorised    boolean NOT NULL DEFAULT false,
    declared_no_commitment boolean NOT NULL DEFAULT false,
    declared_privacy       boolean NOT NULL DEFAULT false,
    consent_contact        boolean NOT NULL DEFAULT false,
    consent_marketing      boolean NOT NULL DEFAULT false,
    -- what the University reads from the answers, and its workflow
    flags                  text[] NOT NULL DEFAULT '{}',
    compliance_review      boolean NOT NULL DEFAULT false,
    risk_level             text NULL CHECK (risk_level IS NULL OR risk_level IN ('LOW', 'MEDIUM', 'HIGH')),
    desk_code              text NULL REFERENCES partnership.desk (code),
    routing_rule           uuid NULL REFERENCES partnership.routing_rule (id) ON DELETE SET NULL,
    owner_person           uuid NULL,
    owner_assigned_at      timestamptz NULL,
    due_on                 date NULL,
    next_action            text NULL,
    received_at            timestamptz NULL,
    acknowledged_at        timestamptz NULL,
    decided_at             timestamptz NULL,
    decided_by             uuid NULL,
    closed_at              timestamptz NULL,
    close_reason           text NULL,
    created_by             uuid NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ptn_received CHECK (status = 'DRAFT' OR (reference IS NOT NULL AND received_at IS NOT NULL AND title IS NOT NULL AND org_name IS NOT NULL
                                                          AND email IS NOT NULL AND category IS NOT NULL AND desk_code IS NOT NULL)),
    -- every proposal beyond routing has an owner (the active ones can never stand ownerless)
    CONSTRAINT ck_ptn_owner CHECK (status IN ('DRAFT', 'RECEIVED', 'INITIAL_SCREENING', 'ROUTED', 'AWAITING_INFORMATION', 'DECLINED', 'CLOSED', 'CANCELLED')
                                   OR owner_person IS NOT NULL),
    CONSTRAINT ck_ptn_declarations CHECK (status = 'DRAFT' OR source = 'INTERNAL'
                                          OR (declared_accurate AND declared_authorised AND declared_no_commitment AND declared_privacy AND consent_contact))
);
CREATE INDEX ix_ptn_status ON partnership.proposal (status, received_at DESC) WHERE status <> 'DRAFT';
CREATE INDEX ix_ptn_owner ON partnership.proposal (owner_person) WHERE owner_person IS NOT NULL;
CREATE INDEX ix_ptn_faculty ON partnership.proposal (faculty_code, dept_code);
CREATE INDEX ix_ptn_email_title ON partnership.proposal (lower(email), lower(title)) WHERE status <> 'DRAFT';
CREATE INDEX ix_ptn_draft ON partnership.proposal (created_at) WHERE status = 'DRAFT';
SELECT audit.attach('partnership.proposal');
COMMENT ON TABLE partnership.proposal IS
  'V658: the one central collaboration and partnership record — from the public enquiry (or one the Linkages office records) to the active partnership and its closure; classified by category, never kept apart by kind. The public reference is PTN/YYYY/NNNNNN; the applicant follows it by the secret link whose hash is token_hash. Submitting is never acceptance.';

-- ── 6 · its satellites ──────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE partnership.info_request (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id   uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    question      text NOT NULL CHECK (length(btrim(question)) >= 10),
    documents     text NULL,
    deadline      date NOT NULL,
    reason        text NULL,
    resume_status text NOT NULL,
    requested_by  uuid NOT NULL,
    requested_at  timestamptz NOT NULL DEFAULT now(),
    answer        text NULL,
    answered_at   timestamptz NULL,
    withdrawn_at  timestamptz NULL
);
CREATE INDEX ix_ptn_info ON partnership.info_request (proposal_id);
CREATE UNIQUE INDEX ux_ptn_info_open ON partnership.info_request (proposal_id) WHERE answered_at IS NULL AND withdrawn_at IS NULL;
SELECT audit.attach('partnership.info_request');
COMMENT ON TABLE partnership.info_request IS 'V658: a request to the applicant for more information or documents (one open at a time); the reason stays internal';

CREATE TABLE partnership.attachment (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id     uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    agreement_id    uuid NULL,
    info_request_id uuid NULL REFERENCES partnership.info_request (id) ON DELETE SET NULL,
    kind            text NOT NULL CHECK (kind IN ('CONCEPT_NOTE', 'PROPOSAL', 'ORGANISATION_PROFILE', 'DRAFT_MOU', 'DRAFT_AGREEMENT', 'CV', 'FUNDING_CALL',
                                                  'BUDGET', 'SUPPORT_LETTER', 'REGISTRATION_EVIDENCE', 'REQUESTED_DOCUMENT', 'AGREEMENT', 'INTERNAL', 'OTHER')),
    filename        text NOT NULL CHECK (btrim(filename) <> '' AND length(filename) <= 200),
    content_type    text NOT NULL,
    size_bytes      bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 20971520),
    sha256          bytea NOT NULL,
    content         bytea NULL,
    object_id       uuid NULL REFERENCES platform.file_object (id),
    from_applicant  boolean NOT NULL DEFAULT false,
    added_by        uuid NULL,
    added_office    text NULL,
    added_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ptn_attachment_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_ptn_attachment ON partnership.attachment (proposal_id);
SELECT audit.exempt('partnership.attachment', 'V658: file bytes; who added which file and when is the row itself, recorded on the proposal''s timeline (partnership.event), and every look at one is recorded there too');
COMMENT ON TABLE partnership.attachment IS 'V658: a file of a proposal — the applicant''s (concept note, proposal, profile, draft agreement …, a document asked for) or the University''s (an agreement, an internal document) — in the file store where there is one, else here; PDF, DOCX, XLSX or PPTX, checked by its content';

CREATE TABLE partnership.event (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id       uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    at                timestamptz NOT NULL DEFAULT clock_timestamp(),
    actor             uuid NULL,
    actor_office      text NULL,
    action            text NOT NULL,
    from_status       text NULL,
    to_status         text NULL,
    detail            text NULL,
    applicant_visible boolean NOT NULL DEFAULT false
);
CREATE INDEX ix_ptn_event ON partnership.event (proposal_id, at);
SELECT audit.attach('partnership.event');
COMMENT ON TABLE partnership.event IS 'V658: the proposal''s timeline — every submission, status change, routing, assignment, review, request, document added or opened, decision, agreement change and export — who, as which office, from and to, why; the applicant sees only the rows marked for them';

CREATE TABLE partnership.message (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id   uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    kind          text NOT NULL CHECK (kind IN ('INTERNAL_NOTE', 'APPLICANT_MESSAGE', 'APPLICANT_REPLY')),
    body          text NOT NULL CHECK (length(btrim(body)) >= 2 AND length(body) <= 8000),
    confidential  boolean NOT NULL DEFAULT false,
    author_person uuid NULL,
    author_office text NULL,
    at            timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_ptn_message ON partnership.message (proposal_id, at);
SELECT audit.attach('partnership.message');
COMMENT ON TABLE partnership.message IS 'V658: an internal note (never sent to the applicant; a confidential one read only by those allowed) or a message to or from the applicant (sent by e-mail and shown on the status page)';

CREATE TABLE partnership.reviewer (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id    uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    office_code    text NOT NULL REFERENCES ref.office (code),
    scope_code     text NULL,
    person_id      uuid NULL,
    role_label     text NULL,
    due_on         date NULL,
    see_confidential boolean NOT NULL DEFAULT false,
    assigned_by    uuid NOT NULL,
    assigned_at    timestamptz NOT NULL DEFAULT now(),
    recommendation text NULL CHECK (recommendation IS NULL OR recommendation IN ('SUPPORT', 'SUPPORT_WITH_CONDITIONS', 'DO_NOT_SUPPORT', 'NEED_MORE_INFORMATION')),
    comment        text NULL,
    completed_by   uuid NULL,
    completed_at   timestamptz NULL,
    withdrawn_at   timestamptz NULL
);
CREATE INDEX ix_ptn_reviewer ON partnership.reviewer (proposal_id);
CREATE INDEX ix_ptn_reviewer_office ON partnership.reviewer (office_code, scope_code) WHERE withdrawn_at IS NULL;
SELECT audit.attach('partnership.reviewer');
COMMENT ON TABLE partnership.reviewer IS 'V658: an office asked to review a proposal — a Dean for a named faculty, a Head for a named department, another office for the University — or a named person; its recommendation and comment';

CREATE TABLE partnership.dd_item (
    code   text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
    label  text NOT NULL,
    sort   integer NOT NULL DEFAULT 100,
    active boolean NOT NULL DEFAULT true
);
SELECT audit.attach('partnership.dd_item');
INSERT INTO partnership.dd_item (code, label, sort) VALUES
    ('IDENTITY', 'Organisation identity', 1), ('REGISTRATION', 'Registration / accreditation', 2), ('REPUTATION', 'Reputation', 3),
    ('FUNDING', 'Funding', 4), ('LEGAL', 'Legal', 5), ('DATA_PROTECTION', 'Data protection', 6), ('ETHICS', 'Research ethics', 7),
    ('CONFLICT_OF_INTEREST', 'Conflict of interest', 8), ('SECURITY', 'Security', 9), ('INTERNATIONAL', 'International compliance', 10),
    ('FINANCIAL_RISK', 'Financial risk', 11), ('IP', 'Intellectual property', 12), ('CONTRACTUAL', 'Contractual requirements', 13);
CREATE TABLE partnership.due_diligence (
    proposal_id uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    item_code   text NOT NULL REFERENCES partnership.dd_item (code),
    status      text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SATISFACTORY', 'CONCERN', 'NOT_APPLICABLE')),
    note        text NULL,
    checked_by  uuid NULL,
    checked_office text NULL,
    checked_at  timestamptz NULL,
    PRIMARY KEY (proposal_id, item_code)
);
SELECT audit.attach('partnership.due_diligence');
COMMENT ON TABLE partnership.due_diligence IS 'V658: the due-diligence checklist of a proposal — each check pending, satisfactory, of concern or not applicable, with who and why';

CREATE TABLE partnership.agreement (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id    uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    reference      text NOT NULL UNIQUE CHECK (reference ~ '^PTN-AGR/[0-9]{4}/[0-9]{6}$'),
    agreement_type text NOT NULL CHECK (agreement_type IN ('MOU', 'MOA', 'RESEARCH_AGREEMENT', 'STUDENT_EXCHANGE', 'NDA', 'DATA_SHARING', 'IP_LICENSING', 'OTHER')),
    type_other     text NULL,
    title          text NOT NULL CHECK (btrim(title) <> ''),
    parties        text NOT NULL CHECK (btrim(parties) <> ''),
    status         text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'LEGAL_REVIEW', 'APPROVAL', 'SIGNING', 'EXECUTED', 'EXPIRED', 'TERMINATED', 'WITHDRAWN')),
    effective_on   date NULL,
    expires_on     date NULL,
    renewal_on     date NULL,
    signed_on      date NULL,
    legal_note     text NULL, legal_by uuid NULL, legal_at timestamptz NULL,
    approved_by    uuid NULL, approved_office text NULL, approved_at timestamptz NULL,
    executed_by    uuid NULL, executed_at timestamptz NULL,
    ended_note     text NULL,
    created_by     uuid NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ptn_agreement_dates CHECK (expires_on IS NULL OR effective_on IS NULL OR expires_on > effective_on),
    CONSTRAINT ck_ptn_agreement_executed CHECK (status NOT IN ('EXECUTED', 'EXPIRED') OR (effective_on IS NOT NULL AND signed_on IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE INDEX ix_ptn_agreement ON partnership.agreement (proposal_id);
CREATE INDEX ix_ptn_agreement_expiry ON partnership.agreement (expires_on) WHERE status = 'EXECUTED';
SELECT audit.attach('partnership.agreement');
ALTER TABLE partnership.attachment ADD CONSTRAINT fk_ptn_attachment_agreement FOREIGN KEY (agreement_id) REFERENCES partnership.agreement (id) ON DELETE SET NULL;
COMMENT ON TABLE partnership.agreement IS 'V658: an agreement of a partnership (MOU, MOA, research, student exchange, NDA, data sharing, IP/licensing, other) — drafted, reviewed by the Legal Officer, approved by the Vice-Chancellor, signed and executed, its effective, expiry and renewal dates watched; never renewed automatically';

CREATE TABLE partnership.activity (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    kind        text NOT NULL CHECK (kind IN ('ACTIVITY', 'DELIVERABLE', 'REPORT')),
    title       text NOT NULL CHECK (btrim(title) <> ''),
    lead        text NULL,
    due_on      date NULL,
    status      text NOT NULL DEFAULT 'PLANNED' CHECK (status IN ('PLANNED', 'IN_PROGRESS', 'DONE', 'CANCELLED')),
    done_on     date NULL,
    note        text NULL,
    created_by  uuid NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_ptn_activity ON partnership.activity (proposal_id);
SELECT audit.attach('partnership.activity');

CREATE TABLE partnership.outcome_kind (
    code   text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
    label  text NOT NULL,
    sort   integer NOT NULL DEFAULT 100,
    active boolean NOT NULL DEFAULT true
);
SELECT audit.attach('partnership.outcome_kind');
INSERT INTO partnership.outcome_kind (code, label, sort) VALUES
    ('RESEARCH_PROJECT', 'Research project', 1), ('GRANT', 'Grant', 2), ('PUBLICATION', 'Publication', 3), ('STUDENT_EXCHANGE', 'Student exchange', 4),
    ('STAFF_EXCHANGE', 'Staff exchange', 5), ('INTERNSHIP', 'Internship', 6), ('TRAINING', 'Training', 7), ('CONSULTANCY', 'Consultancy', 8),
    ('TECHNOLOGY_TRANSFER', 'Technology transfer', 9), ('JOINT_PROGRAMME', 'Joint programme', 10), ('COMMUNITY_PROJECT', 'Community project', 11),
    ('EQUIPMENT_SUPPORT', 'Equipment support', 12), ('OTHER', 'Other', 13);
CREATE TABLE partnership.outcome (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id uuid NOT NULL REFERENCES partnership.proposal (id) ON DELETE CASCADE,
    kind        text NOT NULL REFERENCES partnership.outcome_kind (code),
    description text NOT NULL CHECK (btrim(description) <> ''),
    occurred_on date NULL,
    quantity    integer NULL CHECK (quantity IS NULL OR quantity >= 0),
    amount      numeric(18, 2) NULL CHECK (amount IS NULL OR amount >= 0),
    currency    text NULL CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
    recorded_by uuid NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_ptn_outcome ON partnership.outcome (proposal_id);
SELECT audit.attach('partnership.outcome');

-- ── 7 · who is acting, and what they may ────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION partnership.actor() RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('moaum.actor_id', true), '')::uuid
$$;
CREATE FUNCTION partnership.actor_office() RETURNS text LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('moaum.actor_office', true), '')
$$;
CREATE FUNCTION partnership.permissions(p_office text) RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(g.permission ORDER BY g.permission), '{}') FROM partnership.grant g WHERE g.office_code = p_office
$$;
CREATE FUNCTION partnership.may(p_permission text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM partnership.grant g WHERE g.office_code = partnership.actor_office() AND g.permission = p_permission)
$$;
CREATE FUNCTION partnership.require(p_permission text) RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF NOT partnership.may(p_permission) THEN
        RAISE EXCEPTION 'PTN_NOT_PERMITTED: % may not %', coalesce(partnership.actor_office(), 'this office'),
            lower(replace(p_permission, '_', ' ')) USING ERRCODE = '42501';
    END IF;
END $$;

-- the faculty or department a person holds an office over (a Dean's faculty, a Head's department)
CREATE FUNCTION partnership.office_scopes(p_person uuid, p_office text) RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(DISTINCT iam.scope_code(a.scope_kind, a.scope_id)) FILTER (WHERE a.scope_kind IN ('faculty', 'department')), '{}')
      FROM iam.office_assignment a
     WHERE a.person_id = p_person AND a.office_code = p_office AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
$$;

-- the proposals an acting person sees as the office they act in: all with VIEW_ALL_PARTNERSHIPS; else those they own, those their
-- office is asked to review (a Dean or a Head only for their own faculty or department), those they are named to review
CREATE FUNCTION partnership.visible(p_person uuid, p_office text) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
    WITH g AS (SELECT EXISTS (SELECT 1 FROM partnership.grant WHERE office_code = p_office AND permission = 'VIEW_ALL_PARTNERSHIPS') AS all_,
                      EXISTS (SELECT 1 FROM partnership.grant WHERE office_code = p_office AND permission = 'VIEW_PARTNERSHIP') AS some_,
                      partnership.office_scopes(p_person, p_office) AS scopes)
    SELECT p.id FROM partnership.proposal p CROSS JOIN g
     WHERE g.some_ AND p.status <> 'DRAFT'
       AND (g.all_
            OR p.owner_person = p_person
            OR EXISTS (SELECT 1 FROM partnership.reviewer r
                        WHERE r.proposal_id = p.id AND r.withdrawn_at IS NULL
                          AND (r.person_id = p_person
                               OR (r.person_id IS NULL AND r.office_code = p_office
                                   AND (r.scope_code IS NULL OR r.scope_code = ANY (g.scopes))))))
$$;
CREATE FUNCTION partnership.may_see(p_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM partnership.visible(partnership.actor(), partnership.actor_office()) v WHERE v = p_id)
$$;
CREATE FUNCTION partnership.require_see(p_id uuid) RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM partnership.proposal WHERE id = p_id AND status <> 'DRAFT') THEN
        RAISE EXCEPTION 'PTN_NOT_FOUND: no such proposal' USING ERRCODE = 'P0002';
    END IF;
    IF NOT partnership.may_see(p_id) THEN
        RAISE EXCEPTION 'PTN_NOT_PERMITTED: this proposal is not one your office is asked to see' USING ERRCODE = '42501';
    END IF;
END $$;
-- a confidential disclosure (a conflict of interest to discuss in confidence, a confidential note): VIEW_CONFIDENTIAL, or a
-- reviewer the owner has let see it
CREATE FUNCTION partnership.may_confidential(p_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT partnership.may('VIEW_CONFIDENTIAL')
        OR EXISTS (SELECT 1 FROM partnership.reviewer r WHERE r.proposal_id = p_id AND r.withdrawn_at IS NULL AND r.see_confidential
                      AND (r.person_id = partnership.actor()
                           OR (r.person_id IS NULL AND r.office_code = partnership.actor_office()
                               AND (r.scope_code IS NULL OR r.scope_code = ANY (partnership.office_scopes(partnership.actor(), partnership.actor_office()))))))
$$;

-- ── 8 · dates, references, words ────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION partnership.today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'Africa/Lagos')::date $$;
-- n working days after a date (Saturdays and Sundays not counted)
CREATE FUNCTION partnership.add_working_days(p_from date, p_days integer) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d date := p_from; n integer := 0;
BEGIN
    WHILE n < greatest(p_days, 0) LOOP
        d := d + 1;
        IF extract(isodow FROM d) < 6 THEN n := n + 1; END IF;
    END LOOP;
    RETURN d;
END $$;
CREATE FUNCTION partnership.next_reference() RETURNS text LANGUAGE plpgsql AS $$
DECLARE y text := extract(year FROM now() AT TIME ZONE 'Africa/Lagos')::int::text;
BEGIN
    RETURN 'PTN/' || y || '/' || lpad(platform.next_number('PARTNERSHIP', 'partnership', y)::text, 6, '0');
END $$;
CREATE FUNCTION partnership.next_agreement_reference() RETURNS text LANGUAGE plpgsql AS $$
DECLARE y text := extract(year FROM now() AT TIME ZONE 'Africa/Lagos')::int::text;
BEGIN
    RETURN 'PTN-AGR/' || y || '/' || lpad(platform.next_number('PARTNERSHIP_AGREEMENT', 'partnership', y)::text, 6, '0');
END $$;
-- what the applicant reads of a status (never the internal workings)
CREATE FUNCTION partnership.public_status(p_status text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_status
        WHEN 'RECEIVED' THEN 'Received'
        WHEN 'INITIAL_SCREENING' THEN 'Being screened' WHEN 'ROUTED' THEN 'Being screened' WHEN 'ASSIGNED' THEN 'Being screened'
        WHEN 'AWAITING_INFORMATION' THEN 'Information requested from you'
        WHEN 'UNDER_REVIEW' THEN 'Under review' WHEN 'DUE_DILIGENCE' THEN 'Under review' WHEN 'MEETING_PROPOSED' THEN 'Meeting proposed'
        WHEN 'UNDER_DEVELOPMENT' THEN 'Under development' WHEN 'PENDING_APPROVAL' THEN 'Under review'
        WHEN 'APPROVED_FOR_DEVELOPMENT' THEN 'Approved for development'
        WHEN 'AGREEMENT_REVIEW' THEN 'Agreement being prepared' WHEN 'AGREEMENT_EXECUTED' THEN 'Agreement executed'
        WHEN 'IMPLEMENTATION' THEN 'Being implemented' WHEN 'ACTIVE' THEN 'Active partnership'
        WHEN 'DECLINED' THEN 'Not taken forward' WHEN 'CLOSED' THEN 'Closed' WHEN 'CANCELLED' THEN 'Withdrawn'
        ELSE 'Draft' END
$$;
CREATE FUNCTION partnership.terminal(p_status text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_status IN ('DECLINED', 'CLOSED', 'CANCELLED')
$$;

-- ── 9 · what the answers flag for review (never a legal conclusion), and how high the risk reads ─────────────────────────
CREATE FUNCTION partnership.flags_of(p partnership.proposal) RETURNS TABLE (flags text[], compliance boolean, risk text)
LANGUAGE plpgsql STABLE AS $$
DECLARE f text[] := '{}'; hr jsonb := coalesce(p.high_risk, '{}'::jsonb); k text; high boolean := false;
BEGIN
    IF coalesce(p.international, false) THEN f := array_append(f, 'INTERNATIONAL'::text); END IF;
    IF p.personal_data IN ('YES', 'NOT_SURE') THEN f := array_append(f, 'PERSONAL_DATA'::text); END IF;
    IF p.sensitive_data IN ('YES', 'NOT_SURE') THEN f := array_append(f, 'SENSITIVE_DATA'::text); high := high OR p.sensitive_data = 'YES'; END IF;
    IF p.ethics IN ('YES', 'NOT_SURE') THEN f := array_append(f, 'ETHICS'::text); END IF;
    FOREACH k IN ARRAY ARRAY['HUMAN_PARTICIPANTS', 'ANIMALS', 'CLINICAL', 'HAZARDOUS', 'CONTROLLED_TECHNOLOGY', 'EXPORT_CONTROL', 'SECURITY_SENSITIVE'] LOOP
        IF hr ->> k IN ('YES', 'NOT_SURE') THEN f := array_append(f, k); high := true; END IF;
    END LOOP;
    IF p.funding_status IN ('FULLY_FUNDED', 'PARTLY_FUNDED', 'APPLICATION_PLANNED') OR coalesce(p.budget, 0) > 0 OR p.joint_grant IN ('YES', 'POSSIBLY') THEN
        f := array_append(f, 'FUNDING'::text);
    END IF;
    IF cardinality(p.agreement_types) > 0 AND NOT (p.agreement_types = ARRAY['NOT_SURE']) THEN f := array_append(f, 'FORMAL_AGREEMENT'::text); END IF;
    IF 'IP_LICENSING' = ANY (p.agreement_types) THEN f := array_append(f, 'IP'::text); END IF;
    IF 'NDA' = ANY (p.agreement_types) THEN f := array_append(f, 'NDA'::text); END IF;
    IF 'DATA_SHARING' = ANY (p.agreement_types) THEN f := array_append(f, 'DATA_SHARING'::text); END IF;
    IF p.coi IN ('YES', 'CONFIDENTIAL') THEN f := array_append(f, 'CONFLICT_OF_INTEREST'::text); END IF;
    flags := f;
    compliance := high OR p.ethics = 'YES' OR p.personal_data = 'YES';
    risk := CASE WHEN high THEN 'HIGH'
                 WHEN coalesce(p.international, false) OR p.personal_data IN ('YES', 'NOT_SURE') OR p.ethics IN ('YES', 'NOT_SURE')
                      OR p.coi IN ('YES', 'CONFIDENTIAL') OR 'IP' = ANY (f) OR 'NDA' = ANY (f) OR 'DATA_SHARING' = ANY (f) THEN 'MEDIUM'
                 ELSE 'LOW' END;
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION partnership.flags_of(partnership.proposal) IS
  'V658: the compliance flags the answers raise for review (international, personal and sensitive data, ethics, human participants, animals, clinical, hazardous, controlled technology, export control, security-sensitive, funding, formal agreement, IP, NDA, data sharing, conflict of interest), whether a compliance review is required (any high-risk activity, sensitive data, ethics or personal data answered yes) and the risk read from them — flags for review, never legal conclusions';

-- the desk a proposal is routed to: the first active rule by priority whose stated conditions all match, else the general desk
CREATE FUNCTION partnership.route_of(p partnership.proposal) RETURNS TABLE (desk_code text, rule_id uuid) LANGUAGE sql STABLE AS $$
    SELECT coalesce(r.desk_code, 'GENERAL'), r.id
      FROM (SELECT 1) one
      LEFT JOIN LATERAL (
          SELECT x.desk_code, x.id FROM partnership.routing_rule x
            JOIN partnership.desk d ON d.code = x.desk_code AND d.active
           WHERE x.active
             AND (x.category IS NULL OR x.category = p.category)
             AND (x.category_group IS NULL OR x.category_group = (SELECT c.grp FROM partnership.category c WHERE c.code = p.category))
             AND (x.international IS NULL OR x.international = coalesce(p.international, false))
             AND (x.org_type IS NULL OR x.org_type = p.org_type)
             AND (x.funding_status IS NULL OR x.funding_status = p.funding_status)
           ORDER BY x.priority LIMIT 1) r ON true
$$;

-- ── 10 · the timeline and the notices ───────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION partnership.log(p_id uuid, p_action text, p_from text, p_to text, p_detail text, p_applicant boolean DEFAULT false)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO partnership.event (proposal_id, actor, actor_office, action, from_status, to_status, detail, applicant_visible)
    VALUES (p_id, partnership.actor(), partnership.actor_office(), p_action, p_from, p_to, p_detail, coalesce(p_applicant, false))
$$;
-- the facts a template reads
CREATE FUNCTION partnership.vars(p_id uuid, p_extra jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
               'REFERENCE', p.reference, 'TITLE', p.title, 'ORGANISATION', p.org_name, 'FIRST_NAME', coalesce(p.first_name, 'Sir/Madam'),
               'RECEIVED', to_char(p.received_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI') || ' (Lagos)',
               'STATUS', partnership.public_status(p.status), 'DESK', (SELECT d.label FROM partnership.desk d WHERE d.code = p.desk_code),
               'CATEGORY', (SELECT c.label FROM partnership.category c WHERE c.code = p.category),
               'ACK_DAYS', s.acknowledge_days::text, 'CONTACT_EMAIL', coalesce(s.contact_email, ''), 'CONTACT_PHONE', coalesce(s.contact_phone, ''))
           || coalesce(p_extra, '{}'::jsonb)
      FROM partnership.proposal p CROSS JOIN partnership.setting s WHERE p.id = p_id
$$;
-- the applicant, by e-mail (never a confidential document)
CREATE FUNCTION partnership.tell_applicant(p_id uuid, p_key text, p_extra jsonb, p_event text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE e text; ref text;
BEGIN
    SELECT p.email, p.reference INTO e, ref FROM partnership.proposal p WHERE p.id = p_id;
    IF e IS NULL OR NOT platform.email_valid(e) THEN RETURN 0; END IF;
    RETURN platform.notify(p_key, NULL, partnership.vars(p_id, p_extra), 'PARTNERSHIP', p_id, e, NULL,
                           'PTN:' || coalesce(ref, p_id::text) || ':' || p_event, ARRAY['EMAIL']);
END $$;
-- a person (the owner, a desk officer, a named reviewer), on the portal and by e-mail
CREATE FUNCTION partnership.tell_person(p_person uuid, p_id uuid, p_key text, p_extra jsonb, p_event text) RETURNS integer LANGUAGE plpgsql AS $$
BEGIN
    IF p_person IS NULL THEN RETURN 0; END IF;
    RETURN platform.tell_person(p_person, p_key, NULL, partnership.vars(p_id, p_extra),
                                'PTN:' || coalesce((SELECT reference FROM partnership.proposal WHERE id = p_id), p_id::text) || ':' || p_event || ':' || p_person::text);
END $$;
-- everyone holding an office (for a Dean or a Head, over the faculty or department named)
CREATE FUNCTION partnership.tell_office(p_office text, p_scope text, p_id uuid, p_key text, p_extra jsonb, p_event text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer := 0; r record;
BEGIN
    FOR r IN SELECT DISTINCT a.person_id FROM iam.office_assignment a
              WHERE a.office_code = p_office AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                AND (p_scope IS NULL OR iam.scope_code(a.scope_kind, a.scope_id) = p_scope) LOOP
        n := n + partnership.tell_person(r.person_id, p_id, p_key, p_extra, p_event);
    END LOOP;
    RETURN n;
END $$;
-- the desk a proposal went to: its officers, else the Linkages office
CREATE FUNCTION partnership.tell_desk(p_id uuid, p_key text, p_extra jsonb, p_event text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer := 0; r record; v_desk text;
BEGIN
    SELECT desk_code INTO v_desk FROM partnership.proposal WHERE id = p_id;
    FOR r IN SELECT o.person_id FROM partnership.desk_officer o WHERE o.desk_code = v_desk AND o.active
             UNION SELECT d.lead_person FROM partnership.desk d WHERE d.code = v_desk AND d.lead_person IS NOT NULL LOOP
        n := n + partnership.tell_person(r.person_id, p_id, p_key, p_extra, p_event);
    END LOOP;
    IF n = 0 THEN n := partnership.tell_office('linkages', NULL, p_id, p_key, p_extra, p_event); END IF;
    RETURN n;
END $$;

-- ── 11 · the public form: a draft by its secret link, its answers, the checks, the submission ───────────────────────────
CREATE FUNCTION partnership.token_hash(p_token text) RETURNS bytea LANGUAGE sql IMMUTABLE AS $$
    SELECT digest(coalesce(p_token, ''), 'sha256')
$$;
-- the proposal behind a secret link (a draft, or a submitted proposal followed by its applicant)
CREATE FUNCTION partnership.by_token(p_token text) RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT p.id FROM partnership.proposal p WHERE p.token_hash = partnership.token_hash(p_token) AND p.source = 'PUBLIC'
$$;

-- the answers of a draft written from the form's JSON: every key optional (a draft is saved as it stands); the vocabularies are
-- the column checks'; texts trimmed, an empty answer cleared
CREATE FUNCTION partnership.save_answers(p_id uuid, a jsonb) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE partnership.proposal p SET
        first_name = CASE WHEN a ? 'firstName' THEN nullif(btrim(a ->> 'firstName'), '') ELSE p.first_name END,
        last_name = CASE WHEN a ? 'lastName' THEN nullif(btrim(a ->> 'lastName'), '') ELSE p.last_name END,
        job_title = CASE WHEN a ? 'jobTitle' THEN nullif(btrim(a ->> 'jobTitle'), '') ELSE p.job_title END,
        org_name = CASE WHEN a ? 'orgName' THEN nullif(btrim(a ->> 'orgName'), '') ELSE p.org_name END,
        org_type = CASE WHEN a ? 'orgType' THEN nullif(btrim(a ->> 'orgType'), '') ELSE p.org_type END,
        org_type_other = CASE WHEN a ? 'orgTypeOther' THEN nullif(btrim(a ->> 'orgTypeOther'), '') ELSE p.org_type_other END,
        email = CASE WHEN a ? 'email' THEN nullif(lower(btrim(a ->> 'email')), '') ELSE p.email END,
        phone = CASE WHEN a ? 'phone' THEN nullif(btrim(a ->> 'phone'), '') ELSE p.phone END,
        country = CASE WHEN a ? 'country' THEN nullif(btrim(a ->> 'country'), '') ELSE p.country END,
        city = CASE WHEN a ? 'city' THEN nullif(btrim(a ->> 'city'), '') ELSE p.city END,
        address = CASE WHEN a ? 'address' THEN nullif(btrim(a ->> 'address'), '') ELSE p.address END,
        website = CASE WHEN a ? 'website' THEN nullif(btrim(a ->> 'website'), '') ELSE p.website END,
        profile_url = CASE WHEN a ? 'profileUrl' THEN nullif(btrim(a ->> 'profileUrl'), '') ELSE p.profile_url END,
        language = CASE WHEN a ? 'language' THEN nullif(btrim(a ->> 'language'), '') ELSE p.language END,
        contact_method = CASE WHEN a ? 'contactMethod' THEN nullif(btrim(a ->> 'contactMethod'), '') ELSE p.contact_method END,
        time_zone = CASE WHEN a ? 'timeZone' THEN nullif(btrim(a ->> 'timeZone'), '') ELSE p.time_zone END,
        proposal_kind = CASE WHEN a ? 'proposalKind' THEN nullif(btrim(a ->> 'proposalKind'), '') ELSE p.proposal_kind END,
        previous_reference = CASE WHEN a ? 'previousReference' THEN nullif(upper(btrim(a ->> 'previousReference')), '') ELSE p.previous_reference END,
        has_contact = CASE WHEN a ? 'hasContact' THEN (a ->> 'hasContact')::boolean ELSE p.has_contact END,
        contact_name = CASE WHEN a ? 'contactName' THEN nullif(btrim(a ->> 'contactName'), '') ELSE p.contact_name END,
        contact_unit = CASE WHEN a ? 'contactUnit' THEN nullif(btrim(a ->> 'contactUnit'), '') ELSE p.contact_unit END,
        contact_email = CASE WHEN a ? 'contactEmail' THEN nullif(lower(btrim(a ->> 'contactEmail')), '') ELSE p.contact_email END,
        collaborated_before = CASE WHEN a ? 'collaboratedBefore' THEN nullif(btrim(a ->> 'collaboratedBefore'), '') ELSE p.collaborated_before END,
        previous_collaboration = CASE WHEN a ? 'previousCollaboration' THEN nullif(btrim(a ->> 'previousCollaboration'), '') ELSE p.previous_collaboration END,
        category = CASE WHEN a ? 'category' THEN nullif(btrim(a ->> 'category'), '') ELSE p.category END,
        secondary_category = CASE WHEN a ? 'secondaryCategory' THEN nullif(btrim(a ->> 'secondaryCategory'), '') ELSE p.secondary_category END,
        title = CASE WHEN a ? 'title' THEN nullif(btrim(a ->> 'title'), '') ELSE p.title END,
        summary = CASE WHEN a ? 'summary' THEN nullif(btrim(a ->> 'summary'), '') ELSE p.summary END,
        description = CASE WHEN a ? 'description' THEN nullif(btrim(a ->> 'description'), '') ELSE p.description END,
        objectives = CASE WHEN a ? 'objectives' THEN nullif(btrim(a ->> 'objectives'), '') ELSE p.objectives END,
        activities = CASE WHEN a ? 'activities' THEN nullif(btrim(a ->> 'activities'), '') ELSE p.activities END,
        expected_results = CASE WHEN a ? 'expectedResults' THEN nullif(btrim(a ->> 'expectedResults'), '') ELSE p.expected_results END,
        why_university = CASE WHEN a ? 'whyUniversity' THEN nullif(btrim(a ->> 'whyUniversity'), '') ELSE p.why_university END,
        faculty_code = CASE WHEN a ? 'facultyCode' THEN nullif(btrim(a ->> 'facultyCode'), '') ELSE p.faculty_code END,
        dept_code = CASE WHEN a ? 'deptCode' THEN nullif(btrim(a ->> 'deptCode'), '') ELSE p.dept_code END,
        unit_text = CASE WHEN a ? 'unitText' THEN nullif(btrim(a ->> 'unitText'), '') ELSE p.unit_text END,
        expertise = CASE WHEN a ? 'expertise' THEN nullif(btrim(a ->> 'expertise'), '') ELSE p.expertise END,
        staff_contact = CASE WHEN a ? 'staffContact' THEN nullif(btrim(a ->> 'staffContact'), '') ELSE p.staff_contact END,
        start_date = CASE WHEN a ? 'startDate' THEN nullif(btrim(a ->> 'startDate'), '')::date ELSE p.start_date END,
        duration = CASE WHEN a ? 'duration' THEN nullif(btrim(a ->> 'duration'), '') ELSE p.duration END,
        collaboration_format = CASE WHEN a ? 'collaborationFormat' THEN nullif(btrim(a ->> 'collaborationFormat'), '') ELSE p.collaboration_format END,
        benefits_university = CASE WHEN a ? 'benefitsUniversity' THEN nullif(btrim(a ->> 'benefitsUniversity'), '') ELSE p.benefits_university END,
        benefits_partner = CASE WHEN a ? 'benefitsPartner' THEN nullif(btrim(a ->> 'benefitsPartner'), '') ELSE p.benefits_partner END,
        funding_status = CASE WHEN a ? 'fundingStatus' THEN nullif(btrim(a ->> 'fundingStatus'), '') ELSE p.funding_status END,
        budget = CASE WHEN a ? 'budget' THEN nullif(regexp_replace(coalesce(a ->> 'budget', ''), '[,\s]', '', 'g'), '')::numeric ELSE p.budget END,
        currency = CASE WHEN a ? 'currency' THEN nullif(upper(btrim(a ->> 'currency')), '') ELSE p.currency END,
        funder = CASE WHEN a ? 'funder' THEN nullif(btrim(a ->> 'funder'), '') ELSE p.funder END,
        joint_grant = CASE WHEN a ? 'jointGrant' THEN nullif(btrim(a ->> 'jointGrant'), '') ELSE p.joint_grant END,
        funding_deadline = CASE WHEN a ? 'fundingDeadline' THEN nullif(btrim(a ->> 'fundingDeadline'), '')::date ELSE p.funding_deadline END,
        resources_requested = CASE WHEN a ? 'resourcesRequested' THEN ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(a -> 'resourcesRequested') x WHERE btrim(x) <> '' ORDER BY 1) ELSE p.resources_requested END,
        resources_other = CASE WHEN a ? 'resourcesOther' THEN nullif(btrim(a ->> 'resourcesOther'), '') ELSE p.resources_other END,
        partner_contribution = CASE WHEN a ? 'partnerContribution' THEN nullif(btrim(a ->> 'partnerContribution'), '') ELSE p.partner_contribution END,
        international = CASE WHEN a ? 'international' THEN (a ->> 'international')::boolean ELSE p.international END,
        countries = CASE WHEN a ? 'countries' THEN ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(a -> 'countries') x WHERE btrim(x) <> '' ORDER BY 1) ELSE p.countries END,
        international_aspects = CASE WHEN a ? 'internationalAspects' THEN ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(a -> 'internationalAspects') x WHERE btrim(x) <> '' ORDER BY 1) ELSE p.international_aspects END,
        agreement_types = CASE WHEN a ? 'agreementTypes' THEN ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(a -> 'agreementTypes') x WHERE btrim(x) <> '' ORDER BY 1) ELSE p.agreement_types END,
        personal_data = CASE WHEN a ? 'personalData' THEN nullif(btrim(a ->> 'personalData'), '') ELSE p.personal_data END,
        sensitive_data = CASE WHEN a ? 'sensitiveData' THEN nullif(btrim(a ->> 'sensitiveData'), '') ELSE p.sensitive_data END,
        sensitive_kinds = CASE WHEN a ? 'sensitiveKinds' THEN ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(a -> 'sensitiveKinds') x WHERE btrim(x) <> '' ORDER BY 1) ELSE p.sensitive_kinds END,
        ethics = CASE WHEN a ? 'ethics' THEN nullif(btrim(a ->> 'ethics'), '') ELSE p.ethics END,
        high_risk = CASE WHEN a ? 'highRisk' THEN coalesce((SELECT jsonb_object_agg(k, v) FROM jsonb_each_text(a -> 'highRisk') e(k, v)
                                                            WHERE k IN ('HUMAN_PARTICIPANTS', 'ANIMALS', 'CLINICAL', 'HAZARDOUS', 'CONTROLLED_TECHNOLOGY',
                                                                        'EXPORT_CONTROL', 'SECURITY_SENSITIVE') AND v IN ('YES', 'NO', 'NOT_SURE')), '{}'::jsonb)
                         ELSE p.high_risk END,
        coi = CASE WHEN a ? 'coi' THEN nullif(btrim(a ->> 'coi'), '') ELSE p.coi END,
        coi_detail = CASE WHEN a ? 'coiDetail' THEN nullif(btrim(a ->> 'coiDetail'), '') ELSE p.coi_detail END,
        own_due_diligence = CASE WHEN a ? 'ownDueDiligence' THEN nullif(btrim(a ->> 'ownDueDiligence'), '') ELSE p.own_due_diligence END,
        declared_accurate = CASE WHEN a ? 'declaredAccurate' THEN coalesce((a ->> 'declaredAccurate')::boolean, false) ELSE p.declared_accurate END,
        declared_authorised = CASE WHEN a ? 'declaredAuthorised' THEN coalesce((a ->> 'declaredAuthorised')::boolean, false) ELSE p.declared_authorised END,
        declared_no_commitment = CASE WHEN a ? 'declaredNoCommitment' THEN coalesce((a ->> 'declaredNoCommitment')::boolean, false) ELSE p.declared_no_commitment END,
        declared_privacy = CASE WHEN a ? 'declaredPrivacy' THEN coalesce((a ->> 'declaredPrivacy')::boolean, false) ELSE p.declared_privacy END,
        consent_contact = CASE WHEN a ? 'consentContact' THEN coalesce((a ->> 'consentContact')::boolean, false) ELSE p.consent_contact END,
        consent_marketing = CASE WHEN a ? 'consentMarketing' THEN coalesce((a ->> 'consentMarketing')::boolean, false) ELSE p.consent_marketing END,
        updated_at = now()
     WHERE p.id = p_id;
EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow OR invalid_datetime_format THEN
        RAISE EXCEPTION 'PTN_ANSWER: an answer could not be read (a date, an amount or a yes/no): %', SQLERRM USING ERRCODE = '23514';
    WHEN check_violation OR foreign_key_violation THEN
        RAISE EXCEPTION 'PTN_ANSWER: an answer is not one the form offers (%)', SQLERRM USING ERRCODE = '23514';
END $$;
COMMENT ON FUNCTION partnership.save_answers(uuid, jsonb) IS 'V658: a draft''s answers written from the form (each key optional, texts trimmed, the vocabularies the columns'' own)';

-- every answer checked, as the form checks it, field by field: the step it is on, the field, what to put right (nothing: ready)
CREATE FUNCTION partnership.problems(p_id uuid) RETURNS TABLE (step integer, field text, message text) LANGUAGE plpgsql STABLE AS $$
DECLARE p partnership.proposal; s partnership.setting; n_files integer; v_text text; k text;
BEGIN
    SELECT * INTO p FROM partnership.proposal WHERE id = p_id;
    SELECT * INTO s FROM partnership.setting WHERE id = 1;
    -- step 1
    IF p.first_name IS NULL THEN step := 1; field := 'firstName'; message := 'First name: enter your first name.'; RETURN NEXT; END IF;
    IF p.last_name IS NULL THEN step := 1; field := 'lastName'; message := 'Last name: enter your last name.'; RETURN NEXT; END IF;
    IF p.org_name IS NULL THEN step := 1; field := 'orgName'; message := 'Organisation name: enter the name of your organisation.'; RETURN NEXT; END IF;
    IF p.org_type IS NULL THEN step := 1; field := 'orgType'; message := 'Organisation type: choose the type of your organisation.'; RETURN NEXT; END IF;
    IF p.org_type = 'OTHER' AND p.org_type_other IS NULL THEN step := 1; field := 'orgTypeOther'; message := 'Organisation type: describe the type of your organisation.'; RETURN NEXT; END IF;
    IF p.email IS NULL OR NOT platform.email_valid(p.email) THEN step := 1; field := 'email'; message := 'Work email address: enter a valid email address for your organisation.'; RETURN NEXT; END IF;
    IF p.phone IS NOT NULL AND p.phone !~ '^\+?[0-9 ()\-]{6,24}$' THEN step := 1; field := 'phone'; message := 'Telephone: enter a telephone number of digits, spaces, brackets or dashes, with the country code.'; RETURN NEXT; END IF;
    IF p.country IS NULL THEN step := 1; field := 'country'; message := 'Country/territory: choose your country or territory.'; RETURN NEXT; END IF;
    IF p.website IS NOT NULL AND p.website !~* '^(https?://)?[a-z0-9.-]+\.[a-z]{2,}(/.*)?$' THEN step := 1; field := 'website'; message := 'Organisation website: enter a web address such as www.example.org.'; RETURN NEXT; END IF;
    IF p.profile_url IS NOT NULL AND p.profile_url !~* '^(https?://)?[a-z0-9.-]+\.[a-z]{2,}(/.*)?$' THEN step := 1; field := 'profileUrl'; message := 'LinkedIn/organisation profile: enter a web address.'; RETURN NEXT; END IF;
    -- step 2
    IF p.proposal_kind IS NULL THEN step := 2; field := 'proposalKind'; message := 'Is this: choose new proposal, existing discussion or follow-up.'; RETURN NEXT; END IF;
    IF p.proposal_kind = 'FOLLOW_UP' AND p.previous_reference IS NULL THEN step := 2; field := 'previousReference'; message := 'Previous reference: enter the reference of your earlier submission (PTN/YYYY/NNNNNN).'; RETURN NEXT; END IF;
    IF p.has_contact IS NULL THEN step := 2; field := 'hasContact'; message := 'University contact: say whether you already have a University contact.'; RETURN NEXT; END IF;
    IF p.has_contact AND p.contact_name IS NULL THEN step := 2; field := 'contactName'; message := 'Contact name: enter the name of your University contact.'; RETURN NEXT; END IF;
    IF p.has_contact AND p.contact_email IS NOT NULL AND NOT platform.email_valid(p.contact_email) THEN step := 2; field := 'contactEmail'; message := 'Contact email: enter a valid email address for your University contact.'; RETURN NEXT; END IF;
    IF p.collaborated_before IS NULL THEN step := 2; field := 'collaboratedBefore'; message := 'Previous collaboration: say whether you have collaborated with the University before.'; RETURN NEXT; END IF;
    IF p.collaborated_before = 'YES' AND p.previous_collaboration IS NULL THEN step := 2; field := 'previousCollaboration'; message := 'Previous collaboration: describe the earlier collaboration.'; RETURN NEXT; END IF;
    -- step 3
    IF p.category IS NULL OR NOT EXISTS (SELECT 1 FROM partnership.category c WHERE c.code = p.category AND c.active) THEN step := 3; field := 'category'; message := 'Primary collaboration category: choose the category that fits best.'; RETURN NEXT; END IF;
    IF p.secondary_category IS NOT NULL AND p.secondary_category = p.category THEN step := 3; field := 'secondaryCategory'; message := 'Secondary category: choose a category other than the primary one, or none.'; RETURN NEXT; END IF;
    IF p.title IS NULL OR length(p.title) < 5 OR length(p.title) > 200 THEN step := 3; field := 'title'; message := 'Proposed partnership title: enter a title of 5 to 200 characters.'; RETURN NEXT; END IF;
    IF p.summary IS NULL OR length(p.summary) < 20 THEN step := 3; field := 'summary'; message := 'Short summary: describe the proposal in at least 20 characters.'; RETURN NEXT;
    ELSIF length(p.summary) > s.summary_max THEN step := 3; field := 'summary'; message := 'Short summary: keep it within ' || s.summary_max || ' characters.'; RETURN NEXT; END IF;
    IF p.description IS NULL OR length(p.description) < 20 THEN step := 3; field := 'description'; message := 'Detailed description: describe the proposal in at least 20 characters.'; RETURN NEXT; END IF;
    FOREACH k IN ARRAY ARRAY['description', 'objectives', 'activities', 'expectedResults', 'whyUniversity'] LOOP
        v_text := CASE k WHEN 'description' THEN p.description WHEN 'objectives' THEN p.objectives WHEN 'activities' THEN p.activities
                         WHEN 'expectedResults' THEN p.expected_results ELSE p.why_university END;
        IF length(coalesce(v_text, '')) > s.text_max THEN step := 3; field := k; message := initcap(regexp_replace(k, '([A-Z])', ' \1', 'g')) || ': keep it within ' || s.text_max || ' characters.'; RETURN NEXT; END IF;
    END LOOP;
    FOREACH k IN ARRAY ARRAY['benefitsUniversity', 'benefitsPartner'] LOOP
        v_text := CASE k WHEN 'benefitsUniversity' THEN p.benefits_university ELSE p.benefits_partner END;
        IF length(coalesce(v_text, '')) > s.benefits_max THEN step := 3; field := k; message := 'Expected benefits: keep each within ' || s.benefits_max || ' characters.'; RETURN NEXT; END IF;
    END LOOP;
    IF p.dept_code IS NOT NULL AND p.faculty_code IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = p.dept_code AND d.faculty_code = p.faculty_code) THEN
        step := 3; field := 'deptCode'; message := 'Relevant department: choose a department of the faculty chosen.'; RETURN NEXT;
    END IF;
    IF p.start_date IS NOT NULL AND p.start_date < partnership.today() - 365 THEN step := 3; field := 'startDate'; message := 'Proposed start date: enter a date that is not long past.'; RETURN NEXT; END IF;
    -- step 4
    IF p.funding_status IS NULL THEN step := 4; field := 'fundingStatus'; message := 'Funding: say whether funding is already available.'; RETURN NEXT; END IF;
    IF p.budget IS NOT NULL AND p.currency IS NULL THEN step := 4; field := 'currency'; message := 'Currency: choose the currency of the estimated budget.'; RETURN NEXT; END IF;
    IF EXISTS (SELECT 1 FROM unnest(p.resources_requested) r WHERE r NOT IN ('STAFF_EXPERTISE', 'RESEARCH_FACILITIES', 'LABORATORY_EQUIPMENT', 'SPECIALIST_EQUIPMENT',
                   'STUDENT_PARTICIPATION', 'TRAINING', 'VENUE', 'DATA_ACCESS', 'BRANDING', 'FINANCIAL_CONTRIBUTION', 'OTHER')) THEN
        step := 4; field := 'resourcesRequested'; message := 'University resources requested: choose from the list.'; RETURN NEXT;
    END IF;
    IF 'OTHER' = ANY (p.resources_requested) AND p.resources_other IS NULL THEN step := 4; field := 'resourcesOther'; message := 'Other resources: describe the other resources requested.'; RETURN NEXT; END IF;
    -- step 5
    IF p.international IS NULL THEN step := 5; field := 'international'; message := 'Partners outside the country: say whether the proposal involves partners outside the country.'; RETURN NEXT; END IF;
    IF p.international AND cardinality(p.countries) = 0 THEN step := 5; field := 'countries'; message := 'Countries involved: name the countries involved.'; RETURN NEXT; END IF;
    IF EXISTS (SELECT 1 FROM unnest(p.international_aspects) r WHERE r NOT IN ('ACTIVITIES', 'FUNDING', 'RESEARCH', 'TRAVEL', 'DATA_PROCESSING')) THEN
        step := 5; field := 'internationalAspects'; message := 'What involves other countries: choose from the list.'; RETURN NEXT;
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(p.agreement_types) r WHERE r NOT IN ('MOU', 'MOA', 'RESEARCH_AGREEMENT', 'STUDENT_EXCHANGE', 'NDA', 'DATA_SHARING', 'IP_LICENSING', 'NOT_SURE')) THEN
        step := 5; field := 'agreementTypes'; message := 'Formal agreement: choose from the list.'; RETURN NEXT;
    END IF;
    IF p.personal_data IS NULL THEN step := 5; field := 'personalData'; message := 'Personal data: say whether the project will involve personal data.'; RETURN NEXT; END IF;
    IF p.personal_data = 'YES' AND p.sensitive_data IS NULL THEN step := 5; field := 'sensitiveData'; message := 'Sensitive personal data: say whether it will involve sensitive personal data.'; RETURN NEXT; END IF;
    IF EXISTS (SELECT 1 FROM unnest(p.sensitive_kinds) r WHERE r NOT IN ('HEALTH', 'BIOMETRICS', 'CHILDREN', 'DEMOGRAPHIC', 'OTHER')) THEN
        step := 5; field := 'sensitiveKinds'; message := 'Sensitive data: choose from the list.'; RETURN NEXT;
    END IF;
    IF p.ethics IS NULL THEN step := 5; field := 'ethics'; message := 'Ethics approval: say whether the project will require ethics approval.'; RETURN NEXT; END IF;
    FOREACH k IN ARRAY ARRAY['HUMAN_PARTICIPANTS', 'ANIMALS', 'CLINICAL', 'HAZARDOUS', 'CONTROLLED_TECHNOLOGY', 'EXPORT_CONTROL', 'SECURITY_SENSITIVE'] LOOP
        IF NOT p.high_risk ? k THEN
            step := 5; field := 'highRisk.' || k; message := initcap(replace(k, '_', ' ')) || ': answer yes, no or not sure.'; RETURN NEXT;
        END IF;
    END LOOP;
    IF p.coi IS NULL THEN step := 5; field := 'coi'; message := 'Conflicts of interest: answer yes, no, or prefer to discuss confidentially.'; RETURN NEXT; END IF;
    IF p.coi = 'YES' AND p.coi_detail IS NULL THEN step := 5; field := 'coiDetail'; message := 'Conflicts of interest: describe what should be disclosed.'; RETURN NEXT; END IF;
    IF length(coalesce(p.coi_detail, '')) > s.benefits_max THEN step := 5; field := 'coiDetail'; message := 'Conflicts of interest: keep it within ' || s.benefits_max || ' characters.'; RETURN NEXT; END IF;
    IF p.own_due_diligence IS NULL THEN step := 5; field := 'ownDueDiligence'; message := 'Due diligence: say whether your organisation has conducted its own review.'; RETURN NEXT; END IF;
    -- step 6
    SELECT count(*) INTO n_files FROM partnership.attachment a WHERE a.proposal_id = p_id AND a.from_applicant AND a.kind <> 'REQUESTED_DOCUMENT';
    IF n_files > s.max_files THEN step := 6; field := 'attachments'; message := 'Attachments: attach at most ' || s.max_files || ' files.'; RETURN NEXT; END IF;
    -- step 7
    IF NOT p.declared_accurate THEN step := 7; field := 'declaredAccurate'; message := 'Declaration: confirm that the information is accurate.'; RETURN NEXT; END IF;
    IF NOT p.declared_authorised THEN step := 7; field := 'declaredAuthorised'; message := 'Declaration: confirm that you are authorised to submit this enquiry.'; RETURN NEXT; END IF;
    IF NOT p.declared_no_commitment THEN step := 7; field := 'declaredNoCommitment'; message := 'Declaration: confirm that you understand this creates no legal, financial or contractual relationship.'; RETURN NEXT; END IF;
    IF NOT p.declared_privacy THEN step := 7; field := 'declaredPrivacy'; message := 'Declaration: confirm that you have read the privacy notice.'; RETURN NEXT; END IF;
    IF NOT p.consent_contact THEN step := 7; field := 'consentContact'; message := 'Consent: agree to be contacted about this collaboration request.'; RETURN NEXT; END IF;
END $$;
COMMENT ON FUNCTION partnership.problems(uuid) IS 'V658: every answer of a draft checked as the server checks it — the step, the field and what to put right; none means it may be submitted';

-- a public draft: made with its secret link (the link is returned once; its hash is kept), its answers saved as they stand
CREATE FUNCTION partnership.draft_create(p_token text, p_answers jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    IF NOT (SELECT public_open FROM partnership.setting WHERE id = 1) THEN
        RAISE EXCEPTION 'PTN_CLOSED: the collaboration enquiry form is closed for now' USING ERRCODE = '23514';
    END IF;
    IF p_token IS NULL OR length(p_token) < 32 THEN RAISE EXCEPTION 'PTN_TOKEN: a draft needs its secret link' USING ERRCODE = '23514'; END IF;
    INSERT INTO partnership.proposal (status, source, token_hash) VALUES ('DRAFT', 'PUBLIC', partnership.token_hash(p_token)) RETURNING id INTO v_id;
    PERFORM partnership.save_answers(v_id, coalesce(p_answers, '{}'::jsonb));
    RETURN v_id;
END $$;
CREATE FUNCTION partnership.draft_id(p_token text) RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE v_id uuid; v_status text; v_created timestamptz;
BEGIN
    SELECT p.id, p.status, p.created_at INTO v_id, v_status, v_created FROM partnership.proposal p WHERE p.token_hash = partnership.token_hash(p_token) AND p.source = 'PUBLIC';
    IF v_id IS NULL OR (v_status = 'DRAFT' AND v_created < now() - make_interval(days => (SELECT draft_days FROM partnership.setting WHERE id = 1))) THEN
        RAISE EXCEPTION 'PTN_NOT_FOUND: no draft or enquiry at that link (a draft is kept % days)', (SELECT draft_days FROM partnership.setting WHERE id = 1) USING ERRCODE = 'P0002';
    END IF;
    RETURN v_id;
END $$;
CREATE FUNCTION partnership.draft_save(p_token text, p_answers jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := partnership.draft_id(p_token);
BEGIN
    IF (SELECT status FROM partnership.proposal WHERE id = v_id) <> 'DRAFT' THEN
        RAISE EXCEPTION 'PTN_SUBMITTED: this enquiry has been submitted; follow it from the link in its acknowledgement' USING ERRCODE = '23514';
    END IF;
    PERFORM partnership.save_answers(v_id, coalesce(p_answers, '{}'::jsonb));
    RETURN v_id;
END $$;

-- the submission: answers checked again on the server, a duplicate refused, the reference issued, flags and risk read, routed
-- to its desk (its lead the owner where the desk has one), due by the acknowledgement time, the applicant acknowledged and the
-- desk told. Submitting twice through the same link answers with the same reference (idempotent).
CREATE FUNCTION partnership.submit(p_token text, p_answers jsonb, p_links jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (id uuid, reference text, received_at timestamptz, email text, already boolean) LANGUAGE plpgsql AS $$
DECLARE v_id uuid := partnership.draft_id(p_token); p partnership.proposal; s partnership.setting; f record; r record; v_bad text; v_dup text;
BEGIN
    SELECT * INTO p FROM partnership.proposal x WHERE x.id = v_id FOR UPDATE;
    IF p.status <> 'DRAFT' THEN
        id := p.id; reference := p.reference; received_at := p.received_at; email := p.email; already := true; RETURN NEXT; RETURN;
    END IF;
    IF NOT (SELECT public_open FROM partnership.setting WHERE setting.id = 1) THEN
        RAISE EXCEPTION 'PTN_CLOSED: the collaboration enquiry form is closed for now' USING ERRCODE = '23514';
    END IF;
    IF p_answers IS NOT NULL THEN PERFORM partnership.save_answers(v_id, p_answers); END IF;
    SELECT x.message INTO v_bad FROM partnership.problems(v_id) x LIMIT 1;
    IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'PTN_INVALID: %', v_bad USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM partnership.proposal x WHERE x.id = v_id;
    SELECT x.reference INTO v_dup FROM partnership.proposal x
     WHERE x.status <> 'DRAFT' AND x.id <> v_id AND lower(x.email) = lower(p.email) AND lower(x.title) = lower(p.title)
       AND x.received_at > now() - interval '24 hours' LIMIT 1;
    IF v_dup IS NOT NULL THEN
        RAISE EXCEPTION 'PTN_DUPLICATE: an enquiry with this title from this email address was received in the last day; add to it from the link in its acknowledgement'
            USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM partnership.setting WHERE setting.id = 1;
    SELECT * INTO f FROM partnership.flags_of(p);
    SELECT * INTO r FROM partnership.route_of(p);
    UPDATE partnership.proposal x SET
        status = 'RECEIVED', reference = partnership.next_reference(), received_at = now(),
        flags = f.flags, compliance_review = f.compliance, risk_level = f.risk,
        desk_code = r.desk_code, routing_rule = r.rule_id,
        owner_person = (SELECT d.lead_person FROM partnership.desk d WHERE d.code = r.desk_code),
        owner_assigned_at = CASE WHEN (SELECT d.lead_person FROM partnership.desk d WHERE d.code = r.desk_code) IS NOT NULL THEN now() END,
        due_on = partnership.add_working_days(partnership.today(), s.acknowledge_days),
        next_action = 'Initial screening', acknowledged_at = now(), updated_at = now()
     WHERE x.id = v_id;
    PERFORM partnership.log(v_id, 'SUBMITTED', 'DRAFT', 'RECEIVED', 'Received on the public form', true);
    PERFORM partnership.log(v_id, 'ROUTED', NULL, NULL, 'Routed to ' || (SELECT d.label FROM partnership.desk d WHERE d.code = r.desk_code)
        || coalesce(' by the rule "' || (SELECT rr.note FROM partnership.routing_rule rr WHERE rr.id = r.rule_id) || '"', ' (no rule matched)'), false);
    IF f.compliance THEN PERFORM partnership.log(v_id, 'COMPLIANCE_REVIEW_REQUIRED', NULL, NULL, array_to_string(f.flags, ', '), false); END IF;
    PERFORM partnership.tell_applicant(v_id, 'PARTNERSHIP_RECEIVED', coalesce(p_links, '{}'::jsonb), 'RECEIVED');
    PERFORM partnership.tell_desk(v_id, 'PARTNERSHIP_SUBMITTED', '{}'::jsonb, 'SUBMITTED');
    SELECT * INTO p FROM partnership.proposal x WHERE x.id = v_id;
    id := p.id; reference := p.reference; received_at := p.received_at; email := p.email; already := false;
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION partnership.submit(text, jsonb, jsonb) IS
  'V658: a public draft submitted — checked again on the server, a duplicate (the same title from the same address within a day) refused, PTN/YYYY/NNNNNN issued, the compliance flags and risk read, routed to its desk (its lead the owner where it has one), due by the acknowledgement time, the applicant acknowledged and the desk told; through the same link a second time, the same reference';

-- a submitted enquiry's private link issued again to the address it was sent from (the earlier link stops working); nothing is
-- said of a reference and address that do not match
CREATE FUNCTION partnership.new_link(p_reference text, p_email text, p_token text, p_links jsonb) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    IF p_token IS NULL OR length(p_token) < 32 THEN RAISE EXCEPTION 'PTN_TOKEN: a link needs its secret' USING ERRCODE = '23514'; END IF;
    SELECT p.id INTO v_id FROM partnership.proposal p
     WHERE p.reference = upper(btrim(coalesce(p_reference, ''))) AND lower(p.email) = lower(btrim(coalesce(p_email, ''))) AND p.source = 'PUBLIC' AND p.status <> 'DRAFT';
    IF v_id IS NULL THEN RETURN false; END IF;
    UPDATE partnership.proposal SET token_hash = partnership.token_hash(p_token), updated_at = now() WHERE id = v_id;
    PERFORM partnership.log(v_id, 'LINK_REISSUED', NULL, NULL, 'A new private link sent to the applicant''s address', false);
    PERFORM partnership.tell_applicant(v_id, 'PARTNERSHIP_LINK', coalesce(p_links, '{}'::jsonb), 'LINK:' || extract(epoch FROM clock_timestamp())::bigint);
    RETURN true;
END $$;

-- drafts left past their time are removed with their files
CREATE FUNCTION partnership.purge_drafts() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
    DELETE FROM partnership.proposal p WHERE p.status = 'DRAFT' AND p.source = 'PUBLIC'
       AND p.created_at < now() - make_interval(days => (SELECT draft_days FROM partnership.setting WHERE id = 1));
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- an office brought into a proposal by the workflow itself (the Legal Officer for due diligence and agreements), once
CREATE FUNCTION partnership.ensure_reviewer(p_id uuid, p_office text, p_role text) RETURNS void LANGUAGE sql AS $$
    INSERT INTO partnership.reviewer (proposal_id, office_code, role_label, due_on, assigned_by)
    SELECT p_id, p_office, p_role, partnership.add_working_days(partnership.today(), (SELECT review_days FROM partnership.setting WHERE id = 1)),
           coalesce(partnership.actor(), '00000000-0000-0000-0000-000000000000')
     WHERE NOT EXISTS (SELECT 1 FROM partnership.reviewer r WHERE r.proposal_id = p_id AND r.office_code = p_office AND r.person_id IS NULL AND r.withdrawn_at IS NULL)
$$;

-- ── 12 · the workflow: one function, every action checked against the office and the status it may move from ────────────
-- START_SCREENING, ROUTE {desk, note}, ASSIGN {person}, ACCEPT {note}, REQUEST_INFORMATION {question, documents, deadline, reason},
-- WITHDRAW_REQUEST, START_DUE_DILIGENCE, MEETING {note}, DEVELOP {note}, SUBMIT_FOR_APPROVAL {note}, APPROVE {note},
-- DECLINE {reason, message}, IMPLEMENT {note}, ACTIVATE {note}, CLOSE {reason}, CANCEL {reason}
CREATE FUNCTION partnership.act(p_id uuid, p_action text, p_data jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE p partnership.proposal; s partnership.setting; a text := upper(btrim(coalesce(p_action, ''))); d jsonb := coalesce(p_data, '{}'::jsonb);
        v_to text; v_note text := nullif(btrim(coalesce(d ->> 'note', d ->> 'reason', '')), ''); v_person uuid; v_desk text; v_deadline date;
        v_open integer;
BEGIN
    SELECT * INTO p FROM partnership.proposal WHERE id = p_id FOR UPDATE;
    PERFORM partnership.require_see(p_id);
    SELECT * INTO s FROM partnership.setting WHERE id = 1;
    IF partnership.terminal(p.status) THEN
        RAISE EXCEPTION 'PTN_STATUS: % is %; nothing more is done to it', p.reference, lower(p.status) USING ERRCODE = '23514';
    END IF;
    CASE a
    WHEN 'START_SCREENING' THEN
        PERFORM partnership.require('SCREEN_PARTNERSHIP');
        IF p.status NOT IN ('RECEIVED', 'ROUTED', 'ASSIGNED') THEN RAISE EXCEPTION 'PTN_STATUS: screening starts on a proposal received, routed or assigned' USING ERRCODE = '23514'; END IF;
        v_to := 'INITIAL_SCREENING';
        UPDATE partnership.proposal SET status = v_to, next_action = 'Accept for review, request information, route or decline', updated_at = now() WHERE id = p_id;
    WHEN 'ROUTE' THEN
        PERFORM partnership.require('ROUTE_PARTNERSHIP');
        IF p.status NOT IN ('RECEIVED', 'INITIAL_SCREENING', 'ROUTED', 'ASSIGNED', 'UNDER_REVIEW') THEN
            RAISE EXCEPTION 'PTN_STATUS: a proposal is routed while it is screened or reviewed' USING ERRCODE = '23514';
        END IF;
        v_desk := upper(btrim(coalesce(d ->> 'desk', '')));
        IF NOT EXISTS (SELECT 1 FROM partnership.desk WHERE code = v_desk AND active) THEN RAISE EXCEPTION 'PTN_DESK: no such desk %', v_desk USING ERRCODE = '23514'; END IF;
        IF v_note IS NULL OR length(v_note) < 5 THEN RAISE EXCEPTION 'PTN_REASON: say why it is routed there' USING ERRCODE = '23514'; END IF;
        v_to := 'ROUTED';
        UPDATE partnership.proposal SET status = v_to, desk_code = v_desk, routing_rule = NULL,
               owner_person = (SELECT lead_person FROM partnership.desk WHERE code = v_desk),
               owner_assigned_at = CASE WHEN (SELECT lead_person FROM partnership.desk WHERE code = v_desk) IS NOT NULL THEN now() END,
               next_action = 'Assign an owner', updated_at = now() WHERE id = p_id;
        PERFORM partnership.tell_desk(p_id, 'PARTNERSHIP_ROUTED', '{}'::jsonb, 'ROUTED:' || v_desk || ':' || extract(epoch FROM now())::bigint);
    WHEN 'ASSIGN' THEN
        PERFORM partnership.require('ASSIGN_PARTNERSHIP');
        v_person := nullif(d ->> 'person', '')::uuid;
        IF v_person IS NULL OR NOT (EXISTS (SELECT 1 FROM iam.office_assignment x WHERE x.person_id = v_person AND x.office_code = 'linkages'
                                              AND x.valid_from <= current_date AND (x.valid_to IS NULL OR x.valid_to >= current_date))
                                    OR EXISTS (SELECT 1 FROM partnership.desk_officer o WHERE o.person_id = v_person AND o.active)) THEN
            RAISE EXCEPTION 'PTN_OWNER: an owner is an officer of the Linkages & Partnerships office or of one of its desks' USING ERRCODE = '23514';
        END IF;
        v_to := CASE WHEN p.status IN ('RECEIVED', 'INITIAL_SCREENING', 'ROUTED') THEN 'ASSIGNED' ELSE p.status END;
        UPDATE partnership.proposal SET status = v_to, owner_person = v_person, owner_assigned_at = now(),
               due_on = CASE WHEN v_to = 'ASSIGNED' THEN partnership.add_working_days(partnership.today(), s.screening_days) ELSE due_on END,
               next_action = CASE WHEN v_to = 'ASSIGNED' THEN 'Initial screening' ELSE next_action END, updated_at = now() WHERE id = p_id;
        v_note := coalesce(v_note, 'Owner: ' || helpdesk.person_name(v_person));
        PERFORM partnership.tell_person(v_person, p_id, 'PARTNERSHIP_ASSIGNED', '{}'::jsonb, 'ASSIGNED:' || extract(epoch FROM now())::bigint);
    WHEN 'ACCEPT' THEN
        PERFORM partnership.require('SCREEN_PARTNERSHIP');
        IF p.status NOT IN ('RECEIVED', 'INITIAL_SCREENING', 'ROUTED', 'ASSIGNED') THEN RAISE EXCEPTION 'PTN_STATUS: a proposal is accepted for review from screening' USING ERRCODE = '23514'; END IF;
        IF p.owner_person IS NULL THEN RAISE EXCEPTION 'PTN_OWNER_REQUIRED: assign an owner before the proposal is accepted for review' USING ERRCODE = '23514'; END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE partnership.proposal SET status = v_to,
               due_on = partnership.add_working_days(partnership.today(), CASE WHEN p.compliance_review OR p.risk_level = 'HIGH' THEN s.complex_review_days ELSE s.review_days END),
               next_action = 'Review', updated_at = now() WHERE id = p_id;
        PERFORM partnership.tell_applicant(p_id, 'PARTNERSHIP_REVIEW_STARTED', '{}'::jsonb, 'REVIEW_STARTED');
    WHEN 'REQUEST_INFORMATION' THEN
        PERFORM partnership.require('REQUEST_INFORMATION');
        IF p.status = 'AWAITING_INFORMATION' THEN RAISE EXCEPTION 'PTN_REQUEST_OPEN: a request is already waiting for the applicant' USING ERRCODE = '23514'; END IF;
        IF p.status IN ('AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE') THEN RAISE EXCEPTION 'PTN_STATUS: an active partnership is followed by its messages, not a request' USING ERRCODE = '23514'; END IF;
        IF length(btrim(coalesce(d ->> 'question', ''))) < 10 THEN RAISE EXCEPTION 'PTN_QUESTION: write the question or request (10 characters at least)' USING ERRCODE = '23514'; END IF;
        v_deadline := coalesce(nullif(d ->> 'deadline', '')::date, partnership.add_working_days(partnership.today(), s.info_days));
        IF v_deadline <= partnership.today() THEN RAISE EXCEPTION 'PTN_DEADLINE: the deadline is a date after today' USING ERRCODE = '23514'; END IF;
        INSERT INTO partnership.info_request (proposal_id, question, documents, deadline, reason, resume_status, requested_by)
        VALUES (p_id, btrim(d ->> 'question'), nullif(btrim(coalesce(d ->> 'documents', '')), ''), v_deadline, v_note, p.status, partnership.actor());
        v_to := 'AWAITING_INFORMATION';
        UPDATE partnership.proposal SET status = v_to, due_on = v_deadline, next_action = 'Waiting for the applicant', updated_at = now() WHERE id = p_id;
        PERFORM partnership.tell_applicant(p_id, 'PARTNERSHIP_INFORMATION_REQUESTED',
            jsonb_build_object('QUESTION', btrim(d ->> 'question'), 'DOCUMENTS', coalesce(nullif(btrim(coalesce(d ->> 'documents', '')), ''), 'none'),
                               'DEADLINE', to_char(v_deadline, 'DD Mon YYYY')),
            'INFO:' || (SELECT count(*) FROM partnership.info_request WHERE proposal_id = p_id));
        v_note := 'Requested: ' || btrim(d ->> 'question') || ' — by ' || to_char(v_deadline, 'DD Mon YYYY');
    WHEN 'WITHDRAW_REQUEST' THEN
        PERFORM partnership.require('REQUEST_INFORMATION');
        IF p.status <> 'AWAITING_INFORMATION' THEN RAISE EXCEPTION 'PTN_STATUS: no request is waiting' USING ERRCODE = '23514'; END IF;
        SELECT resume_status INTO v_to FROM partnership.info_request WHERE proposal_id = p_id AND answered_at IS NULL AND withdrawn_at IS NULL;
        UPDATE partnership.info_request SET withdrawn_at = now() WHERE proposal_id = p_id AND answered_at IS NULL AND withdrawn_at IS NULL;
        UPDATE partnership.proposal SET status = v_to, next_action = 'Continue', updated_at = now() WHERE id = p_id;
    WHEN 'START_DUE_DILIGENCE' THEN
        PERFORM partnership.require('DUE_DILIGENCE');
        IF p.status NOT IN ('UNDER_REVIEW', 'MEETING_PROPOSED', 'UNDER_DEVELOPMENT') THEN RAISE EXCEPTION 'PTN_STATUS: due diligence follows review' USING ERRCODE = '23514'; END IF;
        INSERT INTO partnership.due_diligence (proposal_id, item_code) SELECT p_id, i.code FROM partnership.dd_item i WHERE i.active ON CONFLICT DO NOTHING;
        PERFORM partnership.ensure_reviewer(p_id, 'legal', 'Due diligence and agreements');
        v_to := 'DUE_DILIGENCE';
        UPDATE partnership.proposal SET status = v_to, next_action = 'Complete the due-diligence checklist', updated_at = now() WHERE id = p_id;
        PERFORM partnership.tell_person(p.owner_person, p_id, 'PARTNERSHIP_DUE_DILIGENCE_REQUIRED', '{}'::jsonb, 'DD');
        PERFORM partnership.tell_office('legal', NULL, p_id, 'PARTNERSHIP_DUE_DILIGENCE_REQUIRED', '{}'::jsonb, 'DD');
    WHEN 'MEETING' THEN
        PERFORM partnership.require('SCREEN_PARTNERSHIP');
        IF p.status NOT IN ('UNDER_REVIEW', 'DUE_DILIGENCE', 'UNDER_DEVELOPMENT') THEN RAISE EXCEPTION 'PTN_STATUS: a meeting is proposed during review or development' USING ERRCODE = '23514'; END IF;
        v_to := 'MEETING_PROPOSED';
        UPDATE partnership.proposal SET status = v_to, next_action = 'Meeting', updated_at = now() WHERE id = p_id;
    WHEN 'DEVELOP' THEN
        PERFORM partnership.require('SCREEN_PARTNERSHIP');
        IF p.status NOT IN ('UNDER_REVIEW', 'DUE_DILIGENCE', 'MEETING_PROPOSED') THEN RAISE EXCEPTION 'PTN_STATUS: development follows review' USING ERRCODE = '23514'; END IF;
        v_to := 'UNDER_DEVELOPMENT';
        UPDATE partnership.proposal SET status = v_to, next_action = 'Develop the partnership; submit for approval', updated_at = now() WHERE id = p_id;
    WHEN 'SUBMIT_FOR_APPROVAL' THEN
        PERFORM partnership.require('SCREEN_PARTNERSHIP');
        IF p.status NOT IN ('UNDER_REVIEW', 'DUE_DILIGENCE', 'MEETING_PROPOSED', 'UNDER_DEVELOPMENT') THEN RAISE EXCEPTION 'PTN_STATUS: a proposal goes for approval from review or development' USING ERRCODE = '23514'; END IF;
        SELECT count(*) INTO v_open FROM partnership.due_diligence WHERE proposal_id = p_id AND status = 'PENDING';
        IF v_open > 0 THEN RAISE EXCEPTION 'PTN_DD_OPEN: % due-diligence check(s) still pending', v_open USING ERRCODE = '23514'; END IF;
        IF p.compliance_review AND NOT EXISTS (SELECT 1 FROM partnership.due_diligence WHERE proposal_id = p_id) THEN
            RAISE EXCEPTION 'PTN_DD_REQUIRED: the answers require a compliance review; complete due diligence first' USING ERRCODE = '23514';
        END IF;
        v_to := 'PENDING_APPROVAL';
        UPDATE partnership.proposal SET status = v_to, next_action = 'The Vice-Chancellor''s decision', updated_at = now() WHERE id = p_id;
        PERFORM partnership.tell_office('vc', NULL, p_id, 'PARTNERSHIP_APPROVAL_REQUIRED', '{}'::jsonb, 'APPROVAL:' || extract(epoch FROM now())::bigint);
    WHEN 'APPROVE' THEN
        PERFORM partnership.require('APPROVE_PARTNERSHIP');
        IF p.status <> 'PENDING_APPROVAL' THEN RAISE EXCEPTION 'PTN_STATUS: only a proposal pending approval is approved' USING ERRCODE = '23514'; END IF;
        v_to := 'APPROVED_FOR_DEVELOPMENT';
        UPDATE partnership.proposal SET status = v_to, decided_at = now(), decided_by = partnership.actor(),
               next_action = CASE WHEN cardinality(agreement_types) > 0 AND agreement_types <> ARRAY['NOT_SURE'] OR 'FORMAL_AGREEMENT' = ANY (flags)
                                  THEN 'Prepare the agreement' ELSE 'Implement' END, updated_at = now() WHERE id = p_id;
        PERFORM partnership.tell_applicant(p_id, 'PARTNERSHIP_APPROVED', '{}'::jsonb, 'APPROVED');
        PERFORM partnership.tell_person(p.owner_person, p_id, 'PARTNERSHIP_APPROVED', '{}'::jsonb, 'APPROVED');
    WHEN 'DECLINE' THEN
        PERFORM partnership.require('DECLINE_PARTNERSHIP');
        IF p.status = 'PENDING_APPROVAL' THEN PERFORM partnership.require('APPROVE_PARTNERSHIP'); END IF;
        IF p.status IN ('APPROVED_FOR_DEVELOPMENT', 'AGREEMENT_REVIEW', 'AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE') THEN
            RAISE EXCEPTION 'PTN_STATUS: an approved partnership is closed, not declined' USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL OR length(v_note) < 10 THEN RAISE EXCEPTION 'PTN_REASON: give the reason it is declined (10 characters at least)' USING ERRCODE = '23514'; END IF;
        v_to := 'DECLINED';
        UPDATE partnership.proposal SET status = v_to, decided_at = now(), decided_by = partnership.actor(), closed_at = now(), close_reason = v_note,
               next_action = NULL, due_on = NULL, updated_at = now() WHERE id = p_id;
        UPDATE partnership.info_request SET withdrawn_at = now() WHERE proposal_id = p_id AND answered_at IS NULL AND withdrawn_at IS NULL;
        PERFORM partnership.tell_applicant(p_id, 'PARTNERSHIP_DECLINED',
            jsonb_build_object('MESSAGE', coalesce(nullif(btrim(coalesce(d ->> 'message', '')), ''), 'The University will not take the proposal forward at this time.')), 'DECLINED');
    WHEN 'IMPLEMENT' THEN
        PERFORM partnership.require('SCREEN_PARTNERSHIP');
        IF p.status NOT IN ('APPROVED_FOR_DEVELOPMENT', 'AGREEMENT_EXECUTED') THEN RAISE EXCEPTION 'PTN_STATUS: implementation follows approval or the agreement''s execution' USING ERRCODE = '23514'; END IF;
        IF p.status = 'APPROVED_FOR_DEVELOPMENT' AND EXISTS (SELECT 1 FROM partnership.agreement g WHERE g.proposal_id = p_id AND g.status NOT IN ('EXECUTED', 'WITHDRAWN', 'TERMINATED', 'EXPIRED')) THEN
            RAISE EXCEPTION 'PTN_AGREEMENT_OPEN: an agreement of this partnership is still being prepared' USING ERRCODE = '23514';
        END IF;
        v_to := 'IMPLEMENTATION';
        UPDATE partnership.proposal SET status = v_to, next_action = 'Implementation', updated_at = now() WHERE id = p_id;
    WHEN 'ACTIVATE' THEN
        PERFORM partnership.require('SCREEN_PARTNERSHIP');
        IF p.status NOT IN ('IMPLEMENTATION', 'AGREEMENT_EXECUTED', 'APPROVED_FOR_DEVELOPMENT') THEN RAISE EXCEPTION 'PTN_STATUS: a partnership becomes active once approved (and its agreement executed)' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM partnership.agreement g WHERE g.proposal_id = p_id AND g.status IN ('DRAFT', 'LEGAL_REVIEW', 'APPROVAL', 'SIGNING')) THEN
            RAISE EXCEPTION 'PTN_AGREEMENT_OPEN: an agreement of this partnership is still being prepared' USING ERRCODE = '23514';
        END IF;
        v_to := 'ACTIVE';
        UPDATE partnership.proposal SET status = v_to, next_action = 'Monitor activities and outcomes', due_on = NULL, updated_at = now() WHERE id = p_id;
        PERFORM partnership.tell_applicant(p_id, 'PARTNERSHIP_ACTIVE', '{}'::jsonb, 'ACTIVE');
    WHEN 'CLOSE', 'CANCEL' THEN
        PERFORM partnership.require('CLOSE_PARTNERSHIP');
        IF v_note IS NULL OR length(v_note) < 10 THEN RAISE EXCEPTION 'PTN_REASON: give the reason (10 characters at least)' USING ERRCODE = '23514'; END IF;
        v_to := CASE a WHEN 'CLOSE' THEN 'CLOSED' ELSE 'CANCELLED' END;
        UPDATE partnership.proposal SET status = v_to, closed_at = now(), close_reason = v_note, next_action = NULL, due_on = NULL, updated_at = now() WHERE id = p_id;
        UPDATE partnership.info_request SET withdrawn_at = now() WHERE proposal_id = p_id AND answered_at IS NULL AND withdrawn_at IS NULL;
        IF a = 'CLOSE' THEN PERFORM partnership.tell_applicant(p_id, 'PARTNERSHIP_CLOSED', '{}'::jsonb, 'CLOSED'); END IF;
    ELSE
        RAISE EXCEPTION 'PTN_ACTION: no such action %', a USING ERRCODE = '23514';
    END CASE;
    PERFORM partnership.log(p_id, a, p.status, v_to, v_note,
        a IN ('ACCEPT', 'REQUEST_INFORMATION', 'APPROVE', 'DECLINE', 'ACTIVATE', 'CLOSE', 'CANCEL', 'MEETING', 'IMPLEMENT'));
    RETURN v_to;
END $$;
COMMENT ON FUNCTION partnership.act(uuid, text, jsonb) IS
  'V658: the one workflow — screening, routing, assignment, acceptance for review, a request for information, due diligence, a meeting, development, the Vice-Chancellor''s approval or a decline, implementation, activation, closure — each checked against the acting office''s grants, what it may see and the status it moves from, on the timeline, the applicant told where it concerns them';

-- the applicant's answer to the open request: written, the proposal back where it was, the owner told
CREATE FUNCTION partnership.answer_request(p_token text, p_answer text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_id uuid := partnership.draft_id(p_token); r partnership.info_request; v_to text;
BEGIN
    SELECT * INTO r FROM partnership.info_request WHERE proposal_id = v_id AND answered_at IS NULL AND withdrawn_at IS NULL FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'PTN_NO_REQUEST: nothing is waiting for an answer' USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_answer, ''))) < 2 OR length(p_answer) > 8000 THEN
        RAISE EXCEPTION 'PTN_ANSWER: write the answer (up to 8,000 characters)' USING ERRCODE = '23514';
    END IF;
    UPDATE partnership.info_request SET answer = btrim(p_answer), answered_at = now() WHERE id = r.id;
    INSERT INTO partnership.message (proposal_id, kind, body) VALUES (v_id, 'APPLICANT_REPLY', btrim(p_answer));
    v_to := r.resume_status;
    UPDATE partnership.proposal SET status = v_to, next_action = 'Read the applicant''s answer',
           due_on = partnership.add_working_days(partnership.today(), (SELECT screening_days FROM partnership.setting WHERE id = 1)), updated_at = now()
     WHERE id = v_id;
    PERFORM partnership.log(v_id, 'INFORMATION_RECEIVED', 'AWAITING_INFORMATION', v_to, 'The applicant answered the request', true);
    IF (SELECT owner_person FROM partnership.proposal WHERE id = v_id) IS NOT NULL THEN
        PERFORM partnership.tell_person((SELECT owner_person FROM partnership.proposal WHERE id = v_id), v_id, 'PARTNERSHIP_INFORMATION_RECEIVED', '{}'::jsonb, 'ANSWER:' || r.id);
    ELSE
        PERFORM partnership.tell_desk(v_id, 'PARTNERSHIP_INFORMATION_RECEIVED', '{}'::jsonb, 'ANSWER:' || r.id);
    END IF;
    RETURN v_to;
END $$;

-- a reviewer asked: an office holding REVIEW_PARTNERSHIP (a Dean for a faculty, a Head for a department), or a named person
CREATE FUNCTION partnership.add_reviewer(p_id uuid, p_office text, p_scope text, p_person uuid, p_role text, p_due date, p_confidential boolean)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; p partnership.proposal; v_scope text := nullif(upper(btrim(coalesce(p_scope, ''))), '');
BEGIN
    PERFORM partnership.require('ASSIGN_PARTNERSHIP');
    PERFORM partnership.require_see(p_id);
    SELECT * INTO p FROM partnership.proposal WHERE id = p_id;
    IF partnership.terminal(p.status) THEN RAISE EXCEPTION 'PTN_STATUS: % is closed', p.reference USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM partnership.grant g WHERE g.office_code = p_office AND g.permission = 'REVIEW_PARTNERSHIP') THEN
        RAISE EXCEPTION 'PTN_REVIEWER: % does not review partnerships', coalesce(p_office, 'that office') USING ERRCODE = '23514';
    END IF;
    IF p_office = 'dean' AND (v_scope IS NULL OR NOT EXISTS (SELECT 1 FROM ref.faculty f WHERE f.code = v_scope)) THEN
        RAISE EXCEPTION 'PTN_REVIEWER: a Dean reviews for a faculty; name the faculty' USING ERRCODE = '23514';
    END IF;
    IF p_office = 'hod' AND (v_scope IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = v_scope)) THEN
        RAISE EXCEPTION 'PTN_REVIEWER: a Head reviews for a department; name the department' USING ERRCODE = '23514';
    END IF;
    IF p_office NOT IN ('dean', 'hod') THEN v_scope := NULL; END IF;
    IF p_person IS NOT NULL AND NOT EXISTS (SELECT 1 FROM iam.office_assignment x WHERE x.person_id = p_person AND x.office_code = p_office
                                              AND x.valid_from <= current_date AND (x.valid_to IS NULL OR x.valid_to >= current_date)) THEN
        RAISE EXCEPTION 'PTN_REVIEWER: the person named does not hold that office' USING ERRCODE = '23514';
    END IF;
    INSERT INTO partnership.reviewer (proposal_id, office_code, scope_code, person_id, role_label, due_on, see_confidential, assigned_by)
    VALUES (p_id, p_office, v_scope, p_person, nullif(btrim(coalesce(p_role, '')), ''),
            coalesce(p_due, partnership.add_working_days(partnership.today(), (SELECT review_days FROM partnership.setting WHERE id = 1))),
            coalesce(p_confidential, false), partnership.actor())
    RETURNING id INTO v_id;
    PERFORM partnership.log(p_id, 'REVIEWER_ASKED', NULL, NULL, (SELECT label FROM ref.office WHERE code = p_office) || coalesce(' (' || v_scope || ')', '')
        || coalesce(' — ' || helpdesk.person_name(p_person), '') || CASE WHEN p_confidential THEN ' — may read the confidential disclosure' ELSE '' END);
    IF p_person IS NOT NULL THEN
        PERFORM partnership.tell_person(p_person, p_id, 'PARTNERSHIP_REVIEW_REQUESTED', '{}'::jsonb, 'REVIEW:' || v_id);
    ELSE
        PERFORM partnership.tell_office(p_office, v_scope, p_id, 'PARTNERSHIP_REVIEW_REQUESTED', '{}'::jsonb, 'REVIEW:' || v_id);
    END IF;
    RETURN v_id;
END $$;
CREATE FUNCTION partnership.withdraw_reviewer(p_reviewer uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r partnership.reviewer;
BEGIN
    PERFORM partnership.require('ASSIGN_PARTNERSHIP');
    SELECT * INTO r FROM partnership.reviewer WHERE id = p_reviewer;
    IF r.id IS NULL THEN RAISE EXCEPTION 'PTN_NOT_FOUND: no such reviewer' USING ERRCODE = 'P0002'; END IF;
    PERFORM partnership.require_see(r.proposal_id);
    UPDATE partnership.reviewer SET withdrawn_at = now() WHERE id = p_reviewer AND withdrawn_at IS NULL;
    PERFORM partnership.log(r.proposal_id, 'REVIEWER_WITHDRAWN', NULL, NULL, (SELECT label FROM ref.office WHERE code = r.office_code) || coalesce(' (' || r.scope_code || ')', ''));
END $$;
-- the acting reviewer's recommendation: the request the actor answers for (named, or their office over their faculty/department)
CREATE FUNCTION partnership.review(p_id uuid, p_recommendation text, p_comment text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r partnership.reviewer;
BEGIN
    PERFORM partnership.require('REVIEW_PARTNERSHIP');
    PERFORM partnership.require_see(p_id);
    SELECT * INTO r FROM partnership.reviewer x
     WHERE x.proposal_id = p_id AND x.withdrawn_at IS NULL
       AND (x.person_id = partnership.actor()
            OR (x.person_id IS NULL AND x.office_code = partnership.actor_office()
                AND (x.scope_code IS NULL OR x.scope_code = ANY (partnership.office_scopes(partnership.actor(), partnership.actor_office())))))
     ORDER BY (x.completed_at IS NULL) DESC, x.assigned_at DESC LIMIT 1;
    IF r.id IS NULL THEN RAISE EXCEPTION 'PTN_NOT_REVIEWER: your office has not been asked to review this proposal' USING ERRCODE = '42501'; END IF;
    IF p_recommendation NOT IN ('SUPPORT', 'SUPPORT_WITH_CONDITIONS', 'DO_NOT_SUPPORT', 'NEED_MORE_INFORMATION') THEN
        RAISE EXCEPTION 'PTN_RECOMMENDATION: support, support with conditions, do not support or need more information' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_comment, ''))) < 5 THEN RAISE EXCEPTION 'PTN_REASON: write the review''s comment' USING ERRCODE = '23514'; END IF;
    UPDATE partnership.reviewer SET recommendation = p_recommendation, comment = btrim(p_comment), completed_by = partnership.actor(), completed_at = now() WHERE id = r.id;
    PERFORM partnership.log(p_id, 'REVIEWED', NULL, NULL, initcap(replace(lower(p_recommendation), '_', ' ')) || ' — ' || (SELECT label FROM ref.office WHERE code = r.office_code)
        || coalesce(' (' || r.scope_code || ')', ''));
    PERFORM partnership.tell_person((SELECT owner_person FROM partnership.proposal WHERE id = p_id), p_id, 'PARTNERSHIP_REVIEW_RECEIVED',
        jsonb_build_object('RECOMMENDATION', initcap(replace(lower(p_recommendation), '_', ' '))), 'REVIEWED:' || r.id);
    RETURN r.id;
END $$;

-- a note or a message: an internal note never leaves the University (a confidential one only for those allowed); a message to
-- the applicant is e-mailed and shown on their status page
CREATE FUNCTION partnership.note(p_id uuid, p_kind text, p_body text, p_confidential boolean) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_kind text := upper(btrim(coalesce(p_kind, '')));
BEGIN
    PERFORM partnership.require_see(p_id);
    IF v_kind = 'INTERNAL_NOTE' THEN
        IF NOT (partnership.may('REVIEW_PARTNERSHIP') OR partnership.may('SCREEN_PARTNERSHIP')) THEN PERFORM partnership.require('REVIEW_PARTNERSHIP'); END IF;
        IF coalesce(p_confidential, false) AND NOT partnership.may_confidential(p_id) THEN
            RAISE EXCEPTION 'PTN_NOT_PERMITTED: only those allowed to read the confidential disclosure write a confidential note' USING ERRCODE = '42501';
        END IF;
    ELSIF v_kind = 'APPLICANT_MESSAGE' THEN
        PERFORM partnership.require('REQUEST_INFORMATION');
        IF partnership.terminal((SELECT status FROM partnership.proposal WHERE id = p_id)) THEN
            RAISE EXCEPTION 'PTN_STATUS: the proposal is closed' USING ERRCODE = '23514';
        END IF;
    ELSE
        RAISE EXCEPTION 'PTN_NOTE: an internal note or a message to the applicant' USING ERRCODE = '23514';
    END IF;
    INSERT INTO partnership.message (proposal_id, kind, body, confidential, author_person, author_office)
    VALUES (p_id, v_kind, btrim(p_body), v_kind = 'INTERNAL_NOTE' AND coalesce(p_confidential, false), partnership.actor(), partnership.actor_office())
    RETURNING id INTO v_id;
    IF v_kind = 'APPLICANT_MESSAGE' THEN
        PERFORM partnership.log(p_id, 'MESSAGE_SENT', NULL, NULL, 'A message to the applicant', true);
        PERFORM partnership.tell_applicant(p_id, 'PARTNERSHIP_MESSAGE', jsonb_build_object('MESSAGE', btrim(p_body)), 'MSG:' || v_id);
    END IF;
    RETURN v_id;
END $$;

-- a due-diligence check marked
CREATE FUNCTION partnership.dd_set(p_id uuid, p_item text, p_status text, p_note text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM partnership.require('DUE_DILIGENCE');
    PERFORM partnership.require_see(p_id);
    IF partnership.terminal((SELECT status FROM partnership.proposal WHERE id = p_id)) THEN RAISE EXCEPTION 'PTN_STATUS: the proposal is closed' USING ERRCODE = '23514'; END IF;
    IF p_status NOT IN ('PENDING', 'SATISFACTORY', 'CONCERN', 'NOT_APPLICABLE') THEN RAISE EXCEPTION 'PTN_DD: pending, satisfactory, concern or not applicable' USING ERRCODE = '23514'; END IF;
    IF p_status = 'CONCERN' AND length(btrim(coalesce(p_note, ''))) < 5 THEN RAISE EXCEPTION 'PTN_REASON: say what the concern is' USING ERRCODE = '23514'; END IF;
    INSERT INTO partnership.due_diligence (proposal_id, item_code, status, note, checked_by, checked_office, checked_at)
    VALUES (p_id, p_item, p_status, nullif(btrim(coalesce(p_note, '')), ''), partnership.actor(), partnership.actor_office(), now())
    ON CONFLICT (proposal_id, item_code) DO UPDATE SET status = EXCLUDED.status, note = EXCLUDED.note, checked_by = EXCLUDED.checked_by,
        checked_office = EXCLUDED.checked_office, checked_at = EXCLUDED.checked_at;
    PERFORM partnership.log(p_id, 'DUE_DILIGENCE', NULL, NULL, (SELECT label FROM partnership.dd_item WHERE code = p_item) || ': ' || lower(replace(p_status, '_', ' '))
        || coalesce(' — ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
END $$;

-- ── 13 · agreements ─────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION partnership.agreement_create(p_id uuid, p_type text, p_other text, p_title text, p_parties text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p partnership.proposal; v_id uuid;
BEGIN
    PERFORM partnership.require('MANAGE_AGREEMENT');
    PERFORM partnership.require_see(p_id);
    SELECT * INTO p FROM partnership.proposal WHERE id = p_id FOR UPDATE;
    IF p.status NOT IN ('APPROVED_FOR_DEVELOPMENT', 'AGREEMENT_REVIEW', 'AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE') THEN
        RAISE EXCEPTION 'PTN_STATUS: an agreement is prepared once the Vice-Chancellor has approved the partnership for development' USING ERRCODE = '23514';
    END IF;
    IF p_type = 'OTHER' AND length(btrim(coalesce(p_other, ''))) < 3 THEN RAISE EXCEPTION 'PTN_AGREEMENT: name the kind of agreement' USING ERRCODE = '23514'; END IF;
    INSERT INTO partnership.agreement (proposal_id, reference, agreement_type, type_other, title, parties, created_by)
    VALUES (p_id, partnership.next_agreement_reference(), p_type, nullif(btrim(coalesce(p_other, '')), ''), btrim(p_title), btrim(p_parties), partnership.actor())
    RETURNING id INTO v_id;
    PERFORM partnership.ensure_reviewer(p_id, 'legal', 'Due diligence and agreements');
    IF p.status = 'APPROVED_FOR_DEVELOPMENT' THEN
        UPDATE partnership.proposal SET status = 'AGREEMENT_REVIEW', next_action = 'Agreement: legal review, approval, signing', updated_at = now() WHERE id = p_id;
    END IF;
    PERFORM partnership.log(p_id, 'AGREEMENT_CREATED', p.status, CASE WHEN p.status = 'APPROVED_FOR_DEVELOPMENT' THEN 'AGREEMENT_REVIEW' END,
        (SELECT reference FROM partnership.agreement WHERE id = v_id) || ': ' || btrim(p_title), p.status = 'APPROVED_FOR_DEVELOPMENT');
    PERFORM partnership.tell_office('legal', NULL, p_id, 'PARTNERSHIP_AGREEMENT_REQUIRED', jsonb_build_object('AGREEMENT', btrim(p_title)), 'AGR:' || v_id);
    RETURN v_id;
END $$;
-- SEND_TO_LEGAL, LEGAL_CLEAR {note}, LEGAL_RETURN {note}, APPROVE, EXECUTE {signedOn, effectiveOn, expiresOn, renewalOn},
-- UPDATE_DATES {expiresOn, renewalOn, note}, TERMINATE {note}, WITHDRAW {note}
CREATE FUNCTION partnership.agreement_act(p_agreement uuid, p_action text, p_data jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE g partnership.agreement; a text := upper(btrim(coalesce(p_action, ''))); d jsonb := coalesce(p_data, '{}'::jsonb); v_to text;
        v_note text := nullif(btrim(coalesce(d ->> 'note', '')), ''); v_status text;
BEGIN
    SELECT * INTO g FROM partnership.agreement WHERE id = p_agreement FOR UPDATE;
    IF g.id IS NULL THEN RAISE EXCEPTION 'PTN_NOT_FOUND: no such agreement' USING ERRCODE = 'P0002'; END IF;
    PERFORM partnership.require_see(g.proposal_id);
    CASE a
    WHEN 'SEND_TO_LEGAL' THEN
        PERFORM partnership.require('MANAGE_AGREEMENT');
        IF g.status <> 'DRAFT' THEN RAISE EXCEPTION 'PTN_AGREEMENT_STATUS: a draft goes to legal review' USING ERRCODE = '23514'; END IF;
        v_to := 'LEGAL_REVIEW';
        PERFORM partnership.tell_office('legal', NULL, g.proposal_id, 'PARTNERSHIP_AGREEMENT_REQUIRED', jsonb_build_object('AGREEMENT', g.title), 'AGRLEGAL:' || g.id || ':' || extract(epoch FROM now())::bigint);
    WHEN 'LEGAL_CLEAR', 'LEGAL_RETURN' THEN
        PERFORM partnership.require('MANAGE_AGREEMENT');
        IF partnership.actor_office() NOT IN ('legal', 'super') THEN
            RAISE EXCEPTION 'PTN_NOT_PERMITTED: the University Legal Officer reviews an agreement' USING ERRCODE = '42501';
        END IF;
        IF g.status <> 'LEGAL_REVIEW' THEN RAISE EXCEPTION 'PTN_AGREEMENT_STATUS: the agreement is not with legal review' USING ERRCODE = '23514'; END IF;
        IF v_note IS NULL OR length(v_note) < 5 THEN RAISE EXCEPTION 'PTN_REASON: write the legal review''s note' USING ERRCODE = '23514'; END IF;
        v_to := CASE a WHEN 'LEGAL_CLEAR' THEN 'APPROVAL' ELSE 'DRAFT' END;
        UPDATE partnership.agreement SET legal_note = v_note, legal_by = partnership.actor(), legal_at = now() WHERE id = g.id;
        IF a = 'LEGAL_CLEAR' THEN
            PERFORM partnership.tell_office('vc', NULL, g.proposal_id, 'PARTNERSHIP_APPROVAL_REQUIRED', jsonb_build_object('AGREEMENT', g.title), 'AGRVC:' || g.id);
        END IF;
    WHEN 'APPROVE' THEN
        PERFORM partnership.require('APPROVE_PARTNERSHIP');
        IF g.status <> 'APPROVAL' THEN RAISE EXCEPTION 'PTN_AGREEMENT_STATUS: the agreement is approved after legal review' USING ERRCODE = '23514'; END IF;
        v_to := 'SIGNING';
        UPDATE partnership.agreement SET approved_by = partnership.actor(), approved_office = partnership.actor_office(), approved_at = now() WHERE id = g.id;
    WHEN 'EXECUTE' THEN
        PERFORM partnership.require('MANAGE_AGREEMENT');
        IF g.status <> 'SIGNING' THEN RAISE EXCEPTION 'PTN_AGREEMENT_STATUS: an agreement is executed once approved and signed' USING ERRCODE = '23514'; END IF;
        IF NOT EXISTS (SELECT 1 FROM partnership.attachment x WHERE x.agreement_id = g.id AND x.kind = 'AGREEMENT') THEN
            RAISE EXCEPTION 'PTN_AGREEMENT_DOCUMENT: attach the signed agreement first' USING ERRCODE = '23514';
        END IF;
        IF nullif(d ->> 'signedOn', '') IS NULL OR nullif(d ->> 'effectiveOn', '') IS NULL THEN
            RAISE EXCEPTION 'PTN_AGREEMENT_DATES: give the date signed and the date it takes effect' USING ERRCODE = '23514';
        END IF;
        v_to := 'EXECUTED';
        UPDATE partnership.agreement SET signed_on = (d ->> 'signedOn')::date, effective_on = (d ->> 'effectiveOn')::date,
               expires_on = nullif(d ->> 'expiresOn', '')::date, renewal_on = nullif(d ->> 'renewalOn', '')::date,
               executed_by = partnership.actor(), executed_at = now() WHERE id = g.id;
        SELECT status INTO v_status FROM partnership.proposal WHERE id = g.proposal_id;
        IF v_status = 'AGREEMENT_REVIEW' THEN
            UPDATE partnership.proposal SET status = 'AGREEMENT_EXECUTED', next_action = 'Implement', updated_at = now() WHERE id = g.proposal_id;
            PERFORM partnership.log(g.proposal_id, 'AGREEMENT_EXECUTED', 'AGREEMENT_REVIEW', 'AGREEMENT_EXECUTED', g.reference || ': ' || g.title, true);
        END IF;
        PERFORM partnership.tell_applicant(g.proposal_id, 'PARTNERSHIP_AGREEMENT_EXECUTED', jsonb_build_object('AGREEMENT', g.title), 'AGREXEC:' || g.id);
    WHEN 'UPDATE_DATES' THEN
        PERFORM partnership.require('MANAGE_AGREEMENT');
        IF g.status NOT IN ('EXECUTED', 'EXPIRED') THEN RAISE EXCEPTION 'PTN_AGREEMENT_STATUS: the dates of an executed agreement are kept up to date' USING ERRCODE = '23514'; END IF;
        IF v_note IS NULL OR length(v_note) < 5 THEN RAISE EXCEPTION 'PTN_REASON: say why the dates change (a renewal signed, a correction)' USING ERRCODE = '23514'; END IF;
        v_to := CASE WHEN nullif(d ->> 'expiresOn', '')::date IS NULL OR nullif(d ->> 'expiresOn', '')::date >= partnership.today() THEN 'EXECUTED' ELSE 'EXPIRED' END;
        UPDATE partnership.agreement SET expires_on = nullif(d ->> 'expiresOn', '')::date, renewal_on = nullif(d ->> 'renewalOn', '')::date WHERE id = g.id;
    WHEN 'TERMINATE', 'WITHDRAW' THEN
        PERFORM partnership.require('MANAGE_AGREEMENT');
        IF v_note IS NULL OR length(v_note) < 5 THEN RAISE EXCEPTION 'PTN_REASON: give the reason' USING ERRCODE = '23514'; END IF;
        IF a = 'TERMINATE' AND g.status <> 'EXECUTED' THEN RAISE EXCEPTION 'PTN_AGREEMENT_STATUS: an executed agreement is terminated; one in preparation is withdrawn' USING ERRCODE = '23514'; END IF;
        IF a = 'WITHDRAW' AND g.status NOT IN ('DRAFT', 'LEGAL_REVIEW', 'APPROVAL', 'SIGNING') THEN RAISE EXCEPTION 'PTN_AGREEMENT_STATUS: only an agreement in preparation is withdrawn' USING ERRCODE = '23514'; END IF;
        v_to := CASE a WHEN 'TERMINATE' THEN 'TERMINATED' ELSE 'WITHDRAWN' END;
        UPDATE partnership.agreement SET ended_note = v_note WHERE id = g.id;
    ELSE
        RAISE EXCEPTION 'PTN_ACTION: no such agreement action %', a USING ERRCODE = '23514';
    END CASE;
    UPDATE partnership.agreement SET status = v_to WHERE id = g.id;
    PERFORM partnership.log(g.proposal_id, 'AGREEMENT_' || a, g.status, v_to, g.reference || coalesce(': ' || v_note, ''));
    RETURN v_to;
END $$;
COMMENT ON FUNCTION partnership.agreement_act(uuid, text, jsonb) IS
  'V658: an agreement''s life — to the Legal Officer, cleared or returned with a note, approved by the Vice-Chancellor (or the DVC for the VC), executed with the signed copy and its dates, its dates kept up to date (never renewed by itself), terminated or withdrawn';

-- the agreements expiring within the alert window, the expired marked so: each told once to the owner and the Linkages office
CREATE FUNCTION partnership.agreement_alerts() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE g record; n integer := 0; v_days integer := (SELECT expiry_alert_days FROM partnership.setting WHERE id = 1);
BEGIN
    FOR g IN SELECT a.*, p.owner_person FROM partnership.agreement a JOIN partnership.proposal p ON p.id = a.proposal_id
              WHERE a.status = 'EXECUTED' AND a.expires_on IS NOT NULL AND a.expires_on <= partnership.today() + v_days LOOP
        IF g.expires_on < partnership.today() THEN
            UPDATE partnership.agreement SET status = 'EXPIRED' WHERE id = g.id;
            INSERT INTO partnership.event (proposal_id, actor, actor_office, action, from_status, to_status, detail)
            VALUES (g.proposal_id, NULL, NULL, 'AGREEMENT_EXPIRED', 'EXECUTED', 'EXPIRED', g.reference || ' expired on ' || to_char(g.expires_on, 'DD Mon YYYY'));
        END IF;
        n := n + partnership.tell_person(g.owner_person, g.proposal_id, 'PARTNERSHIP_EXPIRING',
                jsonb_build_object('AGREEMENT', g.title, 'EXPIRES', to_char(g.expires_on, 'DD Mon YYYY')),
                'EXPIRY:' || g.id || ':' || CASE WHEN g.expires_on < partnership.today() THEN 'EXPIRED' WHEN g.expires_on <= partnership.today() + 30 THEN '30' ELSE 'WINDOW' END)
           + partnership.tell_office('linkages', NULL, g.proposal_id, 'PARTNERSHIP_EXPIRING',
                jsonb_build_object('AGREEMENT', g.title, 'EXPIRES', to_char(g.expires_on, 'DD Mon YYYY')),
                'EXPIRY:' || g.id || ':' || CASE WHEN g.expires_on < partnership.today() THEN 'EXPIRED' WHEN g.expires_on <= partnership.today() + 30 THEN '30' ELSE 'WINDOW' END);
    END LOOP;
    RETURN n;
END $$;

-- ── 14 · the active partnership: activities, deliverables, reports, outcomes ────────────────────────────────────────────
CREATE FUNCTION partnership.activity_save(p_id uuid, p_activity uuid, p_kind text, p_title text, p_lead text, p_due date, p_status text, p_note text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := p_activity;
BEGIN
    PERFORM partnership.require('SCREEN_PARTNERSHIP');
    PERFORM partnership.require_see(p_id);
    IF (SELECT status FROM partnership.proposal WHERE id = p_id) NOT IN ('APPROVED_FOR_DEVELOPMENT', 'AGREEMENT_REVIEW', 'AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE') THEN
        RAISE EXCEPTION 'PTN_STATUS: activities are kept for an approved partnership' USING ERRCODE = '23514';
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO partnership.activity (proposal_id, kind, title, lead, due_on, status, note, done_on, created_by)
        VALUES (p_id, p_kind, btrim(p_title), nullif(btrim(coalesce(p_lead, '')), ''), p_due, coalesce(p_status, 'PLANNED'), nullif(btrim(coalesce(p_note, '')), ''),
                CASE WHEN p_status = 'DONE' THEN partnership.today() END, partnership.actor())
        RETURNING id INTO v_id;
    ELSE
        UPDATE partnership.activity SET kind = p_kind, title = btrim(p_title), lead = nullif(btrim(coalesce(p_lead, '')), ''), due_on = p_due,
               status = coalesce(p_status, status), note = nullif(btrim(coalesce(p_note, '')), ''),
               done_on = CASE WHEN p_status = 'DONE' THEN coalesce(done_on, partnership.today()) ELSE NULL END
         WHERE id = v_id AND proposal_id = p_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'PTN_NOT_FOUND: no such activity' USING ERRCODE = 'P0002'; END IF;
    END IF;
    PERFORM partnership.log(p_id, 'ACTIVITY', NULL, NULL, initcap(lower(p_kind)) || ': ' || btrim(p_title) || ' — ' || lower(replace(coalesce(p_status, 'PLANNED'), '_', ' ')));
    RETURN v_id;
END $$;
CREATE FUNCTION partnership.outcome_add(p_id uuid, p_kind text, p_description text, p_on date, p_quantity integer, p_amount numeric, p_currency text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    PERFORM partnership.require('SCREEN_PARTNERSHIP');
    PERFORM partnership.require_see(p_id);
    IF (SELECT status FROM partnership.proposal WHERE id = p_id) NOT IN ('AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE', 'CLOSED') THEN
        RAISE EXCEPTION 'PTN_STATUS: outcomes are recorded for a partnership under way' USING ERRCODE = '23514';
    END IF;
    IF p_amount IS NOT NULL AND p_currency IS NULL THEN RAISE EXCEPTION 'PTN_CURRENCY: give the currency of the amount' USING ERRCODE = '23514'; END IF;
    INSERT INTO partnership.outcome (proposal_id, kind, description, occurred_on, quantity, amount, currency, recorded_by)
    VALUES (p_id, p_kind, btrim(p_description), p_on, p_quantity, p_amount, nullif(upper(btrim(coalesce(p_currency, ''))), ''), partnership.actor())
    RETURNING id INTO v_id;
    PERFORM partnership.log(p_id, 'OUTCOME', NULL, NULL, (SELECT label FROM partnership.outcome_kind WHERE code = p_kind) || ': ' || btrim(p_description));
    RETURN v_id;
END $$;

-- ── 15 · a proposal the Linkages office records itself (a letter, an e-mail), and a correction of one ───────────────────
CREATE FUNCTION partnership.create_internal(p_answers jsonb, p_reason text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; p partnership.proposal; f record; r record; v_bad text;
BEGIN
    PERFORM partnership.require('CREATE_PARTNERSHIP');
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'PTN_REASON: say how the proposal came (a letter, an e-mail, a meeting)' USING ERRCODE = '23514'; END IF;
    INSERT INTO partnership.proposal (status, source, created_by) VALUES ('DRAFT', 'INTERNAL', partnership.actor()) RETURNING id INTO v_id;
    PERFORM partnership.save_answers(v_id, coalesce(p_answers, '{}'::jsonb));
    SELECT x.message INTO v_bad FROM partnership.problems(v_id) x WHERE x.step <= 3 OR x.field IN ('fundingStatus', 'international') LIMIT 1;
    IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'PTN_INVALID: %', v_bad USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM partnership.proposal WHERE id = v_id;
    SELECT * INTO f FROM partnership.flags_of(p);
    SELECT * INTO r FROM partnership.route_of(p);
    UPDATE partnership.proposal SET status = 'RECEIVED', reference = partnership.next_reference(), received_at = now(),
           flags = f.flags, compliance_review = f.compliance, risk_level = f.risk, desk_code = r.desk_code, routing_rule = r.rule_id,
           owner_person = (SELECT d.lead_person FROM partnership.desk d WHERE d.code = r.desk_code),
           owner_assigned_at = CASE WHEN (SELECT d.lead_person FROM partnership.desk d WHERE d.code = r.desk_code) IS NOT NULL THEN now() END,
           due_on = partnership.add_working_days(partnership.today(), (SELECT acknowledge_days FROM partnership.setting WHERE id = 1)),
           next_action = 'Initial screening', updated_at = now()
     WHERE id = v_id;
    PERFORM partnership.log(v_id, 'RECORDED', 'DRAFT', 'RECEIVED', 'Recorded by the Linkages office: ' || btrim(p_reason), false);
    PERFORM partnership.tell_desk(v_id, 'PARTNERSHIP_SUBMITTED', '{}'::jsonb, 'SUBMITTED');
    RETURN v_id;
END $$;
CREATE FUNCTION partnership.edit(p_id uuid, p_answers jsonb, p_reason text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p partnership.proposal; f record; v_keys text;
BEGIN
    PERFORM partnership.require('EDIT_PARTNERSHIP');
    PERFORM partnership.require_see(p_id);
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'PTN_REASON: say why the record is corrected' USING ERRCODE = '23514'; END IF;
    IF partnership.terminal((SELECT status FROM partnership.proposal WHERE id = p_id)) THEN RAISE EXCEPTION 'PTN_STATUS: the proposal is closed' USING ERRCODE = '23514'; END IF;
    -- the declarations are the applicant's own and are never edited
    PERFORM partnership.save_answers(p_id, coalesce(p_answers, '{}'::jsonb) - 'declaredAccurate' - 'declaredAuthorised' - 'declaredNoCommitment'
                                                                            - 'declaredPrivacy' - 'consentContact' - 'consentMarketing');
    SELECT * INTO p FROM partnership.proposal WHERE id = p_id;
    SELECT * INTO f FROM partnership.flags_of(p);
    UPDATE partnership.proposal SET flags = f.flags, compliance_review = f.compliance, risk_level = f.risk WHERE id = p_id;
    SELECT string_agg(k, ', ' ORDER BY k) INTO v_keys FROM jsonb_object_keys(coalesce(p_answers, '{}'::jsonb)) k;
    PERFORM partnership.log(p_id, 'EDITED', NULL, NULL, 'Corrected ' || coalesce(v_keys, 'nothing') || ': ' || btrim(p_reason));
END $$;

-- ── 16 · the settings and the configurable lists (MANAGE_PARTNERSHIP_SETTINGS) ──────────────────────────────────────────
CREATE FUNCTION partnership.set_settings(p jsonb, p_reason text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM partnership.require('MANAGE_PARTNERSHIP_SETTINGS');
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'PTN_REASON: say why the settings change' USING ERRCODE = '23514'; END IF;
    UPDATE partnership.setting s SET
        public_open = coalesce((p ->> 'publicOpen')::boolean, s.public_open),
        acknowledge_days = coalesce((p ->> 'acknowledgeDays')::int, s.acknowledge_days),
        screening_days = coalesce((p ->> 'screeningDays')::int, s.screening_days),
        review_days = coalesce((p ->> 'reviewDays')::int, s.review_days),
        complex_review_days = coalesce((p ->> 'complexReviewDays')::int, s.complex_review_days),
        info_days = coalesce((p ->> 'infoDays')::int, s.info_days),
        summary_max = coalesce((p ->> 'summaryMax')::int, s.summary_max),
        text_max = coalesce((p ->> 'textMax')::int, s.text_max),
        benefits_max = coalesce((p ->> 'benefitsMax')::int, s.benefits_max),
        max_files = coalesce((p ->> 'maxFiles')::int, s.max_files),
        max_file_mb = coalesce((p ->> 'maxFileMb')::int, s.max_file_mb),
        draft_days = coalesce((p ->> 'draftDays')::int, s.draft_days),
        expiry_alert_days = coalesce((p ->> 'expiryAlertDays')::int, s.expiry_alert_days),
        contact_email = CASE WHEN p ? 'contactEmail' THEN nullif(btrim(p ->> 'contactEmail'), '') ELSE s.contact_email END,
        contact_phone = CASE WHEN p ? 'contactPhone' THEN nullif(btrim(p ->> 'contactPhone'), '') ELSE s.contact_phone END,
        set_by = partnership.actor(), set_office = partnership.actor_office(), set_at = now(), reason = btrim(p_reason)
     WHERE s.id = 1;
EXCEPTION WHEN check_violation OR invalid_text_representation THEN
    RAISE EXCEPTION 'PTN_SETTING: a setting is outside what is allowed (%)', SQLERRM USING ERRCODE = '23514';
END $$;
CREATE FUNCTION partnership.set_category(p_code text, p_grp text, p_label text, p_sort integer, p_active boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM partnership.require('MANAGE_PARTNERSHIP_SETTINGS');
    INSERT INTO partnership.category (code, grp, label, sort, active)
    VALUES (upper(btrim(p_code)), p_grp, btrim(p_label), coalesce(p_sort, 100), coalesce(p_active, true))
    ON CONFLICT (code) DO UPDATE SET grp = EXCLUDED.grp, label = EXCLUDED.label, sort = EXCLUDED.sort, active = EXCLUDED.active;
END $$;
CREATE FUNCTION partnership.set_desk(p_code text, p_label text, p_lead uuid, p_active boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM partnership.require('MANAGE_PARTNERSHIP_SETTINGS');
    IF p_lead IS NOT NULL AND NOT EXISTS (SELECT 1 FROM iam.office_assignment x WHERE x.person_id = p_lead AND x.office_code = 'linkages'
                                            AND x.valid_from <= current_date AND (x.valid_to IS NULL OR x.valid_to >= current_date)) THEN
        RAISE EXCEPTION 'PTN_OWNER: a desk''s lead holds the Linkages & Partnerships office' USING ERRCODE = '23514';
    END IF;
    IF upper(btrim(p_code)) = 'GENERAL' AND NOT coalesce(p_active, true) THEN RAISE EXCEPTION 'PTN_DESK: the general desk stays open' USING ERRCODE = '23514'; END IF;
    INSERT INTO partnership.desk (code, label, lead_person, active) VALUES (upper(btrim(p_code)), btrim(p_label), p_lead, coalesce(p_active, true))
    ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, lead_person = EXCLUDED.lead_person, active = EXCLUDED.active;
END $$;
CREATE FUNCTION partnership.set_desk_officer(p_desk text, p_person uuid, p_active boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM partnership.require('MANAGE_PARTNERSHIP_SETTINGS');
    INSERT INTO partnership.desk_officer (desk_code, person_id, active, added_by) VALUES (p_desk, p_person, coalesce(p_active, true), partnership.actor())
    ON CONFLICT (desk_code, person_id) DO UPDATE SET active = EXCLUDED.active;
END $$;
CREATE FUNCTION partnership.set_rule(p_id uuid, p_priority integer, p_group text, p_category text, p_international boolean, p_org_type text,
                                     p_funding text, p_desk text, p_active boolean, p_note text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := p_id;
BEGIN
    PERFORM partnership.require('MANAGE_PARTNERSHIP_SETTINGS');
    IF v_id IS NULL THEN
        INSERT INTO partnership.routing_rule (priority, category_group, category, international, org_type, funding_status, desk_code, active, note)
        VALUES (p_priority, nullif(p_group, ''), nullif(p_category, ''), p_international, nullif(p_org_type, ''), nullif(p_funding, ''), p_desk, coalesce(p_active, true), p_note)
        RETURNING id INTO v_id;
    ELSE
        UPDATE partnership.routing_rule SET priority = p_priority, category_group = nullif(p_group, ''), category = nullif(p_category, ''),
               international = p_international, org_type = nullif(p_org_type, ''), funding_status = nullif(p_funding, ''), desk_code = p_desk,
               active = coalesce(p_active, true), note = p_note
         WHERE id = v_id;
    END IF;
    RETURN v_id;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'PTN_RULE: another rule has priority %', p_priority USING ERRCODE = '23514';
END $$;

-- ── 17 · the figures of the dashboard, over what the acting office sees ─────────────────────────────────────────────────
CREATE FUNCTION partnership.figures(p_person uuid, p_office text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH v AS (SELECT p.* FROM partnership.proposal p WHERE p.id IN (SELECT partnership.visible(p_person, p_office)))
    SELECT jsonb_build_object(
        'total', count(*),
        'new', count(*) FILTER (WHERE status = 'RECEIVED'),
        'screening', count(*) FILTER (WHERE status IN ('INITIAL_SCREENING', 'ROUTED', 'ASSIGNED')),
        'underReview', count(*) FILTER (WHERE status IN ('UNDER_REVIEW', 'MEETING_PROPOSED', 'UNDER_DEVELOPMENT')),
        'awaitingInformation', count(*) FILTER (WHERE status = 'AWAITING_INFORMATION'),
        'dueDiligence', count(*) FILTER (WHERE status = 'DUE_DILIGENCE'),
        'pendingApproval', count(*) FILTER (WHERE status = 'PENDING_APPROVAL'),
        'agreementReview', count(*) FILTER (WHERE status = 'AGREEMENT_REVIEW'),
        'active', count(*) FILTER (WHERE status IN ('AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE', 'APPROVED_FOR_DEVELOPMENT')),
        'declined', count(*) FILTER (WHERE status = 'DECLINED'),
        'closed', count(*) FILTER (WHERE status IN ('CLOSED', 'CANCELLED')),
        'overdue', count(*) FILTER (WHERE NOT partnership.terminal(status) AND status <> 'ACTIVE' AND due_on < partnership.today()),
        'complianceReview', count(*) FILTER (WHERE compliance_review AND NOT partnership.terminal(status)),
        'unassigned', count(*) FILTER (WHERE owner_person IS NULL AND NOT partnership.terminal(status)),
        'mine', count(*) FILTER (WHERE owner_person = p_person AND NOT partnership.terminal(status)),
        'expiring', (SELECT count(*) FROM partnership.agreement a WHERE a.proposal_id IN (SELECT id FROM v) AND a.status = 'EXECUTED'
                       AND a.expires_on <= partnership.today() + (SELECT expiry_alert_days FROM partnership.setting WHERE id = 1)),
        'myReviews', (SELECT count(*) FROM partnership.reviewer r WHERE r.proposal_id IN (SELECT id FROM v) AND r.withdrawn_at IS NULL AND r.completed_at IS NULL
                        AND (r.person_id = p_person OR (r.person_id IS NULL AND r.office_code = p_office
                                                        AND (r.scope_code IS NULL OR r.scope_code = ANY (partnership.office_scopes(p_person, p_office)))))))
      FROM v
$$;

-- ── 18 · the notices (the central engine's templates; the Directorate of ICT may reword them on Notice Templates) ────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PARTNERSHIP_RECEIVED', 'Partnership enquiry received', 'To the applicant, at once, when a collaboration enquiry is submitted on the public form',
 'Collaboration enquiry received — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nThank you. [UNIVERSITY_NAME] has received your collaboration enquiry.\n\nReference: [REFERENCE]\nTitle: [TITLE]\nOrganisation: [ORGANISATION]\nReceived: [RECEIVED]\n\nNext: the enquiry is screened and routed to the office or academic unit concerned. We aim to acknowledge complete enquiries within [ACK_DAYS] working days. Submitting an enquiry does not constitute acceptance of a partnership proposal or create a binding commitment with the University.\n\nFollow your enquiry, answer any request and add documents at this private link (keep it to yourself): [STATUS_URL]\n\nContact: [CONTACT_EMAIL]\nHow we use your information: [PRIVACY_URL]\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','TITLE','ORGANISATION','RECEIVED','ACK_DAYS','STATUS_URL','CONTACT_EMAIL','PRIVACY_URL'], true, 'NORMAL'),
('PARTNERSHIP_LINK', 'Partnership enquiry: a new private link', 'To the applicant who asks for the private link of their enquiry again (the earlier link stops working)',
 'Your private link — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nHere is a new private link to follow your collaboration enquiry [REFERENCE] ([TITLE]). The earlier link no longer works.\n\n[STATUS_URL]\n\nIf you did not ask for this, contact [CONTACT_EMAIL].\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','TITLE','STATUS_URL','CONTACT_EMAIL'], true, 'NORMAL'),
('PARTNERSHIP_SUBMITTED', 'Partnership: a new proposal', 'To the officers of the Linkages desk a new proposal is routed to (else the Linkages office)',
 'New collaboration proposal [REFERENCE] — [ORGANISATION]',
 E'A collaboration proposal has been received and routed to [DESK].\n\nReference: [REFERENCE]\nTitle: [TITLE]\nOrganisation: [ORGANISATION]\nCategory: [CATEGORY]\nReceived: [RECEIVED]\n\nOpen Partnerships on the portal to screen it.',
 NULL, 'New proposal [REFERENCE]', '[ORGANISATION]: [TITLE] — routed to [DESK].', ARRAY['REFERENCE','TITLE','ORGANISATION','CATEGORY','RECEIVED','DESK'], true, 'NORMAL'),
('PARTNERSHIP_ROUTED', 'Partnership: routed to a desk', 'To the officers of the desk a proposal is routed to',
 'Collaboration proposal [REFERENCE] routed to [DESK]',
 E'Proposal [REFERENCE] ([TITLE], [ORGANISATION]) has been routed to [DESK]. Open Partnerships on the portal to take it forward.',
 NULL, 'Routed to [DESK]: [REFERENCE]', '[ORGANISATION]: [TITLE].', ARRAY['REFERENCE','TITLE','ORGANISATION','DESK'], true, 'NORMAL'),
('PARTNERSHIP_ASSIGNED', 'Partnership: assigned to you', 'To the officer a proposal is assigned to as owner',
 'Collaboration proposal [REFERENCE] assigned to you',
 E'You are the owner of collaboration proposal [REFERENCE] ([TITLE], [ORGANISATION]). Open Partnerships on the portal to screen it.',
 NULL, 'Assigned to you: [REFERENCE]', '[ORGANISATION]: [TITLE].', ARRAY['REFERENCE','TITLE','ORGANISATION'], true, 'NORMAL'),
('PARTNERSHIP_INFORMATION_REQUESTED', 'Partnership enquiry: information requested', 'To the applicant when the University asks for more information or documents',
 'More information needed — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nTo take your collaboration enquiry [REFERENCE] ([TITLE]) forward, the University asks:\n\n[QUESTION]\n\nDocuments requested: [DOCUMENTS]\nPlease respond by: [DEADLINE]\n\nRespond and add documents from the private link in your acknowledgement e-mail (if you no longer have it, ask for a new one on the collaboration page with your reference and e-mail address).\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','TITLE','QUESTION','DOCUMENTS','DEADLINE'], true, 'NORMAL'),
('PARTNERSHIP_INFORMATION_RECEIVED', 'Partnership: the applicant answered', 'To the owner (else the desk) when the applicant answers a request',
 'Applicant answered — [REFERENCE]',
 E'The applicant has answered the request on collaboration proposal [REFERENCE] ([TITLE], [ORGANISATION]). Open Partnerships on the portal to read it.',
 NULL, 'Answer received: [REFERENCE]', 'The applicant answered the request.', ARRAY['REFERENCE','TITLE','ORGANISATION'], true, 'NORMAL'),
('PARTNERSHIP_MESSAGE', 'Partnership enquiry: a message', 'To the applicant when the University sends a message about their enquiry',
 'Message about your enquiry — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nA message from [UNIVERSITY_NAME] about your collaboration enquiry [REFERENCE] ([TITLE]):\n\n[MESSAGE]\n\nYou can reply from the private link in your acknowledgement e-mail.\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','TITLE','MESSAGE'], true, 'NORMAL'),
('PARTNERSHIP_REVIEW_STARTED', 'Partnership enquiry: under review', 'To the applicant when the enquiry is accepted for review',
 'Your enquiry is under review — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nYour collaboration enquiry [REFERENCE] ([TITLE]) has been accepted for review. Review is not a decision; the University will contact you about the next steps.\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','TITLE'], true, 'NORMAL'),
('PARTNERSHIP_REVIEW_REQUESTED', 'Partnership: your review is asked for', 'To an office (or person) asked to review a proposal',
 'Review asked: collaboration proposal [REFERENCE]',
 E'Your office is asked to review collaboration proposal [REFERENCE] ([TITLE], [ORGANISATION]). Open Partnerships on the portal to read it and record your recommendation.',
 NULL, 'Review asked: [REFERENCE]', '[ORGANISATION]: [TITLE].', ARRAY['REFERENCE','TITLE','ORGANISATION'], true, 'NORMAL'),
('PARTNERSHIP_REVIEW_RECEIVED', 'Partnership: a review recorded', 'To the owner when a reviewer records a recommendation',
 'Review recorded — [REFERENCE]',
 E'A review of collaboration proposal [REFERENCE] ([TITLE]) has been recorded: [RECOMMENDATION].',
 NULL, 'Review recorded: [REFERENCE]', '[RECOMMENDATION].', ARRAY['REFERENCE','TITLE','RECOMMENDATION'], true, 'NORMAL'),
('PARTNERSHIP_DUE_DILIGENCE_REQUIRED', 'Partnership: due diligence', 'To the owner and the Legal Officer when due diligence starts',
 'Due diligence — [REFERENCE]',
 E'Due diligence has started on collaboration proposal [REFERENCE] ([TITLE], [ORGANISATION]). Open Partnerships on the portal for the checklist.',
 NULL, 'Due diligence: [REFERENCE]', '[ORGANISATION]: [TITLE].', ARRAY['REFERENCE','TITLE','ORGANISATION'], true, 'NORMAL'),
('PARTNERSHIP_APPROVAL_REQUIRED', 'Partnership: approval required', 'To the Vice-Chancellor when a proposal (or an agreement) awaits approval',
 'Approval required — [REFERENCE]',
 E'Collaboration proposal [REFERENCE] ([TITLE], [ORGANISATION]) awaits your approval. Open Partnerships on the portal to decide.',
 NULL, 'Approval required: [REFERENCE]', '[ORGANISATION]: [TITLE].', ARRAY['REFERENCE','TITLE','ORGANISATION'], true, 'HIGH'),
('PARTNERSHIP_APPROVED', 'Partnership: approved for development', 'To the applicant and the owner when the Vice-Chancellor approves a proposal for development',
 'Approved for development — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nThe University has approved your collaboration proposal [REFERENCE] ([TITLE]) for development. The University will contact you about the agreement and next steps. Approval for development is not itself an agreement.\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, 'Approved: [REFERENCE]', '[TITLE] approved for development.', ARRAY['FIRST_NAME','REFERENCE','TITLE'], true, 'NORMAL'),
('PARTNERSHIP_DECLINED', 'Partnership enquiry: not taken forward', 'To the applicant when the proposal is declined',
 'Your collaboration enquiry — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nThank you for your collaboration enquiry [REFERENCE] ([TITLE]). [MESSAGE]\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','TITLE','MESSAGE'], true, 'NORMAL'),
('PARTNERSHIP_AGREEMENT_REQUIRED', 'Partnership: an agreement to review', 'To the University Legal Officer when an agreement is prepared or sent for legal review',
 'Agreement for review — [REFERENCE]',
 E'An agreement ([AGREEMENT]) of collaboration proposal [REFERENCE] ([ORGANISATION]) is prepared for legal review. Open Partnerships on the portal.',
 NULL, 'Agreement for review: [REFERENCE]', '[AGREEMENT] — [ORGANISATION].', ARRAY['REFERENCE','ORGANISATION','AGREEMENT'], true, 'NORMAL'),
('PARTNERSHIP_AGREEMENT_EXECUTED', 'Partnership: agreement executed', 'To the applicant when an agreement is executed',
 'Agreement executed — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nThe agreement "[AGREEMENT]" of your partnership with [UNIVERSITY_NAME] ([REFERENCE]) has been executed.\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','AGREEMENT'], true, 'NORMAL'),
('PARTNERSHIP_ACTIVE', 'Partnership: active', 'To the applicant when the partnership becomes active',
 'Partnership active — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nYour partnership with [UNIVERSITY_NAME] ([REFERENCE], [TITLE]) is now active.\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','TITLE'], true, 'NORMAL'),
('PARTNERSHIP_EXPIRING', 'Partnership: agreement expiring', 'To the owner and the Linkages office as an executed agreement nears or passes its expiry (never renewed automatically)',
 'Agreement expiring [EXPIRES] — [REFERENCE]',
 E'The agreement "[AGREEMENT]" of partnership [REFERENCE] ([ORGANISATION]) expires on [EXPIRES]. Decide whether to renew it; nothing is renewed automatically.',
 NULL, 'Agreement expiring: [REFERENCE]', '[AGREEMENT] expires [EXPIRES].', ARRAY['REFERENCE','ORGANISATION','AGREEMENT','EXPIRES'], true, 'HIGH'),
('PARTNERSHIP_CLOSED', 'Partnership enquiry: closed', 'To the applicant when the proposal or partnership is closed',
 'Closed — [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nYour collaboration [REFERENCE] ([TITLE]) has been closed. Thank you for your interest in [UNIVERSITY_NAME].\n\n[UNIVERSITY_SHORT] Directorate of Linkages & Partnerships',
 NULL, NULL, NULL, ARRAY['FIRST_NAME','REFERENCE','TITLE'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── 19 · the schema's grants (the API connects as the owner; the module roles read and write as elsewhere) ──────────────
GRANT USAGE ON SCHEMA partnership TO app_platform, app_iam, app_student, app_auditor;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA partnership TO app_platform;
GRANT SELECT ON ALL TABLES IN SCHEMA partnership TO app_auditor;

COMMIT;
