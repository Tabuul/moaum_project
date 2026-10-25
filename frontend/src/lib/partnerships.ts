/**
 * V658: collaboration and partnerships — the vocabularies the public form and the desk share, the words for statuses and flags,
 * the steps of the form with the checks the browser makes before the server's own (partnership.problems decides), and the rows of
 * the report. Imported by node --test with relative paths, so nothing here reaches for the server.
 */

export type Opt = [string, string];
export type YesNo = "YES" | "NO" | "NOT_SURE";

export const ORG_TYPES: Opt[] = [["UNIVERSITY", "University/Higher Education"], ["RESEARCH_INSTITUTE", "Research Institute"], ["COMPANY", "Company/Private Sector"],
  ["GOVERNMENT", "Government/Public Agency"], ["NGO", "NGO/Civil Society"], ["FOUNDATION_DONOR", "Foundation/Donor"], ["INTERNATIONAL_ORGANISATION", "International Organisation"],
  ["OTHER", "Other"]];
export const CONTACT_METHODS: Opt[] = [["EMAIL", "Email"], ["PHONE", "Telephone"], ["VIDEO_CALL", "Video call"], ["IN_PERSON", "In person"]];
export const PROPOSAL_KINDS: Opt[] = [["NEW", "New proposal"], ["EXISTING_DISCUSSION", "Existing discussion"], ["FOLLOW_UP", "Follow-up to a previous submission"]];
export const YES_NO_NOT_SURE: Opt[] = [["YES", "Yes"], ["NO", "No"], ["NOT_SURE", "Not sure"]];
export const FORMATS: Opt[] = [["ONE_OFF", "One-off activity"], ["PILOT", "Pilot project"], ["MULTI_YEAR", "Multi-year programme"],
  ["INSTITUTIONAL_AGREEMENT", "Formal institutional agreement"], ["JOINT_FUNDING_APPLICATION", "Joint funding application"], ["OTHER", "Other"]];
export const FUNDING: Opt[] = [["FULLY_FUNDED", "Fully funded"], ["PARTLY_FUNDED", "Partly funded"], ["APPLICATION_PLANNED", "Funding application planned"],
  ["NONE_IDENTIFIED", "No funding identified"], ["PREFER_TO_DISCUSS", "Prefer to discuss"]];
export const JOINT_GRANT: Opt[] = [["YES", "Yes"], ["NO", "No"], ["POSSIBLY", "Possibly"]];
export const RESOURCES: Opt[] = [["STAFF_EXPERTISE", "Staff expertise"], ["RESEARCH_FACILITIES", "Research facilities"], ["LABORATORY_EQUIPMENT", "Laboratory equipment"],
  ["SPECIALIST_EQUIPMENT", "Specialist equipment"], ["STUDENT_PARTICIPATION", "Student participation"], ["TRAINING", "Training"], ["VENUE", "Venue"],
  ["DATA_ACCESS", "Data access"], ["BRANDING", "Branding/communications"], ["FINANCIAL_CONTRIBUTION", "Financial contribution"], ["OTHER", "Other"]];
export const INTERNATIONAL_ASPECTS: Opt[] = [["ACTIVITIES", "Activities"], ["FUNDING", "Funding"], ["RESEARCH", "Research"], ["TRAVEL", "Travel"], ["DATA_PROCESSING", "Data processing"]];
export const AGREEMENT_TYPES: Opt[] = [["MOU", "Memorandum of Understanding"], ["MOA", "Memorandum of Agreement"], ["RESEARCH_AGREEMENT", "Research Agreement"],
  ["STUDENT_EXCHANGE", "Student Exchange Agreement"], ["NDA", "Non-Disclosure Agreement"], ["DATA_SHARING", "Data-Sharing Agreement"],
  ["IP_LICENSING", "Intellectual Property/Licensing Agreement"], ["NOT_SURE", "Not sure"]];
