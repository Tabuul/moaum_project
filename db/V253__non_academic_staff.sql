-- ═══════════════════════════════════════════════════════════════════════════
-- V253 — non-academic staff: the unit register and the upload
--
--   The University's non-teaching staff belong to units the academic registers
--   do not hold — the Registry, the Bursary and its directorates and their
--   sub-units, the directorates, the divisions, the centres, the schools, the
--   College of Health Sciences' own offices and clinical departments. This is
--   that register: one row per unit with its kind, its parent and, for the
--   College, its college; and an alias table carrying every spelling the
--   nominal roll uses ("CHS-DEPT. OF SURGERY", "BUR-DIRECTORATE OF FAT-[CASH
--   OFFICE]", "DIRECTORATE OF HRM-SSE") so the sheet is loaded as it is. A
--   member of non-academic staff in an academic department or a faculty office
--   is placed against that department or faculty on the existing registers —
--   nothing is duplicated.
--
--   iam.import_staff takes the same sheet as the teaching-staff upload (PNO,
--   full names, sex, date of first appointment, department, present rank,
--   phone) with CONTISS in place of CONUASS. It makes the person and the
--   establishment record, placed in the unit, and issues no sign-in and no
--   office: a non-academic member of staff has no desk on the portal yet, and
--   a login with no office cannot act. A dry run resolves every row and
--   reports the spellings it cannot place, writing nothing.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'non-academic staff: the unit register (V253)', true);

-- ── the units ────────────────────────────────────────────────────────────────
CREATE TABLE ref.unit (
    code         text PRIMARY KEY,
    name         text NOT NULL,
    kind         text NOT NULL,
    parent_code  text NULL REFERENCES ref.unit(code),
    college_code text NULL REFERENCES ref.college(code),
    ended_on     date NULL,
    CONSTRAINT ck_unit_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
    CONSTRAINT ck_unit_kind CHECK (kind IN ('OFFICE','DIRECTORATE','DIVISION','UNIT','CENTRE','SCHOOL','FACULTY_OFFICE','DEPARTMENT')),
    CONSTRAINT ck_unit_name CHECK (btrim(name) <> '')
);
SELECT audit.attach('ref.unit');
COMMENT ON TABLE ref.unit IS 'The University''s non-academic units: offices, directorates, divisions, units, centres, schools, and the College''s own offices and clinical departments. A unit is ended, never deleted.';

