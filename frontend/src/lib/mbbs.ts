/**
 * The MBBS programme of the College of Health Sciences as the CHS Prospectus 2023–2025 states it —
 * the extraction of 24 September 2026 (v2), pages 24–154. Everything here is the document's; where the
 * document is silent or contradicts itself, that is recorded too, not smoothed over. The College
 * overview and the College student's dashboard read this one file, so both say the same thing.
 */

export const MBBS = {
  degree: "MB.BS",
  minSemesters: { utme: 12, directEntry: 10 },
  minYears: { utme: 6, directEntry: 5 },
  minCreditUnits: 160,
  regulationsEffective: "29 September 2021",
  classification: "Unclassified. Distinction at 70% or more in a subject, shown on the certificate. MBBS Honours for at least one distinction in each of the four Professional examinations.",
  carryOver: "No carry-over except GST and EPS (entrepreneurship) courses; both must be passed before graduation.",
  governance: [
    "The College Academic Board is the highest academic body, subject to final approval by Senate; the Benue State Teaching Hospital is represented on it.",
    "100 Level results go from the Chief Examiner, through the Dean of Science, to the Provost. An examiners' meeting is held at the end of each session.",
  ],
  entry: {
    olevel: "Credit passes in five subjects — English, Mathematics, Physics, Chemistry, Biology — in no more than two sittings.",
    utme: "English, Physics, Biology and Chemistry, plus the University's cut-off and screening.",
    directEntry: "Three A'Level passes (at least 10 points) in Physics, Chemistry and Biology or Zoology in one sitting; or a Second Class Upper degree or better in a relevant science, plus the O'Level credits.",
    special: "Intra- or inter-university transfer with a CGPA of 3.50 or more.",
  },
} as const;

export type Phase = "PREMEDICAL" | "PRECLINICAL" | "CLINICAL";

export const PHASES: { phase: Phase; name: string; levels: number[]; how: string }[] = [
  { phase: "PREMEDICAL", name: "Pre-Medical", levels: [100], how: "Semester, credit-unit registration under the Faculty of Science. A fixed course list, each course tagged C (compulsory) or E (essential, GST); one credit unit is fifteen one-hour lectures or tutorials; each course examined at the end of its semester in a one- to three-hour paper marked out of 100 (CA 30, examination 70)." },
  { phase: "PRECLINICAL", name: "Pre-clinical", levels: [200, 300], how: "A fixed programme taught over three semesters — two of seventeen weeks at 200 Level and a twenty-week Third Semester at 300 Level. Every course compulsory, no electives; assessed by subject in the 200 Level Comprehensive Promotional Examination and then the 1st Professional examination. Credit units are not shown for these courses." },
  { phase: "CLINICAL", name: "Clinical", levels: [400, 500, 600], how: "Block and posting enrolment, not free course registration: Years 4, 5 and 6 begin after the 1st Professional is passed; clinical clerkship runs 152–156 weeks in all, split into Blocks, each subdivided into Junior and Senior Postings, with rotation groups where a department names them (Family Medicine A and B)." },
];

export const phaseOf = (level: number): Phase => (level <= 100 ? "PREMEDICAL" : level <= 300 ? "PRECLINICAL" : "CLINICAL");

export const SEMESTERS: { period: string; weeks: number; subjects: string }[] = [
  { period: "200 Level, semester 1", weeks: 17, subjects: "ANA 201/203/205, BCM 201/203/205, PHS 201/203/205/207" },
  { period: "200 Level, semester 2", weeks: 17, subjects: "ANA 202/204/206/208, BCM 202/204/206, PHS 202/204/206/208" },
  { period: "300 Level, the Third Semester", weeks: 20, subjects: "ANA 301/303/305, BCM 301/303/305, PHS 301/303/305/307" },
];