export const AGREEMENT_KINDS: Opt[] = [...AGREEMENT_TYPES.filter(([k]) => k !== "NOT_SURE"), ["OTHER", "Other"]];
export const SENSITIVE_KINDS: Opt[] = [["HEALTH", "Health"], ["BIOMETRICS", "Biometrics"], ["CHILDREN", "Children"], ["DEMOGRAPHIC", "Demographic data"], ["OTHER", "Other sensitive information"]];
export const HIGH_RISK: Opt[] = [["HUMAN_PARTICIPANTS", "Human participants"], ["ANIMALS", "Animals"], ["CLINICAL", "Clinical work"], ["HAZARDOUS", "Hazardous materials"],
  ["CONTROLLED_TECHNOLOGY", "Controlled technologies"], ["EXPORT_CONTROL", "Export-controlled items"], ["SECURITY_SENSITIVE", "Security-sensitive research"]];
export const COI: Opt[] = [["YES", "Yes"], ["NO", "No"], ["CONFIDENTIAL", "Prefer to discuss confidentially"]];
export const OWN_DD: Opt[] = [["YES", "Yes"], ["NO", "No"], ["IN_PROGRESS", "In progress"]];
export const ATTACHMENT_KINDS: Opt[] = [["CONCEPT_NOTE", "Concept note"], ["PROPOSAL", "Partnership proposal"], ["ORGANISATION_PROFILE", "Organisation profile"],
  ["DRAFT_MOU", "Draft MOU"], ["DRAFT_AGREEMENT", "Draft agreement"], ["CV", "CV of lead investigator"], ["FUNDING_CALL", "Grant/funding call"], ["BUDGET", "Budget"],
  ["SUPPORT_LETTER", "Institutional support letter"], ["REGISTRATION_EVIDENCE", "Accreditation/registration evidence"], ["OTHER", "Other"]];
export const CURRENCIES = ["NGN", "USD", "EUR", "GBP", "CAD", "AUD", "CHF", "JPY", "CNY", "ZAR", "GHS", "KES", "XOF", "AED", "SAR", "INR"];
export const LANGUAGES = ["English", "French", "Arabic", "Portuguese", "Spanish", "German", "Chinese", "Hausa", "Yoruba", "Igbo", "Tiv", "Other"];