INSERT INTO ref.unit (code, name, kind, parent_code, college_code) VALUES
    ('VC_OFFICE', 'Office of the Vice-Chancellor', 'OFFICE', NULL, NULL),
    ('DVC_ACADEMIC', 'Office of the Deputy Vice-Chancellor (Academic)', 'OFFICE', NULL, NULL),
    ('DVC_ADMIN', 'Office of the Deputy Vice-Chancellor (Administration)', 'OFFICE', NULL, NULL),
    ('REGISTRY', 'Office of the Registrar', 'OFFICE', NULL, NULL),
    ('BURSARY', 'Bursary Department', 'DIVISION', NULL, NULL),
    ('BUR_BAEC', 'Directorate of BAEC (Bursary)', 'DIRECTORATE', 'BURSARY', NULL),
    ('BUR_BAEC_CENTRAL_STORES', 'Central Stores (BAEC)', 'UNIT', 'BUR_BAEC', NULL),
    ('BUR_BAEC_CEFTER', 'CEFTER Accounts (BAEC)', 'UNIT', 'BUR_BAEC', NULL),
    ('BUR_BAEC_CEFTER_STORES', 'CEFTER Stores (BAEC)', 'UNIT', 'BUR_BAEC', NULL),
    ('BUR_BAEC_EXPENDITURE', 'Expenditure Control (BAEC)', 'UNIT', 'BUR_BAEC', NULL),
    ('BUR_BAEC_TETFUND', 'TETFund Accounts (BAEC)', 'UNIT', 'BUR_BAEC', NULL),
    ('BUR_FAAR', 'Directorate of FAAR (Bursary)', 'DIRECTORATE', 'BURSARY', NULL),
    ('BUR_FAT', 'Directorate of FAT (Bursary)', 'DIRECTORATE', 'BURSARY', NULL),
    ('BUR_FAT_CASH_OFFICE', 'Cash Office (FAT)', 'UNIT', 'BUR_FAT', NULL),
    ('BUR_FAT_PAYROLL', 'Payroll (FAT)', 'UNIT', 'BUR_FAT', NULL),
    ('BUR_FAT_STUDENTS_ACCOUNTS', 'Students'' Accounts (FAT)', 'UNIT', 'BUR_FAT', NULL),
    ('BUR_FAT_HEALTH_SERVICES', 'University Health Services Accounts (FAT)', 'UNIT', 'BUR_FAT', NULL),
    ('BUR_FAT_PG_ACCOUNTS', 'Postgraduate Accounts and Payroll (FAT)', 'UNIT', 'BUR_FAT', NULL),
    ('HRM', 'Directorate of Human Resource Management', 'DIRECTORATE', NULL, NULL),
    ('HRM_DIRECTOR', 'Director''s Office (HRM)', 'UNIT', 'HRM', NULL),
    ('HRM_SSE', 'Senior Staff Establishment (HRM)', 'UNIT', 'HRM', NULL),
    ('HRM_JSE', 'Junior Staff Establishment (HRM)', 'UNIT', 'HRM', NULL),
    ('HRM_STD', 'Staff Training and Development (HRM)', 'UNIT', 'HRM', NULL),
    ('HRM_UDU', 'HRM-UDU', 'UNIT', 'HRM', NULL),
    ('CAMA', 'Directorate of CAMA', 'DIRECTORATE', NULL, NULL),
    ('ACA', 'Directorate of ACA', 'DIRECTORATE', NULL, NULL),
    ('IPPR', 'Directorate of IPPR', 'DIRECTORATE', NULL, NULL),
    ('CALM', 'Directorate of CALM', 'DIRECTORATE', NULL, NULL),
    ('CALM_PENGRA', 'PENGRA (CALM)', 'UNIT', 'CALM', NULL),
    ('CALM_HWP', 'HWP (CALM)', 'UNIT', 'CALM', NULL),
    ('ICT', 'Directorate of ICT', 'DIRECTORATE', NULL, NULL),
    ('INTERNAL_AUDIT', 'Directorate of Internal Audit', 'DIRECTORATE', NULL, NULL),
    ('HEALTH_SERVICES', 'Directorate of University Health Services', 'DIRECTORATE', NULL, NULL),
    ('PHYSICAL_PLANNING', 'Directorate of Physical Planning', 'DIRECTORATE', NULL, NULL),
    ('APQA', 'Directorate of Academic Planning and Quality Assurance', 'DIRECTORATE', NULL, NULL),
    ('GST', 'Directorate of General Studies (GST)', 'DIRECTORATE', NULL, NULL),
    ('LIBRARY', 'University Library and Information Services', 'DIVISION', NULL, NULL),
    ('STUDENT_AFFAIRS', 'Student Affairs Division', 'DIVISION', NULL, NULL),
    ('PG_SCHOOL', 'Postgraduate School', 'SCHOOL', NULL, NULL),
    ('PROCUREMENT', 'Procurement Unit', 'UNIT', NULL, NULL),
    ('SECURITY', 'Security Unit', 'UNIT', NULL, NULL),
    ('TRANSPORT', 'Transport Unit', 'UNIT', NULL, NULL),
    ('CATERING', 'Catering Unit', 'UNIT', NULL, NULL),
    ('SPORTS', 'Sports Unit', 'UNIT', NULL, NULL),
    ('MAINTENANCE', 'Maintenance Services Unit', 'UNIT', NULL, NULL),
    ('CAREER_SERVICES', 'Career Services Unit', 'UNIT', NULL, NULL),
    ('SIWES_UNIT', 'SIWES Unit', 'UNIT', NULL, NULL),
    ('SANDWICH_OFFICE', 'Sandwich Programme Office', 'OFFICE', NULL, NULL),
    ('PRELIM_SCIENCE', 'Preliminary Science Office', 'OFFICE', NULL, NULL),
    ('PRELIM_VTE', 'Preliminary Vocational and Technical Education', 'OFFICE', NULL, NULL),
    ('UNIPOD', 'UNIPOD', 'UNIT', NULL, NULL),
    ('JUPEB', 'JUPEB Office', 'OFFICE', NULL, NULL),
    ('TTO', 'Technology Transfer Office (Centre for Entrepreneurship Studies)', 'OFFICE', NULL, NULL),
    ('CEID', 'Centre for Entrepreneurship and Innovation Development (CEID)', 'CENTRE', NULL, NULL),
    ('CRM', 'Centre for Research Management', 'CENTRE', NULL, NULL),
    ('CCE', 'Centre for Continuing Education', 'CENTRE', NULL, NULL),
    ('CODL', 'Centre for Open and Distance Learning', 'CENTRE', NULL, NULL),
    ('CCHD', 'Centre for Counselling and Human Development', 'CENTRE', NULL, NULL),
    ('CADL', 'Centre for Advancement, Development and Linkages', 'CENTRE', NULL, NULL),
    ('CEFTER', 'CEFTER', 'CENTRE', NULL, NULL),
    ('STAFF_SCHOOL', 'BSU Staff School', 'SCHOOL', NULL, NULL),
    ('STC', 'BSU Science and Technical College', 'SCHOOL', NULL, NULL),
    ('CHS_PROVOST', 'Provost''s Office', 'OFFICE', NULL, 'CHS'),
    ('CHS_DEPUTY_PROVOST', 'Deputy Provost''s Office', 'OFFICE', NULL, 'CHS'),
    ('CHS_SECRETARY', 'College Secretary''s Office (Central Administration)', 'OFFICE', NULL, 'CHS'),
    ('CHS_FINANCE', 'Finance and Accounts Department', 'DIVISION', NULL, 'CHS'),
    ('CHS_FINANCE_STORES', 'Stores (Finance and Accounts)', 'UNIT', 'CHS_FINANCE', 'CHS'),
    ('CHS_PROCUREMENT', 'Procurement Unit', 'UNIT', NULL, 'CHS'),
    ('CHS_INTERNAL_AUDIT', 'Internal Audit', 'UNIT', NULL, 'CHS'),
    ('CHS_ESTABLISHMENT', 'Establishment Unit', 'UNIT', NULL, 'CHS'),
    ('CHS_STUDENT_AFFAIRS', 'Student Affairs Unit', 'UNIT', NULL, 'CHS'),
    ('CHS_MEDICAL_LIBRARY', 'Medical Library', 'UNIT', NULL, 'CHS'),
    ('CHS_WORKS', 'Works and Maintenance Services Unit', 'UNIT', NULL, 'CHS'),
    ('CHS_TRANSPORT', 'Transport Unit', 'UNIT', NULL, 'CHS'),
    ('CHS_SECURITY', 'Security Unit', 'UNIT', NULL, 'CHS'),
    ('CHS_ANIMAL_HOUSE', 'Animal House Unit', 'UNIT', NULL, 'CHS'),
    ('CHS_FBCS', 'Faculty of Basic Clinical Sciences', 'FACULTY_OFFICE', NULL, 'CHS'),
    ('CHS_FCS', 'Faculty of Clinical Sciences', 'FACULTY_OFFICE', NULL, 'CHS'),
    ('CHS_SURGERY', 'Department of Surgery', 'DEPARTMENT', 'CHS_FBCS', 'CHS'),
    ('CHS_MEDICINE', 'Department of Medicine', 'DEPARTMENT', NULL, 'CHS'),
    ('CHS_PAEDIATRICS', 'Department of Paediatrics', 'DEPARTMENT', NULL, 'CHS'),
    ('CHS_OPHTHALMOLOGY', 'Department of Ophthalmology', 'DEPARTMENT', NULL, 'CHS'),
    ('CHS_CHEMICAL_PATHOLOGY', 'Department of Chemical Pathology', 'DEPARTMENT', NULL, 'CHS'),
    ('CHS_HAEMATOLOGY', 'Department of Haematology', 'DEPARTMENT', NULL, 'CHS'),
    ('CHS_HISTOPATHOLOGY', 'Department of Histopathology (Anatomical Pathology)', 'DEPARTMENT', NULL, 'CHS'),
    ('CHS_MEDICAL_MICROBIOLOGY', 'Department of Medical Microbiology and Parasitology', 'DEPARTMENT', NULL, 'CHS'),
    ('CHS_PHARMACOLOGY', 'Department of Pharmacology and Therapeutics', 'DEPARTMENT', NULL, 'CHS');

-- ── the spellings: each resolves to a unit, an academic department, or a faculty ──
CREATE TABLE ref.unit_alias (
    alias_key    text PRIMARY KEY,
    alias        text NOT NULL,
    unit_code    text NULL REFERENCES ref.unit(code),
    dept_code    text NULL REFERENCES ref.department(code),
    faculty_code text NULL REFERENCES ref.faculty(code),
    CONSTRAINT ck_unit_alias_one CHECK ((unit_code IS NOT NULL)::int + (dept_code IS NOT NULL)::int + (faculty_code IS NOT NULL)::int = 1)
);
SELECT audit.attach('ref.unit_alias');
COMMENT ON TABLE ref.unit_alias IS 'A spelling the nominal roll uses for a unit, keyed on its letters and digits alone, and where it belongs.';