export interface Progression {
  from: number; to: string; exam: string; subjects: string; weights: string; pass: string; attendance: string; resit: string; onFailure: string;
}
export const PROGRESSION: Progression[] = [
  { from: 100, to: "200", exam: "100 Level sessional examinations", subjects: "C group: Mathematics 6, Physics 11, Chemistry 11, Biology 6 (34 CU). E group: GST (12 CU)", weights: "30 / 70",
    pass: "Pass all 46 CU, or all 34 C-group CU at 50% or more (GST carried over)", attendance: "Not stated", resit: "No",
    onFailure: "Advised to withdraw; may transfer within the University" },
  { from: 200, to: "300", exam: "Comprehensive Promotional Examination — essay, MCQ, practical; oral optional", subjects: "Anatomy, Biochemistry, Physiology (plus EPS)", weights: "30 / 70",
    pass: "50% or more per subject; the EPS pass mark is the Centre for Entrepreneurial Studies'", attendance: "75% in each activity and overall", resit: "No",
    onFailure: "Failing any subject means repeating 200 Level with fresh CA, a second and final attempt; failing again, advice to withdraw. A failed EPS course is carried over" },
  { from: 300, to: "400", exam: "1st Professional MBBS — essay, MCQ, practical, oral; external examiners", subjects: "Anatomy, Medical Biochemistry, Physiology", weights: "30 / 70 — the CA is the 300 Level comprehensive examination plus other tests",
    pass: "50% or more per subject", attendance: "75%", resit: "Yes, within three months, unless all three subjects are failed",
    onFailure: "Fail all three: repeat 300 Level. Fail one or two: resit with fresh CA; fail the resit: repeat 300 Level; fail after repeating: advised to withdraw" },
  { from: 400, to: "500", exam: "2nd Professional MBBS — essay, MCQ, practical, oral", subjects: "Pathology; Pharmacology & Therapeutics", weights: "30 / 70 (Pharmacology's own chapter says 50 / 50 — a conflict to resolve)",
    pass: "50% or more per subject", attendance: "70%", resit: "Yes, within three months, with fresh CA",
    onFailure: "Fail the resit: repeat the class with fresh 400 Level CA; fail after repeating: must withdraw" },
  { from: 500, to: "600", exam: "3rd Professional MBBS — essay, MCQ, clinical", subjects: "Paediatrics; Obstetrics & Gynaecology", weights: "30 / 70",
    pass: "50% or more per subject and 50% or more in the clinical component", attendance: "70%", resit: "Yes, within three months, with fresh CA",
    onFailure: "Fail the resit: repeat with fresh 500 Level CA; fail after repeating: must withdraw" },
  { from: 600, to: "Graduation", exam: "4th Professional (Final) MBBS — essay, MCQ, clinical", subjects: "Medicine (with Psychiatry and Family Medicine); Surgery (with Anaesthesia, Ophthalmology, ENT, Radiology); Community Medicine & Epidemiology", weights: "30 / 70",
    pass: "50% or more per subject and 50% or more in the clinical component", attendance: "Not stated in the regulations; Surgery requires 80%", resit: "Yes, within three months, with fresh CA",
    onFailure: "Fail the resit: repeat 600 Level; fail after repeating: advised to withdraw, with an appeal to Senate for a fourth and final attempt" },
];

export const COMMON_RULES = [
  "The resit window is three months from the release of results.",
  "A resit or repeat candidate earns fresh CA; the old CA is never overwritten.",
  "A student who withdraws may transfer to another programme of the University.",
];