export const STATUS_WORDS: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  DRAFT: ["Draft", "grey"], RECEIVED: ["Received", "info"], INITIAL_SCREENING: ["Initial screening", "info"], AWAITING_INFORMATION: ["Awaiting information", "warn"],
  ROUTED: ["Routed", "info"], ASSIGNED: ["Assigned", "info"], UNDER_REVIEW: ["Under review", "info"], DUE_DILIGENCE: ["Due diligence", "warn"],
  MEETING_PROPOSED: ["Meeting proposed", "info"], UNDER_DEVELOPMENT: ["Under development", "info"], PENDING_APPROVAL: ["Pending approval", "warn"],
  APPROVED_FOR_DEVELOPMENT: ["Approved for development", "ok"], AGREEMENT_REVIEW: ["Agreement review", "warn"], AGREEMENT_EXECUTED: ["Agreement executed", "ok"],
  IMPLEMENTATION: ["Implementation", "ok"], ACTIVE: ["Active", "ok"], DECLINED: ["Declined", "bad"], CLOSED: ["Closed", "grey"], CANCELLED: ["Cancelled", "grey"],
};
export const ACTION_WORDS: Record<string, string> = {
  START_SCREENING: "Start screening", ASSIGN: "Assign owner", ACCEPT: "Accept for review", ROUTE: "Route", REQUEST_INFORMATION: "Request information",
  WITHDRAW_REQUEST: "Withdraw the request", START_DUE_DILIGENCE: "Start due diligence", MEETING: "Meeting proposed", DEVELOP: "Under development",
  SUBMIT_FOR_APPROVAL: "Submit for approval", APPROVE: "Approve", DECLINE: "Decline", IMPLEMENT: "Start implementation", ACTIVATE: "Activate", CLOSE: "Close",
  CANCEL: "Cancel (withdrawn by the applicant)",
};
/** the actions that ask for a reason or a note before they go */
export const ACTION_NEEDS: Record<string, "reason" | "note" | "none"> = {
  DECLINE: "reason", CLOSE: "reason", CANCEL: "reason", ROUTE: "reason", APPROVE: "note", MEETING: "note", DEVELOP: "note", SUBMIT_FOR_APPROVAL: "note",
  ACCEPT: "note", START_SCREENING: "none", IMPLEMENT: "note", ACTIVATE: "note", START_DUE_DILIGENCE: "none", WITHDRAW_REQUEST: "none", ASSIGN: "none",
  REQUEST_INFORMATION: "none",
};
export const FLAG_WORDS: Record<string, string> = {
  INTERNATIONAL: "International", PERSONAL_DATA: "Personal data", SENSITIVE_DATA: "Sensitive data", ETHICS: "Ethics", HUMAN_PARTICIPANTS: "Human participants",
  ANIMALS: "Animals", CLINICAL: "Clinical", HAZARDOUS: "Hazardous", CONTROLLED_TECHNOLOGY: "Controlled technology", EXPORT_CONTROL: "Export control",
  SECURITY_SENSITIVE: "Security-sensitive", FUNDING: "Funding", FORMAL_AGREEMENT: "Formal agreement", IP: "IP", NDA: "NDA", DATA_SHARING: "Data sharing",
  CONFLICT_OF_INTEREST: "Conflict of interest",
};
export const RECOMMENDATIONS: Opt[] = [["SUPPORT", "Support"], ["SUPPORT_WITH_CONDITIONS", "Support with conditions"], ["DO_NOT_SUPPORT", "Do not support"],
  ["NEED_MORE_INFORMATION", "Need more information"]];
export const DD_STATUS: Opt[] = [["PENDING", "Pending"], ["SATISFACTORY", "Satisfactory"], ["CONCERN", "Concern"], ["NOT_APPLICABLE", "Not applicable"]];
export const AGREEMENT_STATUS: Record<string, string> = { DRAFT: "Draft", LEGAL_REVIEW: "Legal review", APPROVAL: "Awaiting approval", SIGNING: "Signing",
  EXECUTED: "Executed", EXPIRED: "Expired", TERMINATED: "Terminated", WITHDRAWN: "Withdrawn" };

/** the timeline's own events, beside the workflow's actions */
const EVENT_WORDS: Record<string, string> = {
  SUBMITTED: "Submitted", RECORDED: "Recorded by the office", ROUTED: "Routed", COMPLIANCE_REVIEW_REQUIRED: "Compliance review required",
  INFORMATION_RECEIVED: "Information received", LINK_REISSUED: "Status link sent again", REVIEWER_ASKED: "Reviewer asked", REVIEWER_WITHDRAWN: "Reviewer withdrawn",
  REVIEWED: "Review given", MESSAGE_SENT: "Message to the applicant", DUE_DILIGENCE: "Due-diligence check", EDITED: "Record corrected",
  DOCUMENT_ADDED: "Document added", DOCUMENT_OPENED: "Document opened", ACTIVITY: "Activity", OUTCOME: "Outcome recorded",
  AGREEMENT_CREATED: "Agreement prepared", AGREEMENT_EXECUTED: "Agreement executed", AGREEMENT_EXPIRED: "Agreement expired",
  AGREEMENT_SEND_TO_LEGAL: "Agreement sent for legal review", AGREEMENT_LEGAL_CLEAR: "Agreement cleared by the Legal Officer",
  AGREEMENT_LEGAL_RETURN: "Agreement returned by the Legal Officer", AGREEMENT_APPROVE: "Agreement approved", AGREEMENT_EXECUTE: "Agreement signed copy recorded",
  AGREEMENT_UPDATE_DATES: "Agreement dates updated", AGREEMENT_TERMINATE: "Agreement terminated", AGREEMENT_WITHDRAW: "Agreement withdrawn",
};
export const eventWord = (a: string): string =>
  ACTION_WORDS[a] ?? EVENT_WORDS[a] ?? (a.charAt(0) + a.slice(1).toLowerCase().replace(/_/g, " "));