-- letters and digits only, upper case, & as AND, DEPT. as DEPARTMENT
CREATE OR REPLACE FUNCTION ref.unit_key(p text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT regexp_replace(regexp_replace(replace(upper(coalesce(p, '')), '&', ' AND '), '\mDEPT\.?\s', 'DEPARTMENT ', 'g'), '[^A-Z0-9]', '', 'g')
$$;

INSERT INTO ref.unit_alias (alias_key, alias, unit_code, dept_code, faculty_code) VALUES
    ('AGRICTECHNOLOGYANDCONSUMERSCIENCE', 'AGRIC TECHNOLOGY & CONSUMER SCIENCE', NULL, 'ATC', NULL),
    ('BSUSCIENCEANDTECHNICALCOLLEGE', 'BSU SCIENCE & TECHNICAL COLLEGE', 'STC', NULL, NULL),
    ('BSUSTAFFSCHOOL', 'BSU STAFF SCHOOL', 'STAFF_SCHOOL', NULL, NULL),
    ('BURDIRECTORATEOFBAEC', 'BUR-DIRECTORATE OF BAEC', 'BUR_BAEC', NULL, NULL),
    ('BURDIRECTORATEOFBAECCENTRALSTORES', 'BUR-DIRECTORATE OF BAEC-CENTRAL STORES', 'BUR_BAEC_CENTRAL_STORES', NULL, NULL),
    ('BURDIRECTORATEOFBAECCEFTERSTORES', 'BUR-DIRECTORATE OF BAEC-[CEFTER STORES]', 'BUR_BAEC_CEFTER_STORES', NULL, NULL),
    ('BURDIRECTORATEOFBAECCEFTER', 'BUR-DIRECTORATE OF BAEC-[CEFTER]', 'BUR_BAEC_CEFTER', NULL, NULL),
    ('BURDIRECTORATEOFBAECCENTRALSTORES', 'BUR-DIRECTORATE OF BAEC-[CENTRAL STORES]', 'BUR_BAEC_CENTRAL_STORES', NULL, NULL),
    ('BURDIRECTORATEOFBAECEXPENDITURECONTROL', 'BUR-DIRECTORATE OF BAEC-[EXPENDITURE CONTROL]', 'BUR_BAEC_EXPENDITURE', NULL, NULL),
    ('BURDIRECTORATEOFBAECTETFUND', 'BUR-DIRECTORATE OF BAEC-[TETFUND]', 'BUR_BAEC_TETFUND', NULL, NULL),
    ('BURDIRECTORATEOFFAAR', 'BUR-DIRECTORATE OF FAAR', 'BUR_FAAR', NULL, NULL),
    ('BURDIRECTORATEOFFAT', 'BUR-DIRECTORATE OF FAT', 'BUR_FAT', NULL, NULL),
    ('BURDIRECTORATEOFFATCASHOFFICE', 'BUR-DIRECTORATE OF FAT-[CASH OFFICE]', 'BUR_FAT_CASH_OFFICE', NULL, NULL),
    ('BURDIRECTORATEOFFATPAYROLL', 'BUR-DIRECTORATE OF FAT-[PAYROLL]', 'BUR_FAT_PAYROLL', NULL, NULL),
    ('BURDIRECTORATEOFFATSTUDENTSACCOUNTS', 'BUR-DIRECTORATE OF FAT-[STUDENTS ACCOUNTS]', 'BUR_FAT_STUDENTS_ACCOUNTS', NULL, NULL),
    ('BURDIRECTORATEOFFATUNIHEALTHSERVICES', 'BUR-DIRECTORATE OF FAT-[UNI.HEALTH SERVICES]', 'BUR_FAT_HEALTH_SERVICES', NULL, NULL),
    ('BURSARYDEPARTMENT', 'BURSARY DEPARTMENT', 'BURSARY', NULL, NULL),
    ('CAREERSERVICEUNIT', 'CAREER SERVICE UNIT', 'CAREER_SERVICES', NULL, NULL),
    ('CATERINGUNIT', 'CATERING UNIT', 'CATERING', NULL, NULL),
    ('CEFTER', 'CEFTER', 'CEFTER', NULL, NULL),
    ('CEFTER', 'CEFTER-???', 'CEFTER', NULL, NULL),
    ('CENTREFORADVANCEMENTDEVELOPMENTANDLINKAGES', 'CENTRE FOR ADVANCEMENT, DEVELOPMENT AND LINKAGES', 'CADL', NULL, NULL),
    ('CENTREFORCONSERVATIONSCIENCEANDPRACTICECCSP', 'CENTRE FOR CONSERVATION SCIENCE AND PRACTICE (CCSP)', NULL, 'CSP', NULL),
    ('CENTREFORCONTINUINGEDUCATION', 'CENTRE FOR CONTINUING EDUCATION', 'CCE', NULL, NULL),
    ('CENTREFORCOUNSELLINGANDHUMANDEVELOPMENT', 'CENTRE FOR COUNSELLING AND HUMAN DEVELOPMENT', 'CCHD', NULL, NULL),
    ('CENTREFORENTREPRENEURSHIPANDINNOVATIONDEVELOPMENTCEID', 'CENTRE FOR ENTREPRENEURSHIP AND INNOVATION DEVELOPMENT (CEID)', 'CEID', NULL, NULL),
    ('CENTREFORGENDERSTUDIES', 'CENTRE FOR GENDER STUDIES', NULL, 'GND', NULL),
    ('CENTREFOROPENANDDISTANCELEARNING', 'CENTRE FOR OPEN & DISTANCE LEARNING', 'CODL', NULL, NULL),
    ('CENTREFORPEACEANDDEVELOPMENTSTUDIES', 'CENTRE FOR PEACE AND DEVELOPMENT STUDIES', NULL, 'PDS', NULL),
    ('CENTREFORRESEARCHMANAGEMENT', 'CENTRE FOR RESEARCH MANAGEMENT', 'CRM', NULL, NULL),
    ('CHSANIMALHOUSEUNIT', 'CHS-ANIMAL HOUSE UNIT', 'CHS_ANIMAL_HOUSE', NULL, NULL),
    ('CHSCENTRALADMINCOLLEGESECRETARYSOFFICE', 'CHS-CENTRAL ADMIN-COLLEGE SECRETARY''S OFFICE', 'CHS_SECRETARY', NULL, NULL),
    ('CHSCENTRALADMINCOLLEGESECRETARYSOFFICE', 'CHS-CENTRAL ADMIN.-COLLEGE SECRETARY''S OFFICE', 'CHS_SECRETARY', NULL, NULL),
    ('CHSCOLLESECRETARYSOFFICE', 'CHS-COLLE SECRETARY''S OFFICE', 'CHS_SECRETARY', NULL, NULL),
    ('CHSDDEPARTMENTOFCHEMICALPATHOLOGY', 'CHS-DDEPARTMENT OF CHEMICAL PATHOLOGY', 'CHS_CHEMICAL_PATHOLOGY', NULL, NULL),
    ('CHSDEPARTMENTOFANATOMY', 'CHS-DEPARTMENT OF ANATOMY', NULL, 'ANT', NULL),
    ('CHSDEPARTMENTOFCHEMICALPATHOLOGY', 'CHS-DEPARTMENT OF CHEMICAL PATHOLOGY', 'CHS_CHEMICAL_PATHOLOGY', NULL, NULL),
    ('CHSDEPARTMENTOFEPIDEMOLOGYANDCOMMUNITYHEALTH', 'CHS-DEPARTMENT OF EPIDEMOLOGY & COMMUNITY HEALTH', NULL, 'EPI', NULL),
    ('CHSDEPARTMENTOFHAEMATOLOGY', 'CHS-DEPARTMENT OF HAEMATOLOGY', 'CHS_HAEMATOLOGY', NULL, NULL),
    ('CHSDEPARTMENTOFHISTOPATHOLOGYANATOMICALPATHOLOGY', 'CHS-DEPARTMENT OF HISTOPATHOLOGY (ANATOMICAL PATHOLOGY)', 'CHS_HISTOPATHOLOGY', NULL, NULL),
    ('CHSDEPARTMENTOFMEDICALBIOCHEMISTRY', 'CHS-DEPARTMENT OF MEDICAL BIOCHEMISTRY', NULL, 'BCH', NULL),
    ('CHSDEPARTMENTOFMEDICALMICROBIOLOGYANDPARASITOLOGY', 'CHS-DEPARTMENT OF MEDICAL MICROBIOLOGY AND PARASITOLOGY', 'CHS_MEDICAL_MICROBIOLOGY', NULL, NULL),
    ('CHSDEPARTMENTOFMEDICINE', 'CHS-DEPARTMENT OF MEDICINE', 'CHS_MEDICINE', NULL, NULL),
    ('CHSDEPARTMENTOFNURSINGSCIENCES', 'CHS-DEPARTMENT OF NURSING SCIENCES', NULL, 'NUR', NULL),
    ('CHSDEPARTMENTOFOBSTETRICSANDGYNAECOLOGY', 'CHS-DEPARTMENT OF OBSTETRICS & GYNAECOLOGY', NULL, 'OBG', NULL),
    ('CHSDEPARTMENTOFOBSTETRICSANDGYNECOLOGY', 'CHS-DEPARTMENT OF OBSTETRICS & GYNECOLOGY', NULL, 'OBG', NULL),
    ('CHSDEPARTMENTOFOPHTHAMLMOLOGY', 'CHS-DEPARTMENT OF OPHTHAMLMOLOGY', 'CHS_OPHTHALMOLOGY', NULL, NULL),
    ('CHSDEPARTMENTOFPAEDIATRICS', 'CHS-DEPARTMENT OF PAEDIATRICS', 'CHS_PAEDIATRICS', NULL, NULL),
    ('CHSDEPARTMENTOFPHARMACOLOGYANDTHERAPEUTICS', 'CHS-DEPARTMENT OF PHARMACOLOGY & THERAPEUTICS', 'CHS_PHARMACOLOGY', NULL, NULL),
    ('CHSDEPARTMENTOFPHYSIOLOGY', 'CHS-DEPARTMENT OF PHYSIOLOGY', NULL, 'PGY', NULL),
    ('CHSDEPARTMENTOFSURGERY', 'CHS-DEPARTMENT OF SURGERY', 'CHS_SURGERY', NULL, NULL),
    ('CHSDEPARTMETOFNURSINGSCIENCE', 'CHS-DEPARTMET OF NURSING SCIENCE', NULL, 'NUR', NULL),
    ('CHSDEPARTMENTOFANATOMY', 'CHS-DEPT. OF ANATOMY', NULL, 'ANT', NULL),
    ('CHSDEPARTMENTOFSURGERY', 'CHS-DEPT. OF SURGERY', 'CHS_SURGERY', NULL, NULL),
    ('CHSDEPUTYPROVOSTOFFICE', 'CHS-DEPUTY PROVOST OFFICE', 'CHS_DEPUTY_PROVOST', NULL, NULL),
    ('CHSESTABLISHMENTUNIT', 'CHS-ESTABLISHMENT UNIT', 'CHS_ESTABLISHMENT', NULL, NULL),
    ('CHSFACULTYOFBASICCLINICALSCIENCES', 'CHS-FACULTY OF BASIC CLINICAL SCIENCES', 'CHS_FBCS', NULL, NULL),
    ('CHSFACULTYOFBASICMEDICALSCIENCESBMS', 'CHS-FACULTY OF BASIC MEDICAL SCIENCES (BMS)', NULL, NULL, 'BAMS'),
    ('CHSFACULTYOFCLINICALSCIENCES', 'CHS-FACULTY OF CLINICAL SCIENCES', 'CHS_FCS', NULL, NULL),
    ('CHSFINANCEANDACCOUNTSDEPARTMENT', 'CHS-FINANCE AND ACCOUNTS DEPARTMENT', 'CHS_FINANCE', NULL, NULL),
    ('CHSFINANCEANDACCOUNTSDEPARTMENTSTORES', 'CHS-FINANCE AND ACCOUNTS DEPARTMENT-[STORES]', 'CHS_FINANCE_STORES', NULL, NULL),
    ('CHSINTERNALAUDIT', 'CHS-INTERNAL AUDIT', 'CHS_INTERNAL_AUDIT', NULL, NULL),
    ('CHSMEDICALLABORATORYSCIENCE', 'CHS-MEDICAL LABORATORY SCIENCE', NULL, 'MLS', NULL),
    ('CHSMEDICALLABORATORYSCIENCES', 'CHS-MEDICAL LABORATORY SCIENCES', NULL, 'MLS', NULL),
    ('CHSMEDICALLIBRARY', 'CHS-MEDICAL LIBRARY', 'CHS_MEDICAL_LIBRARY', NULL, NULL),
    ('CHSPROCUREMENTOFFICE', 'CHS-PROCUREMENT OFFICE', 'CHS_PROCUREMENT', NULL, NULL),
    ('CHSPROCUREMENTUNIT', 'CHS-PROCUREMENT UNIT', 'CHS_PROCUREMENT', NULL, NULL),
    ('CHSPROVOSTOFFICE', 'CHS-PROVOST OFFICE', 'CHS_PROVOST', NULL, NULL),
    ('CHSPROVOSTSOFFICE', 'CHS-PROVOST''S OFFICE', 'CHS_PROVOST', NULL, NULL),
    ('CHSSECURITYUNIT', 'CHS-SECURITY UNIT', 'CHS_SECURITY', NULL, NULL),
    ('CHSSTUDENTAFFAIRS', 'CHS-STUDENT AFFAIRS', 'CHS_STUDENT_AFFAIRS', NULL, NULL),
    ('CHSSTUDENTAFFAIRSUNIT', 'CHS-STUDENT AFFAIRS UNIT', 'CHS_STUDENT_AFFAIRS', NULL, NULL),
    ('CHSTRANSPORTUNIT', 'CHS-TRANSPORT UNIT', 'CHS_TRANSPORT', NULL, NULL),
    ('CHSWORKSANDMAINTENANCESERVICESUNIT', 'CHS-WORKS & MAINTENANCE SERVICES UNIT', 'CHS_WORKS', NULL, NULL),
    ('DEPARTMENTOFACCOUNTING', 'DEPARTMENT OF ACCOUNTING', NULL, 'ACC', NULL),
    ('DEPARTMENTOFAGRICULTURETECHNOLOGYANDCONSUMERSCIENCE', 'DEPARTMENT OF AGRICULTURE TECHNOLOGY & CONSUMER SCIENCE', NULL, 'ATC', NULL),
    ('DEPARTMENTOFARCHITECTURE', 'DEPARTMENT OF ARCHITECTURE', NULL, 'ARC', NULL),
    ('DEPARTMENTOFARTSANDSOCIALSCIENCEEDUCATION', 'DEPARTMENT OF ARTS AND SOCIAL SCIENCE EDUCATION', NULL, 'ASS', NULL),
    ('DEPARTMENTOFBIOLOGICALSCIENCES', 'DEPARTMENT OF BIOLOGICAL SCIENCES', NULL, 'BIO', NULL),
    ('DEPARTMENTOFBUSINESSADMINISTRATION', 'DEPARTMENT OF BUSINESS ADMINISTRATION', NULL, 'BSM', NULL),
    ('DEPARTMENTOFBUSINESSMANAGEMENT', 'DEPARTMENT OF BUSINESS MANAGEMENT', NULL, 'BSM', NULL),
    ('DEPARTMENTOFBUSINESSTECHANDENTREPREEDU', 'DEPARTMENT OF BUSINESS TECH AND ENTREPRE EDU', NULL, 'BTE', NULL),
    ('DEPARTMENTOFCHEMISTRY', 'DEPARTMENT OF CHEMISTRY', NULL, 'CHM', NULL),
    ('DEPARTMENTOFCOMMERCIALLAW', 'DEPARTMENT OF COMMERCIAL LAW', NULL, 'LAW', NULL),
    ('DEPARTMENTOFECONOMICS', 'DEPARTMENT OF ECONOMICS', NULL, 'ECO', NULL),
    ('DEPARTMENTOFEDUCATIONALFOUNDATIONS', 'DEPARTMENT OF EDUCATIONAL FOUNDATIONS', NULL, 'EDF', NULL),
    ('DEPARTMENTOFGEOGRAPHY', 'DEPARTMENT OF GEOGRAPHY', NULL, 'GEO', NULL),
    ('DEPARTMENTOFHISTORYANDSTRATEGICSTUDIES', 'DEPARTMENT OF HISTORY AND STRATEGIC STUDIES', NULL, 'HST', NULL),
    ('DEPARTMENTOFINDUSTRIALTECHNOLOGY', 'DEPARTMENT OF INDUSTRIAL TECHNOLOGY', NULL, 'IND', NULL),
    ('DEPARTMENTOFINTERNATIONALLAWANDJURISPRUDENCE', 'DEPARTMENT OF INTERNATIONAL LAW & JURISPRUDENCE', NULL, 'LAW', NULL),
    ('DEPARTMENTOFLANGUAGESANDLINGUISTICS', 'DEPARTMENT OF LANGUAGES & LINGUISTICS', NULL, 'LAN', NULL),
    ('DEPARTMENTOFLIBRARYANDINFORMATIONSCIENCE', 'DEPARTMENT OF LIBRARY AND INFORMATION SCIENCE', NULL, 'LIS', NULL),
    ('DEPARTMENTOFMASSCOMMUNICATION', 'DEPARTMENT OF MASS COMMUNICATION', NULL, 'MCM', NULL),
    ('DEPARTMENTOFMATHEMATICSCOMPUTERSCIENCE', 'DEPARTMENT OF MATHEMATICS/COMPUTER SCIENCE', NULL, 'MTC', NULL),
    ('DEPARTMENTOFPHILOSOPHY', 'DEPARTMENT OF PHILOSOPHY', NULL, 'PHL', NULL),
    ('DEPARTMENTOFPHYSICALEDUCATIONANDHUMANKINETICS', 'DEPARTMENT OF PHYSICAL EDUCATION & HUMAN KINETICS', NULL, 'HKH', NULL),
    ('DEPARTMENTOFPHYSICS', 'DEPARTMENT OF PHYSICS', NULL, 'PHY', NULL),
    ('DEPARTMENTOFPOLITICALSCIENCE', 'DEPARTMENT OF POLITICAL SCIENCE', NULL, 'POL', NULL),
    ('DEPARTMENTOFPSYCHOLOGY', 'DEPARTMENT OF PSYCHOLOGY', NULL, 'PSY', NULL),
    ('DEPARTMENTOFPUBLICADMINISTRATION', 'DEPARTMENT OF PUBLIC ADMINISTRATION', NULL, 'PUB', NULL),
    ('DEPARTMENTOFPUBLICLAW', 'DEPARTMENT OF PUBLIC LAW', NULL, 'LAW', NULL),
    ('DEPARTMENTOFRELIGIONANDCULTURALSTUDIES', 'DEPARTMENT OF RELIGION & CULTURAL STUDIES', NULL, 'RAC', NULL),
    ('DEPARTMENTOFSCIENCEANDMATHEMATICSEDUCATION', 'DEPARTMENT OF SCIENCE AND MATHEMATICS EDUCATION', NULL, 'SME', NULL),
    ('DEPARTMENTOFSOCIOLOGY', 'DEPARTMENT OF SOCIOLOGY', NULL, 'SOC', NULL),
    ('DEPARTMENTOFTHEATREARTS', 'DEPARTMENT OF THEATRE ARTS', NULL, 'THE', NULL),
    ('DEPARTMENTOFURBANANDREGIONALPLANNING', 'DEPARTMENT OF URBAN AND REGIONAL PLANNING', NULL, 'URP', NULL),
    ('DEPARTMENTOFMATHEMATICSCOMPUTERSCIENCE', 'DEPT. OF MATHEMATICS/COMPUTER SCIENCE', NULL, 'MTC', NULL),
    ('DEPARTMENTOFSCIENCEANDMATHEMATICSEDUCATION', 'DEPT. OF SCIENCE AND MATHEMATICS EDUCATION', NULL, 'SME', NULL),
    ('DIRECTORATEOFACA', 'DIRECTORATE OF ACA', 'ACA', NULL, NULL),
    ('DIRECTORATEOFACADEMICPLANNINGANDQUALITYASSURANCE', 'DIRECTORATE OF ACADEMIC PLANNING & QUALITY ASSURANCE', 'APQA', NULL, NULL),
    ('DIRECTORATEOFCALM', 'DIRECTORATE OF CALM', 'CALM', NULL, NULL),
    ('DIRECTORATEOFCALMHWP', 'DIRECTORATE OF CALM-HWP', 'CALM_HWP', NULL, NULL),
    ('DIRECTORATEOFCALMPENGRA', 'DIRECTORATE OF CALM-PENGRA', 'CALM_PENGRA', NULL, NULL),
    ('DIRECTORATEOFCAMA', 'DIRECTORATE OF CAMA', 'CAMA', NULL, NULL),
    ('DIRECTORATEOFFATPGACCOUNTPAYROL', 'DIRECTORATE OF FAT-[PG ACCOUNT/PAYROL]', 'BUR_FAT_PG_ACCOUNTS', NULL, NULL),
    ('DIRECTORATEOFGST', 'DIRECTORATE OF GST', 'GST', NULL, NULL),
    ('DIRECTORATEOFHRM', 'DIRECTORATE OF HRM', 'HRM', NULL, NULL),
    ('DIRECTORATEOFHRMDIRECTOR', 'DIRECTORATE OF HRM-DIRECTOR', 'HRM_DIRECTOR', NULL, NULL),
    ('DIRECTORATEOFHRMJSE', 'DIRECTORATE OF HRM-JSE', 'HRM_JSE', NULL, NULL),
    ('DIRECTORATEOFHRMSSE', 'DIRECTORATE OF HRM-SSE', 'HRM_SSE', NULL, NULL),
    ('DIRECTORATEOFHRMSTD', 'DIRECTORATE OF HRM-STD', 'HRM_STD', NULL, NULL),
    ('DIRECTORATEOFHRMUDU', 'DIRECTORATE OF HRM-UDU', 'HRM_UDU', NULL, NULL),
    ('DIRECTORATEOFICT', 'DIRECTORATE OF ICT', 'ICT', NULL, NULL),
    ('DIRECTORATEOFINTERNALAUDIT', 'DIRECTORATE OF INTERNAL AUDIT', 'INTERNAL_AUDIT', NULL, NULL),
    ('DIRECTORATEOFIPPR', 'DIRECTORATE OF IPPR', 'IPPR', NULL, NULL),
    ('DIRECTORATEOFPHYSICALPLANNING', 'DIRECTORATE OF PHYSICAL PLANNING', 'PHYSICAL_PLANNING', NULL, NULL),
    ('DIRECTORATEOFUNIVERSITYHEALTHSERVICES', 'DIRECTORATE OF UNIVERSITY HEALTH SERVICES', 'HEALTH_SERVICES', NULL, NULL),
    ('ENGLISHLANGUAGEANDLITERATURE', 'ENGLISH LANGUAGE AND LITERATURE', NULL, 'ENG', NULL),
    ('FACULTYOFADMINISTRATIONANDMANAGEMENT', 'FACULTY OF ADMINISTRATION AND MANAGEMENT', NULL, NULL, 'MS'),
    ('FACULTYOFARCHITECTURE', 'FACULTY OF ARCHITECTURE', NULL, NULL, 'AC'),
    ('FACULTYOFARTS', 'FACULTY OF ARTS', NULL, NULL, 'AR'),
    ('FACULTYOFCOMMUNICATIONANDMEDIASTUDIES', 'FACULTY OF COMMUNICATION AND MEDIA STUDIES', NULL, NULL, 'CM'),
    ('FACULTYOFEDUCATION', 'FACULTY OF EDUCATION', NULL, NULL, 'ED'),
    ('FACULTYOFENVIRONMENTALSCIENCES', 'FACULTY OF ENVIRONMENTAL SCIENCES', NULL, NULL, 'ES'),
    ('FACULTYOFLAW', 'FACULTY OF LAW', NULL, NULL, 'LW'),
    ('FACULTYOFMEDIAANDCOMMUNICATIONSTUDIES', 'FACULTY OF MEDIA AND COMMUNICATION STUDIES', NULL, NULL, 'CM'),
    ('FACULTYOFPHARMACEUTICALSCIENCES', 'FACULTY OF PHARMACEUTICAL SCIENCES', NULL, NULL, 'PS'),
    ('FACULTYOFSCIENCE', 'FACULTY OF SCIENCE', NULL, NULL, 'SC'),
    ('FACULTYOFSCIENCES', 'FACULTY OF SCIENCES', NULL, NULL, 'SC'),
    ('FACULTYOFSOCIALSCIENCE', 'FACULTY OF SOCIAL SCIENCE', NULL, NULL, 'SS'),
    ('FACULTYOFSOCIALSCIENCES', 'FACULTY OF SOCIAL SCIENCES', NULL, NULL, 'SS'),
    ('FACULTYOFTECHNOLOGYANDINDUSTRIALSTUDIES', 'FACULTY OF TECHNOLOGY AND INDUSTRIAL STUDIES', NULL, NULL, 'TI'),
    ('HISTORYANDSTRATEGICSTUDIES', 'HISTORY AND STRATEGIC STUDIES', NULL, 'HST', NULL),
    ('JUBEP', 'JUBEP', 'JUPEB', NULL, NULL),
    ('JUPEB', 'JUPEB', 'JUPEB', NULL, NULL),
    ('MAINTENANCESERVICESUNIT', 'MAINTENANCE SERVICES UNIT', 'MAINTENANCE', NULL, NULL),
    ('OFFICEOFTHEDVCADMIN', 'OFFICE OF THE DVC ADMIN', 'DVC_ADMIN', NULL, NULL),
    ('OFFICEOFTHEDVCACAD', 'OFFICE OF THE DVC-[ACAD]', 'DVC_ACADEMIC', NULL, NULL),
    ('OFFICEOFTHEDVCADMIN', 'OFFICE OF THE DVC-[ADMIN]', 'DVC_ADMIN', NULL, NULL),
    ('OFFICEOFTHEREGISTRAR', 'OFFICE OF THE REGISTRAR', 'REGISTRY', NULL, NULL),
    ('OFFICEOFTHEVICECHANCELLOR', 'OFFICE OF THE VICE-CHANCELLOR', 'VC_OFFICE', NULL, NULL),
    ('POSTGRADUATESCHOOL', 'POSTGRADUATE SCHOOL', 'PG_SCHOOL', NULL, NULL),
    ('PRELIMINARYSCIENCEOFFICE', 'PRELIMINARY SCIENCE OFFICE', 'PRELIM_SCIENCE', NULL, NULL),
    ('PRELIMINARYVOCATIONALANDTECHNICALEDUCATION', 'PRELIMINARY VOCATIONAL & TECHNICAL EDUCATION', 'PRELIM_VTE', NULL, NULL),
    ('PROCUREMENTUNIT', 'PROCUREMENT UNIT', 'PROCUREMENT', NULL, NULL),
    ('SANDWICHOFFICE', 'SANDWICH OFFICE', 'SANDWICH_OFFICE', NULL, NULL),
    ('SECURITYUNIT', 'SECURITY UNIT', 'SECURITY', NULL, NULL),
    ('SECURITYUNITCHS', 'SECURITY UNIT-CHS', 'CHS_SECURITY', NULL, NULL),
    ('SECURITYUNITCHSNOPR', 'SECURITY UNIT-CHS-NOPR', 'CHS_SECURITY', NULL, NULL),
    ('SIWES', 'SIWES', 'SIWES_UNIT', NULL, NULL),
    ('SPORTSUNIT', 'SPORTS UNIT', 'SPORTS', NULL, NULL),
    ('STUDENTAFFAIRSDIVISION', 'STUDENT AFFAIRS DIVISION', 'STUDENT_AFFAIRS', NULL, NULL),
    ('TECHNOLOGYTRANSFEROFFICECENTREOFFICEFORENTREPRENEURSHIPSTUDIES', 'TECHNOLOGY TRANSFER OFFICE [CENTRE OFFICE FOR ENTREPRENEURSHIP STUDIES]', 'TTO', NULL, NULL),
    ('TRANSPORTUNIT', 'TRANSPORT UNIT', 'TRANSPORT', NULL, NULL),
    ('UNIPOD', 'UNIPOD', 'UNIPOD', NULL, NULL),
    ('UNIVERSITYLIBRARYANDINFORMATIONSERVICES', 'UNIVERSITY LIBRARY & INFORMATION SERVICES', 'LIBRARY', NULL, NULL)
ON CONFLICT (alias_key) DO NOTHING;

-- where a spelling belongs: the alias table first; else a department or a faculty by name, tolerant of
-- case, spacing, & and the "DEPARTMENT OF" / "FACULTY OF" prefix; else a unit by name
CREATE OR REPLACE FUNCTION ref.resolve_unit(p_raw text)
RETURNS TABLE (unit_code text, dept_code text, faculty_code text)
LANGUAGE plpgsql STABLE AS $$
DECLARE k text := ref.unit_key(p_raw); bare text;
BEGIN
    IF k = '' THEN RETURN; END IF;
    RETURN QUERY SELECT a.unit_code, a.dept_code, a.faculty_code FROM ref.unit_alias a WHERE a.alias_key = k;
    IF FOUND THEN RETURN; END IF;
    bare := regexp_replace(k, '^(DEPARTMENTOF|FACULTYOF|CHSDEPARTMENTOF|CHSFACULTYOF)', '');
    RETURN QUERY SELECT NULL::text, d.code, NULL::text FROM ref.department d WHERE d.ended_on IS NULL AND (ref.unit_key(d.name) = bare OR upper(d.code) = k) LIMIT 1;
    IF FOUND THEN RETURN; END IF;
    RETURN QUERY SELECT NULL::text, NULL::text, f.code FROM ref.faculty f WHERE ref.unit_key(f.name) = bare OR upper(f.code) = k LIMIT 1;
    IF FOUND THEN RETURN; END IF;
    RETURN QUERY SELECT u.code, NULL::text, NULL::text FROM ref.unit u WHERE u.ended_on IS NULL AND (ref.unit_key(u.name) = k OR u.code = upper(btrim(p_raw))) LIMIT 1;
END $$;

-- ── the establishment record learns the category, the scale and the unit ────
ALTER TABLE hrm.staff_record
    ADD COLUMN IF NOT EXISTS category      text NULL,
    ADD COLUMN IF NOT EXISTS salary_scale  text NULL,
    ADD COLUMN IF NOT EXISTS contiss_step  int  NULL,
    ADD COLUMN IF NOT EXISTS home_unit     text NULL REFERENCES ref.unit(code),
    ADD COLUMN IF NOT EXISTS home_faculty  text NULL REFERENCES ref.faculty(code),
    ADD COLUMN IF NOT EXISTS unit_as_given text NULL;
ALTER TABLE hrm.staff_record DROP CONSTRAINT IF EXISTS ck_staffrec_category;
ALTER TABLE hrm.staff_record ADD CONSTRAINT ck_staffrec_category CHECK (category IS NULL OR category IN ('ACADEMIC','NON_ACADEMIC'));
ALTER TABLE hrm.staff_record DROP CONSTRAINT IF EXISTS ck_staffrec_scale;
ALTER TABLE hrm.staff_record ADD CONSTRAINT ck_staffrec_scale CHECK (salary_scale IS NULL OR salary_scale IN ('CONUASS','CONTISS','CONUNASS','CONMESS','CONHESS','CONSOLIDATED'));
COMMENT ON COLUMN hrm.staff_record.home_unit IS 'The non-academic unit the person belongs to (ref.unit); an academic department is home_department, a faculty office home_faculty.';
COMMENT ON COLUMN hrm.staff_record.unit_as_given IS 'The unit exactly as the nominal roll spelt it, kept beside the placement so a wrong placement can be traced.';

-- teaching staff already on record are academic
UPDATE hrm.staff_record SET category = 'ACADEMIC', salary_scale = coalesce(salary_scale, CASE WHEN conuass_step IS NOT NULL THEN 'CONUASS' END)
 WHERE category IS NULL AND home_department IS NOT NULL;

-- ── the upload ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iam.import_staff(p_rows jsonb, p_dry_run boolean DEFAULT false)
RETURNS TABLE (rows int, created int, existing int, records int, unplaced int, skipped int, first_error text, unplaced_units text)
LANGUAGE plpgsql AS $$
DECLARE
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    r jsonb;
    v_pno text; v_staff text; v_full text; v_clean text; v_parts text[];
    v_surname text; v_given text; v_sex text; v_rank text; v_phone text; v_email text;
    v_unitin text; v_unit text; v_dept text; v_fac text; v_date date; v_scale text; v_step int; v_stepin text; v_pid uuid;
    n int := 0; c_created int := 0; c_exist int := 0; c_rec int := 0; c_unplaced int := 0; c_skip int := 0;
    v_err text := NULL; v_missing text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'staff are loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows: PNO, full names, sex, date of first appointment, department or unit, present rank, phone, CONTISS' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_pno := regexp_replace(btrim(coalesce(r->>'pno', r->>'PNO', r->>'staff_number', r->>'staffNumber', '')), '[^0-9]', '', 'g');
        CONTINUE WHEN v_pno = '';
        v_full := btrim(coalesce(r->>'full_names', r->>'fullNames', r->>'name', r->>'names', ''));
        CONTINUE WHEN v_full = '' OR v_full ~* '^(full\s*names?|names?)$';
        n := n + 1;
        v_staff := 'P' || v_pno;

        v_clean := btrim(regexp_replace(v_full,
            '^((PROF|PROFESSOR|ASSOC|ASSOCIATE|DR|MR|MRS|MISS|MS|ENGR|ENGINEER|REV|REVD|REVEREND|BARR|ARC|ARCH|SIR|CHIEF|PASTOR|VEN|VENERABLE|ALHAJI|HAJIA|COMRADE)\.?\s+)+', '', 'i'));
        v_clean := btrim(regexp_replace(v_clean, '\s+', ' ', 'g'));
        IF v_clean = '' THEN v_clean := v_full; END IF;
        v_parts := string_to_array(v_clean, ' ');
        IF array_length(v_parts, 1) = 1 THEN
            v_surname := v_parts[1]; v_given := v_parts[1];
        ELSE
            -- as the teaching-staff upload reads it: the surname is the last word, the given names the rest
            v_surname := v_parts[array_upper(v_parts, 1)];
            v_given := array_to_string(v_parts[1:array_upper(v_parts, 1) - 1], ' ');
        END IF;

        v_unitin := btrim(coalesce(r->>'unit', r->>'department', r->>'dept', r->>'department_or_unit', ''));
        SELECT u.unit_code, u.dept_code, u.faculty_code INTO v_unit, v_dept, v_fac FROM ref.resolve_unit(v_unitin) u LIMIT 1;
        IF v_unit IS NULL AND v_dept IS NULL AND v_fac IS NULL THEN
            c_unplaced := c_unplaced + 1;
            IF v_unitin <> '' AND NOT (upper(v_unitin) = ANY(SELECT upper(x) FROM unnest(v_missing) x)) THEN v_missing := v_missing || v_unitin; END IF;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): no unit matching ' || coalesce(nullif(v_unitin, ''), '(blank)'); END IF;
            CONTINUE;
        END IF;

        v_sex := upper(left(nullif(btrim(coalesce(r->>'sex', '')), ''), 1));
        IF v_sex NOT IN ('M', 'F') THEN v_sex := NULL; END IF;
        v_rank := nullif(btrim(coalesce(r->>'rank', r->>'present_rank', r->>'presentRank', '')), '');
        v_phone := nullif(btrim(coalesce(r->>'phone', r->>'phone_no', r->>'phoneNo', '')), '');
        v_email := nullif(lower(btrim(coalesce(r->>'email', ''))), '');
        v_stepin := upper(btrim(coalesce(r->>'contiss', r->>'scale', r->>'grade', r->>'conuass', '')));
        v_scale := CASE WHEN v_stepin LIKE 'CONSOL%' THEN 'CONSOLIDATED' WHEN v_stepin LIKE 'CONUASS%' THEN 'CONUASS' WHEN v_stepin LIKE 'CONUNASS%' THEN 'CONUNASS'
                        WHEN v_stepin LIKE 'CONMESS%' THEN 'CONMESS' WHEN v_stepin LIKE 'CONHESS%' THEN 'CONHESS' WHEN v_stepin <> '' THEN 'CONTISS' END;
        v_step := nullif(regexp_replace(v_stepin, '[^0-9]', '', 'g'), '')::int;
        v_date := NULL;
        BEGIN
            v_date := to_date(nullif(btrim(coalesce(r->>'date_first_appointment', r->>'date_of_1st_appt', r->>'dateOf1stAppt', r->>'first_appointment', '')), ''), 'DD/MM/YYYY');
        EXCEPTION WHEN OTHERS THEN v_date := NULL; END;

        SELECT id INTO v_pid FROM iam.person WHERE staff_number = v_staff;
        IF v_pid IS NULL THEN c_created := c_created + 1; ELSE c_exist := c_exist + 1; END IF;
        c_rec := c_rec + 1;
        CONTINUE WHEN p_dry_run;

        BEGIN
            IF v_pid IS NULL THEN
                v_pid := gen_random_uuid();
                INSERT INTO iam.person (id, staff_number, surname, given_names, email, phone) VALUES (v_pid, v_staff, v_surname, v_given, v_email, v_phone);
            ELSE
                UPDATE iam.person SET email = coalesce(email, v_email), phone = coalesce(phone, v_phone) WHERE id = v_pid AND (email IS NULL OR phone IS NULL);
            END IF;
            INSERT INTO hrm.staff_record (person_id, pno, sex, date_first_appointment, present_rank, category, salary_scale, contiss_step, home_unit, home_department, home_faculty, unit_as_given)
            VALUES (v_pid, v_pno, v_sex, v_date, v_rank, 'NON_ACADEMIC', v_scale, CASE WHEN v_scale = 'CONSOLIDATED' THEN NULL ELSE v_step END, v_unit, v_dept, v_fac, v_unitin)
            ON CONFLICT (person_id) DO UPDATE SET
                pno = excluded.pno,
                sex = coalesce(excluded.sex, hrm.staff_record.sex),
                date_first_appointment = coalesce(excluded.date_first_appointment, hrm.staff_record.date_first_appointment),
                present_rank = coalesce(excluded.present_rank, hrm.staff_record.present_rank),
                category = coalesce(hrm.staff_record.category, 'NON_ACADEMIC'),
                salary_scale = coalesce(excluded.salary_scale, hrm.staff_record.salary_scale),
                contiss_step = coalesce(excluded.contiss_step, hrm.staff_record.contiss_step),
                home_unit = coalesce(excluded.home_unit, CASE WHEN excluded.home_department IS NULL AND excluded.home_faculty IS NULL THEN hrm.staff_record.home_unit END),
                home_department = coalesce(excluded.home_department, CASE WHEN excluded.home_unit IS NULL AND excluded.home_faculty IS NULL THEN hrm.staff_record.home_department END),
                home_faculty = coalesce(excluded.home_faculty, CASE WHEN excluded.home_unit IS NULL AND excluded.home_department IS NULL THEN hrm.staff_record.home_faculty END),
                unit_as_given = excluded.unit_as_given,
                updated_at = now();
        EXCEPTION WHEN OTHERS THEN
            c_skip := c_skip + 1; c_rec := c_rec - 1;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): ' || SQLERRM; END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, c_created, c_exist, c_rec, c_unplaced, c_skip, v_err, nullif(array_to_string(v_missing, ', '), '');
END $$;
COMMENT ON FUNCTION iam.import_staff(jsonb, boolean) IS
  'Loads non-academic staff from the nominal roll: person and establishment record, placed in a unit, department or faculty; no sign-in, no office. Per-row savepoints; idempotent; a dry run writes nothing.';

GRANT SELECT ON ref.unit, ref.unit_alias TO app_iam, app_student, app_admissions, app_registration, app_results, app_auditor;

COMMIT;