export interface Posting { code: string; name: string; level: string; courses: string; weeks: string }
export interface Block { block: string; total: string; postings: Posting[]; note?: string }
export const BLOCKS: Block[] = [
  { block: "Internal Medicine", total: "34 weeks", postings: [
    { code: "M0", name: "Introduction to Clinical Medicine", level: "400", courses: "MED 401, MED 402", weeks: "2" },
    { code: "M1", name: "Junior Clerkship", level: "400", courses: "MED 403–409: Cardiology I, Respiratory I, GI I, Clinical Haematology, Metabolic & Endocrine, Neurology I, Nephrology I", weeks: "8" },
    { code: "M2", name: "Intermediate Clerkship", level: "500", courses: "MED 501–508: Cardiology II, Respiratory, GI II, Nephrology II, Rheumatology, Clinical Immunology, Tropical Medicine & Infections, Endocrine lectures", weeks: "8" },
    { code: "M3", name: "Senior Clerkship", level: "600", courses: "MED 601–604: Special Topics & Neurology II, Dermatovenereology, Medical Ethics & Jurisprudence, Traditional Medicine", weeks: "8" },
    { code: "Psychiatry", name: "Psychiatry posting", level: "600", courses: "MED 605 — the only posting with an hour-by-hour weekly timetable", weeks: "8" },
  ], note: "Teaching is formal lectures (about five per body system), tutorials, seminars and independent class projects." },
  { block: "Surgery", total: "Stated as 30 weeks; the phases add to 26, or 34 with the revision block", postings: [
    { code: "S0", name: "Introductory Clerkship", level: "400", courses: "SUG 401 Introduction to Clinical Surgery", weeks: "2" },
    { code: "S1", name: "Junior Surgery Posting", level: "400", courses: "SUG 402 Principles of Surgery; SUG 403 General Surgery", weeks: "8" },
    { code: "S2", name: "Intermediate — major sub-specialties", level: "500", courses: "SUG 501 Urology; 502 Burns & Plastics; 503 Orthopaedics; 504 Cardiothoracic; 505 Paediatric Surgery; 506 Neurosurgery; 507 Maxillofacial", weeks: "8" },
    { code: "S3", name: "Senior — minor sub-specialties", level: "600", courses: "SUG 601 ENT; SUG 602 Ophthalmology; SUG 605 Anaesthesia (SUG 603/604 not seen, possibly Radiology)", weeks: "8" },
    { code: "SUG 606", name: "Surgery Three revision", level: "600", courses: "Revision", weeks: "8" },
  ] },
  { block: "Paediatrics", total: "16 weeks at 500 Level", postings: [
    { code: "P1", name: "Junior Posting", level: "500", courses: "Lectures PAE 501–511: Introduction, Nutrition & Growth, Child Health & PHC, CVS/Respiratory, GU/GIT, Endocrine/Metabolic, CNS/Muscles/Bones, Blood, Infections & Genetics, Oncology, Neonatology", weeks: "8" },
    { code: "P2", name: "Senior Posting — clinical clerkship", level: "500", courses: "Seminars and clerkship; 7–14 days in the Newborn Unit", weeks: "8" },
  ] },
  { block: "Obstetrics & Gynaecology", total: "16 weeks at 500 Level", postings: [
    { code: "Posting I", name: "Junior", level: "500", courses: "OBG 501 Introductory Gynaecology; 502 Reproductive Physiology & Disorders of Pregnancy; 503 Labour, Puerperium & the Neonate; 504 Gynaecology Clinics", weeks: "8" },
    { code: "Posting II", name: "Senior", level: "500", courses: "OBG 505 Obstetrics Clinics; OBG 506 Special Topics & Clinics", weeks: "8" },
  ] },
  { block: "Pharmacology & Therapeutics", total: "Three 8-week postings; the 2nd Professional in Pharmacology falls 42–44 weeks after the clinical programme begins", postings: [
    { code: "PHT I", name: "First posting", level: "300, second semester", courses: "PHT 301 General Pharmacology & Pharmacokinetics (20 h, 2 CU); PHT 302 ANS Pharmacology with practical (30 h, 3 CU)", weeks: "8" },
    { code: "PHT II", name: "Second posting", level: "400", courses: "PHT 401 CVS Pharmacology; PHT 402 Systemic Pharmacology; PHT 403 Hormones & Endocrine (30 h, 3 CU each)", weeks: "8" },
    { code: "PHT III", name: "Senior posting", level: "400 or 500 — not stated", courses: "PHT 404 Chemotherapy; PHT 405 CNS Pharmacology; PHT 406 Drug Misuse & Toxicology (3 CU each)", weeks: "8" },
  ], note: "Eighteen laboratory practicals of three hours each, from Quantitative Drug Dilution to Rat Uterus Preparation." },
  { block: "Pathology disciplines", total: "Three 8-week postings each, 300–400 Level; 24 weeks a discipline", postings: [
    { code: "Chemical Pathology", name: "Postings I–III", level: "300–400", courses: "CPY 302, 304, 306 (300 Level); CPY 401, 402; CPY 403, 404", weeks: "8 each" },
    { code: "Haematology", name: "Postings I–III", level: "300–400", courses: "HAE 302 (300 Level); HAE 401, 402; HAE 403, 404 — taught during the first and second clinical years", weeks: "8 each" },
    { code: "Medical Microbiology", name: "Postings I–III", level: "300–400", courses: "Introductory concepts; systemic and pathogenesis; diagnosis, management and control", weeks: "8 each" },
    { code: "Anatomical Pathology", name: "Postings I–III", level: "300–400", courses: "PAT 302, 304; PAT 401, 403; PAT 402, 404 (Forensic)", weeks: "8 each" },
  ] },
  { block: "Family Medicine", total: "3 weeks", postings: [
    { code: "FAM I", name: "Posting I", level: "500", courses: "Groups A and B rotate through General Outpatient (adult, paediatric and adolescent, procedures and mini-theatre, injection room, wound dressing) and the special clinics (NHIS, Well Adult, Pain & Palliative, HAART)", weeks: "2" },
    { code: "FAM II", name: "Posting II", level: "600", courses: "The same clinics", weeks: "1" },
  ] },
  { block: "Community Medicine", total: "200–600 Level", postings: [
    { code: "COM", name: "COM 201–204, 301–304, 401–407, 501–510, 601–602", level: "200–600", courses: "COM 510 Field Activities — water and sewage plants, abattoirs and markets, remand and motherless-babies homes, public health laboratories, TB, endemic-disease and under-5 clinics, industries, international health organisations. COM 602 Community Diagnosis — the class maps a community, conducts a census, surveys facilities, identifies health problems, intervenes and reports", weeks: "—" },
  ] },
];