export const word = (opts: Opt[], key: string | null | undefined): string => (key ? opts.find(([k]) => k === key)?.[1] ?? key : "—");
export const words = (opts: Opt[], keys: string[] | null | undefined): string => (keys && keys.length ? keys.map((k) => word(opts, k)).join(", ") : "—");
export const statusWord = (s: string | null | undefined): string => (s ? STATUS_WORDS[s]?.[0] ?? s : "—");

/** ISO 3166 region codes; their names come from the browser in English */
const REGIONS = "AF AX AL DZ AS AD AO AI AQ AG AR AM AW AU AT AZ BS BH BD BB BY BE BZ BJ BM BT BO BQ BA BW BV BR IO BN BG BF BI CV KH CM CA KY CF TD CL CN CX CC CO KM CG CD CK CR CI HR CU CW CY CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET FK FO FJ FI FR GF PF TF GA GM GE DE GH GI GR GL GD GP GU GT GG GN GW GY HT HM VA HN HK HU IS IN ID IR IQ IE IM IL IT JM JP JE JO KZ KE KI KP KR KW KG LA LV LB LS LR LY LI LT LU MO MG MW MY MV ML MT MH MQ MR MU YT MX FM MD MC MN ME MS MA MZ MM NA NR NP NL NC NZ NI NE NG NU NF MK MP NO OM PK PW PS PA PG PY PE PH PN PL PT PR QA RE RO RU RW BL SH KN LC MF PM VC WS SM ST SA SN RS SC SL SG SX SK SI SB SO ZA GS SS ES LK SD SR SJ SE CH SY TW TJ TZ TH TL TG TK TO TT TN TR TM TC TV UG UA AE GB US UM UY UZ VU VE VN VG VI WF EH YE ZM ZW".split(" ");
export function countries(): string[] {
  let names: string[] = [];
  try {
    const dn = new Intl.DisplayNames(["en"], { type: "region" });
    names = REGIONS.map((c) => dn.of(c) ?? c);
  } catch {
    names = REGIONS;
  }
  return [...new Set(names)].sort((a, b) => a.localeCompare(b));
}

/** the form's answers as the browser keeps them (the API's keys) */
export interface Answers {
  firstName?: string; lastName?: string; jobTitle?: string; orgName?: string; orgType?: string; orgTypeOther?: string; email?: string; phone?: string;
  country?: string; city?: string; address?: string; website?: string; profileUrl?: string; language?: string; contactMethod?: string; timeZone?: string;
  proposalKind?: string; previousReference?: string; hasContact?: boolean | null; contactName?: string; contactUnit?: string; contactEmail?: string;
  collaboratedBefore?: string; previousCollaboration?: string;
  category?: string; secondaryCategory?: string; title?: string; summary?: string; description?: string; objectives?: string; activities?: string;
  expectedResults?: string; whyUniversity?: string; facultyCode?: string; deptCode?: string; unitText?: string; expertise?: string; staffContact?: string;
  startDate?: string; duration?: string; collaborationFormat?: string; benefitsUniversity?: string; benefitsPartner?: string;
  fundingStatus?: string; budget?: string; currency?: string; funder?: string; jointGrant?: string; fundingDeadline?: string; resourcesRequested?: string[];
  resourcesOther?: string; partnerContribution?: string;
  international?: boolean | null; countries?: string[]; internationalAspects?: string[]; agreementTypes?: string[]; personalData?: string; sensitiveData?: string;
  sensitiveKinds?: string[]; ethics?: string; highRisk?: Record<string, string>; coi?: string; coiDetail?: string; ownDueDiligence?: string;
  declaredAccurate?: boolean; declaredAuthorised?: boolean; declaredNoCommitment?: boolean; declaredPrivacy?: boolean; consentContact?: boolean; consentMarketing?: boolean;
}

export const STEPS = ["Applicant details", "Existing University connection", "Partnership proposal", "Funding & resources", "International, legal & compliance",
  "Attachments", "Declarations & consent", "Review & submit"];

export interface Problem { step: number; field: string; message: string }
export interface Limits { summary_max: number; text_max: number; benefits_max: number; max_files: number; max_file_mb: number }

const filled = (s: string | undefined | null) => !!s && s.trim().length > 0;
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/;

/** what the browser checks on a step before moving on — the server checks everything again (partnership.problems) */
export function stepProblems(step: number, a: Answers, lim: Limits): Problem[] {
  const out: Problem[] = [];
  const need = (ok: boolean, field: string, message: string) => { if (!ok) out.push({ step, field, message }); };
  const max = (v: string | undefined, n: number, field: string, label: string) => need((v ?? "").length <= n, field, `${label}: keep it within ${n.toLocaleString("en-GB")} characters.`);
  if (step === 1) {
    need(filled(a.firstName), "firstName", "First name: enter your first name.");
    need(filled(a.lastName), "lastName", "Last name: enter your last name.");
    need(filled(a.orgName), "orgName", "Organisation name: enter the name of your organisation.");
    need(filled(a.orgType), "orgType", "Organisation type: choose the type of your organisation.");
    if (a.orgType === "OTHER") need(filled(a.orgTypeOther), "orgTypeOther", "Organisation type: describe the type of your organisation.");
    need(EMAIL.test((a.email ?? "").trim()), "email", "Work email address: enter a valid email address for your organisation.");
    if (filled(a.phone)) need(/^\+?[0-9 ()-]{6,24}$/.test(a.phone!.trim()), "phone", "Telephone: enter a telephone number of digits, spaces, brackets or dashes, with the country code.");
    need(filled(a.country), "country", "Country/territory: choose your country or territory.");
  } else if (step === 2) {
    need(filled(a.proposalKind), "proposalKind", "Is this: choose new proposal, existing discussion or follow-up.");
    if (a.proposalKind === "FOLLOW_UP") need(filled(a.previousReference), "previousReference", "Previous reference: enter the reference of your earlier submission (PTN/YYYY/NNNNNN).");
    need(a.hasContact === true || a.hasContact === false, "hasContact", "University contact: say whether you already have a University contact.");
    if (a.hasContact) need(filled(a.contactName), "contactName", "Contact name: enter the name of your University contact.");
    if (a.hasContact && filled(a.contactEmail)) need(EMAIL.test(a.contactEmail!.trim()), "contactEmail", "Contact email: enter a valid email address for your University contact.");
    need(filled(a.collaboratedBefore), "collaboratedBefore", "Previous collaboration: say whether you have collaborated with the University before.");
    if (a.collaboratedBefore === "YES") need(filled(a.previousCollaboration), "previousCollaboration", "Previous collaboration: describe the earlier collaboration.");
  } else if (step === 3) {
    need(filled(a.category), "category", "Primary collaboration category: choose the category that fits best.");
    if (filled(a.secondaryCategory)) need(a.secondaryCategory !== a.category, "secondaryCategory", "Secondary category: choose a category other than the primary one, or none.");
    need((a.title ?? "").trim().length >= 5 && (a.title ?? "").trim().length <= 200, "title", "Proposed partnership title: enter a title of 5 to 200 characters.");
    need((a.summary ?? "").trim().length >= 20, "summary", "Short summary: describe the proposal in at least 20 characters.");
    max(a.summary, lim.summary_max, "summary", "Short summary");
    need((a.description ?? "").trim().length >= 20, "description", "Detailed description: describe the proposal in at least 20 characters.");
    max(a.description, lim.text_max, "description", "Detailed description");
    max(a.objectives, lim.text_max, "objectives", "Objectives");
    max(a.activities, lim.text_max, "activities", "Activities");
    max(a.expectedResults, lim.text_max, "expectedResults", "Expected results");
    max(a.whyUniversity, lim.text_max, "whyUniversity", "Why partner with this University");
    max(a.benefitsUniversity, lim.benefits_max, "benefitsUniversity", "Expected benefits to the University");
    max(a.benefitsPartner, lim.benefits_max, "benefitsPartner", "Expected benefits to your organisation");
  } else if (step === 4) {
    need(filled(a.fundingStatus), "fundingStatus", "Funding: say whether funding is already available.");
    if (filled(a.budget)) {
      need(/^[0-9][0-9,]*(\.[0-9]{1,2})?$/.test(a.budget!.trim()), "budget", "Estimated budget: enter an amount in figures, such as 250000.");
      need(filled(a.currency), "currency", "Currency: choose the currency of the estimated budget.");
    }
    if ((a.resourcesRequested ?? []).includes("OTHER")) need(filled(a.resourcesOther), "resourcesOther", "Other resources: describe the other resources requested.");
  } else if (step === 5) {
    need(a.international === true || a.international === false, "international", "Partners outside the country: say whether the proposal involves partners outside the country.");
    if (a.international) need((a.countries ?? []).length > 0, "countries", "Countries involved: name the countries involved.");
    need(filled(a.personalData), "personalData", "Personal data: say whether the project will involve personal data.");
    if (a.personalData === "YES") need(filled(a.sensitiveData), "sensitiveData", "Sensitive personal data: say whether it will involve sensitive personal data.");
    need(filled(a.ethics), "ethics", "Ethics approval: say whether the project will require ethics approval.");
    for (const [k, label] of HIGH_RISK) need(filled(a.highRisk?.[k]), `highRisk.${k}`, `${label}: answer yes, no or not sure.`);
    need(filled(a.coi), "coi", "Conflicts of interest: answer yes, no, or prefer to discuss confidentially.");
    if (a.coi === "YES") need(filled(a.coiDetail), "coiDetail", "Conflicts of interest: describe what should be disclosed.");
    need(filled(a.ownDueDiligence), "ownDueDiligence", "Due diligence: say whether your organisation has conducted its own review.");
  } else if (step === 7) {
    need(!!a.declaredAccurate, "declaredAccurate", "Declaration: confirm that the information is accurate.");
    need(!!a.declaredAuthorised, "declaredAuthorised", "Declaration: confirm that you are authorised to submit this enquiry.");
    need(!!a.declaredNoCommitment, "declaredNoCommitment", "Declaration: confirm that you understand this creates no legal, financial or contractual relationship.");
    need(!!a.declaredPrivacy, "declaredPrivacy", "Declaration: confirm that you have read the privacy notice.");
    need(!!a.consentContact, "consentContact", "Consent: agree to be contacted about this collaboration request.");
  }
  return out;
}