export const PSYCHIATRY_DAY: [string, string][] = [
  ["08:00–09:00", "Lecture"], ["10:00–12:00", "Ward-round teaching, clinic teaching or departmental academic seminar"],
  ["14:00–15:00", "Lecture"], ["15:00–16:00", "Seminar or bedside teaching"], ["17:00–20:00", "Teaching at call duty"],
];
export const PSYCHIATRY_WEEKS: [string, string][] = [
  ["1", "Introduction; history taking; aetiology and classification of mental disorders; psychopathology I–II"],
  ["2", "Psychopharmacology I–II; schizophrenia I–II"],
  ["3", "Alcohol and other substance disorders; organic mental disorders; delirium; Alzheimer's; somatoform"],
  ["4", "Mood, depressive and bipolar disorders; sleep disorders"],
  ["5", "Emergency psychiatry; anxiety; molecular biology; personality disorders"],
  ["6", "Transcultural and forensic psychiatry; childhood autism; mental retardation; sex and gender identity; HIV neuropsychiatry"],
  ["7", "Suicide; old-age psychiatry; mental health and PHC; PTSD; psychological therapy I–II"],
  ["8", "Uncommon disorders; postpartum disorders; revision; Friday: end-of-posting clinical examination, counted as CA"],
];

export const YEAR_VIEW: [string, string][] = [
  ["300", "Pre-clinical Third Semester (20 weeks). Pathology Posting I in each of the four disciplines and PHT I (8 weeks each; whether they run concurrently is not stated)."],
  ["400", "M0 (2) + M1 (8); S0 (2) + S1 (8); Pathology Postings II–III; PHT II (and PHT III?). 2nd Professional examination."],
  ["500", "M2 (8); S2 (8); Paediatrics P1 + P2 (16); O&G I + II (16); FAM I (2). 3rd Professional examination."],
  ["600", "M3 (8); Psychiatry (8); S3 (8) + SUG 606 revision (8); FAM II (1); COM 601–602. Final examination."],
];