/** the answers sent to the API: blanks as empty strings (the server clears them), the budget without separators */
export function payload(a: Answers): Record<string, unknown> {
  const out: Record<string, unknown> = { ...a };
  if (typeof a.budget === "string") out.budget = a.budget.replace(/[,\s]/g, "");
  return out;
}

/** the answers read back from a saved draft (the API's column names) */
export function fromDraft(r: Record<string, unknown>): Answers {
  const s = (k: string) => (r[k] == null ? undefined : String(r[k]));
  const arr = (k: string) => (Array.isArray(r[k]) ? (r[k] as string[]) : []);
  let highRisk: Record<string, string> = {};
  try { highRisk = r.high_risk ? JSON.parse(String(r.high_risk)) : {}; } catch { highRisk = {}; }
  return {
    firstName: s("first_name"), lastName: s("last_name"), jobTitle: s("job_title"), orgName: s("org_name"), orgType: s("org_type"), orgTypeOther: s("org_type_other"),
    email: s("email"), phone: s("phone"), country: s("country"), city: s("city"), address: s("address"), website: s("website"), profileUrl: s("profile_url"),
    language: s("language"), contactMethod: s("contact_method"), timeZone: s("time_zone"), proposalKind: s("proposal_kind"), previousReference: s("previous_reference"),
    hasContact: r.has_contact == null ? null : Boolean(r.has_contact), contactName: s("contact_name"), contactUnit: s("contact_unit"), contactEmail: s("contact_email"),
    collaboratedBefore: s("collaborated_before"), previousCollaboration: s("previous_collaboration"), category: s("category"), secondaryCategory: s("secondary_category"),
    title: s("title"), summary: s("summary"), description: s("description"), objectives: s("objectives"), activities: s("activities"),
    expectedResults: s("expected_results"), whyUniversity: s("why_university"), facultyCode: s("faculty_code"), deptCode: s("dept_code"), unitText: s("unit_text"),
    expertise: s("expertise"), staffContact: s("staff_contact"), startDate: s("start_date"), duration: s("duration"), collaborationFormat: s("collaboration_format"),
    benefitsUniversity: s("benefits_university"), benefitsPartner: s("benefits_partner"), fundingStatus: s("funding_status"), budget: s("budget"), currency: s("currency"),
    funder: s("funder"), jointGrant: s("joint_grant"), fundingDeadline: s("funding_deadline"), resourcesRequested: arr("resources_requested"),
    resourcesOther: s("resources_other"), partnerContribution: s("partner_contribution"), international: r.international == null ? null : Boolean(r.international),
    countries: arr("countries"), internationalAspects: arr("international_aspects"), agreementTypes: arr("agreement_types"), personalData: s("personal_data"),
    sensitiveData: s("sensitive_data"), sensitiveKinds: arr("sensitive_kinds"), ethics: s("ethics"), highRisk, coi: s("coi"), coiDetail: s("coi_detail"),
    ownDueDiligence: s("own_due_diligence"), consentMarketing: Boolean(r.consent_marketing),
    // the declarations are never carried over: they are given afresh before submission
    declaredAccurate: false, declaredAuthorised: false, declaredNoCommitment: false, declaredPrivacy: false, consentContact: false,
  };
}