export const ASSESSMENT_RULE = {
  general: "CA 30% and Professional examination 70% at every stage. Pass mark 50% or more per subject; for the clinical subjects of the 3rd and 4th examinations, 50% or more in the clinical component as well. Clinical CA is the supervisors' periodic evaluation plus end-of-posting examinations.",
};
export interface DeptCa { department: string; components: string; weight: string; exam: string }
export const DEPARTMENT_CA: DeptCa[] = [
  { department: "Paediatrics", components: "Continuous assessment of performance in all areas; junior end-of-posting MCQ at week 8; senior end-of-posting clinical (long and short case) and orals; at least six cases clerked per posting; the minimum procedures logbook; mandatory Wednesday Grand Round and Case Management Conferences.", weight: "30% of the overall evaluation; how the 30% splits is not stated", exam: "3rd Professional" },
  { department: "Pharmacology", components: "A series of course tests of about 32 MCQs, at least two essays and an oral; at least four CA tests by the end of the course; attendance at every test compulsory for eligibility; a CA test at the end of each semester.", weight: "50% of the final mark — conflicts with 30/70", exam: "Paper I essays, five of six; Paper II 100 or more MCQs plus practical theory; three hours each" },
  { department: "Psychiatry", components: "Attendance and participation in lectures, tutorials, seminars and clinical examinations; the week-8 end-of-posting clinical examination counts as CA.", weight: "Not stated", exam: "With Medicine in the Final: MCQ, essay, clinical cases" },
  { department: "Obstetrics & Gynaecology", components: "MCQs, essays, and electronic and non-electronic OSCE.", weight: "Not stated", exam: "Held \"together with Community Health and Paediatrics\"" },
  { department: "Surgery", components: "Test results at the end of each lecture group form the CA and count toward the final; 80% attendance and participation to sit the Surgery final.", weight: "Not stated; 80% attendance against the 70% general rule", exam: "Final" },
  { department: "Community Medicine", components: "Attendance and participation; the community study project (two bound copies, graded by neutral lecturers as part of CA, defended at the orals, a prerequisite for the final); continuous assessment.", weight: "Not stated", exam: "Professional examinations \"at 300 and 600 levels\"" },
  { department: "Chemical Pathology", components: "A desired-competency split by contact time — Knowledge 40%, Comprehension 30%, Application 30% — which describes teaching time, not assessment.", weight: "—", exam: "2nd Professional" },
];

export const LOGBOOKS = {
  paediatrics: "Observed or performed, five times each: lumbar puncture; scalp or peripheral IV infusion; venepuncture; exchange blood transfusion (watch and assist); nasogastric tube insertion; PCV/haematocrit; urinalysis; malaria RDT; random blood sugar.",
  familyMedicine: "Instruments — stethoscope, sphygmomanometer, thermometer, diagnostic set. Procedures — venepuncture, parenteral drug administration, basic lung-function testing, nebuliser use, point-of-care testing.",
};

/** what the College's academic system must hold — the document's proposed model; a field marked ◊ has no value in the source */
export const MODEL: [string, string][] = [
  ["Programme, Session, Level, Semester", "MBBS: six years UTME, five Direct Entry, 160 CU, regulations from 29 September 2021. Levels 100–600 with a phase and a clinical year. Semesters of 17, 17 and 20 weeks; ◊ start dates."],
  ["Department, DepartmentUnit, Course", "Departments under their block (Medicine, Surgery, Paediatrics, O&G, Pathology, Community, PHT…); units under a consultant; courses with credit units where the prospectus gives them, a status of C, E, EPS or core, and whether carry-over is allowed."],
  ["Registration", "By course, session, semester and attempt number — ◊ the mode itself (per semester or session, through the portal, whether posting codes are registered) is unconfirmed."],
  ["Block, Posting, PostingCourse, RotationGroup, PostingAllocation", "Internal Medicine 34 weeks and the rest; each posting with its tier (intro, junior, intermediate, senior, revision), level, duration and order, ◊ dates; the courses it carries; groups A and B; the student's allocation with supervisor."],
  ["TimetableSlot", "Week, weekday, start, end and type — lecture, ward round, clinic, bedside, seminar, departmental seminar, call duty, examination. Psychiatry's eight weeks are the only full data."],
  ["ProcedureRequirement, ProcedureLog, CaseClerking, MandatoryEvent, EventAttendance", "The Paediatrics minimum procedures (×5, observe or perform), verified by a supervisor; six cases clerked a posting; the Wednesday Grand Round."],
  ["AttendanceRule, AttendanceRecord", "75% pre-clinical, 70% clinical, 80% Surgery — by activity type; every session recorded."],
  ["ProfessionalExam, ExamSubject, AssessmentItem, AssessmentScore", "CPE and the four Professionals with their papers, external examiners, resit rules, the three-month window and the Senate appeal; each subject's departments, CA weight (30, or Pharmacology's 50?) and pass marks; each CA item with ◊ its weight within the 30 and whether it gates eligibility; every score by attempt."],
  ["Project, ExamResult, ProgressionDecision", "The Community Medicine project as an exam prerequisite; the result by attempt (first, resit, repeat, Senate appeal) with its distinction at 70; the decision — promote, resit, repeat, withdrawal advised or required, appeal — with the carry-overs and the rule it rests on."],
];

export const RULES_TO_IMPLEMENT = [
  "Eligibility: attendance against every rule that applies; Pharmacology also requires every course test sat.",
  "Pass: total 50 or more; for the 3rd and 4th examinations the clinical component 50 or more as well.",
  "1st Professional with all three subjects failed: repeat directly, no resit. CPE and 100 Level: no resit.",
  "A resit or repeat creates a new CA attempt; the old CA is never overwritten.",
  "Carry-over: GST and EPS courses only. Honours: a distinction in each of the four Professionals. Senate appeal: only after failing the Final after a repeat.",
];

export const CONFLICTS: string[] = [
  "Pharmacology CA weight: its chapter says 50%, the regulations 30% everywhere.",
  "Surgery attendance: 80% required, against the regulations' 70% for clinical stages.",
  "Surgery duration: stated as 30 weeks; the phases add to 26, or 34 with the SUG 606 revision block.",
  "O&G examination grouping: \"together with Community Health and Paediatrics\", but the regulations put Community Medicine in the 4th examination, not the 3rd.",
  "Community Medicine examination levels: its chapter says 300 and 600; the regulations list it only in the 4th.",
  "Pharmacology timing: a \"revision tutorial session in the 5th year\" and an examination called \"Part II\", yet the examination falls at the end of 400 Level; PHT III's level is not stated.",
  "Surgery refers to \"the final 5th MB.BS examination\"; there are four Professionals.",
  "The Final's rules say \"one or both subjects\" for three subjects, and point back to the \"Third Professional\" and to \"500 Level\" CA.",
  "100 Level credit totals: the table sums to 45 CU (Physics 10), the text says 46 (Physics 11).",
  "Chemical Pathology levels: the description says 400/500, the codes and posting table 300/400.",
  "Missing: calendar dates and the rotation order between blocks; how the 30% CA splits inside each department; SUG 603/604 titles; the course registration procedure; pages 1–23, 68–69 and 120–123 (blurred).",
];

/** the questions the College must answer before registration can be built */
export const TO_CONFIRM = [
  "Is registration per semester or per session, and is it through the University portal?",
  "Do clinical students register posting codes such as MED 403 or SUG 402 as courses?",
  "What happens to registration when a student repeats a year?",
];