export const bytes = (n: number) => (n >= 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
export const ALLOWED_EXT = ["pdf", "docx", "xlsx", "pptx"];
/** a file the form refuses before uploading it: its type by name (the server checks the content too) or its size */
export function fileProblem(name: string, size: number, maxMb: number): string | null {
  const ext = (name.split(".").pop() ?? "").toLowerCase();
  if (!ALLOWED_EXT.includes(ext) || !name.includes(".")) return `${name}: upload a PDF, DOCX, XLSX or PPTX file within the permitted size.`;
  if (size > maxMb * 1048576) return `${name}: the file is ${bytes(size)}; upload a file of at most ${maxMb} MB.`;
  if (size === 0) return `${name}: the file is empty.`;
  return null;
}

export const dateWords = (iso: string | null | undefined, withTime = false): string => {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleString("en-GB", withTime ? { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }
    : { day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Lagos" });
};
export const money = (n: unknown, cur?: string | null): string => (n == null || n === "" ? "—" : `${cur ? cur + " " : ""}${Number(n).toLocaleString("en-GB", { maximumFractionDigits: 2 })}`);

/** the report's list as the PDF prints it */
export const REPORT_HEAD = ["Reference", "Organisation", "Country", "Category", "Title", "Faculty", "Department", "Status", "Owner", "Received", "Due"];
export function reportRows(rows: Record<string, unknown>[]): (string | number | null)[][] {
  return rows.map((r) => [String(r.reference ?? ""), String(r.org_name ?? ""), String(r.country ?? ""), String(r.category_label ?? ""), String(r.title ?? ""),
    String(r.faculty ?? ""), String(r.department ?? ""), statusWord(r.status as string), String(r.owner_name ?? "Unassigned"),
    dateWords(r.received_at as string), r.due_on ? dateWords(r.due_on as string) : ""]);
}
