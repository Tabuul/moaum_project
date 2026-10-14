import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { jpegSize } from "@/lib/pdf-write";
import { qrMatrix } from "@/lib/qr";
import { loadInstitution } from "@/lib/document/institution-server";
import { PdfDocument, type DocumentMeta } from "@/lib/document/pdf";
import { formatDocDate, formatDocDateTime } from "@/lib/document/institution";
import { ELIGIBILITY, REMEDIATION, TARGET_NOTE, labelOf, remediationWords, type PrelimBlock, type PrelimView } from "@/lib/preliminary";

export const dynamic = "force-dynamic";

interface Doc { id: string; kind: string; label?: string; filename: string; status: string }
interface Payment { reference: string; kind: string; amount: number; confirmed_at?: string | null; confirmedAt?: string | null; receipt_no?: string | null; receiptNo?: string | null }
/** what the desk's detail gives an officer (/api/v1/admissions/preliminary/applications/{id}) */
interface OfficeDetail {
  application: { application_no: string; session: string; surname: string; other_names: string; sex: string | null; email?: string; phone?: string };
  preliminary: PrelimBlock; documents: Doc[]; payments: Payment[];
}
interface Letter { number: string; version: number; verification_code: string; statement: string; issued_on: string; verifyPath: string }

const money = (n: number | string | null | undefined) => (n == null ? "-" : "NGN " + Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 }));

/** the applicant's passport photograph as a JPEG (the form takes a JPEG); null when none */
async function passport(path: string | null): Promise<DocumentMeta["photo"]> {
  if (!path) return null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}${path}`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (!res.ok) return null;
    const data = new Uint8Array(await res.arrayBuffer());
    const dim = jpegSize(data);
    return dim ? { width: dim.width, height: dim.height, data } : null;
  } catch {
    return null;
  }
}

/**
 * V446 — the Preliminary Science papers on the University's document writer, with the applicant's passport at the top right:
 * the application form (the applicant's own, or any application's for the Preliminary Science desk with ?id=, which its own
 * endpoint scopes), and the admission letter (the applicant's, once the admission is published: it names the Preliminary
 * Science Programme and the target programme only as an intended progression). Each is issued only when the server's record
 * supports it.
 */
export async function GET(req: Request, { params }: { params: Promise<{ doc: string }> }) {
  const { doc } = await params;
  const url = new URL(req.url);
  const id = url.searchParams.get("id");
  const office = !!id && /^[0-9a-f-]{36}$/i.test(id);
  const download = url.searchParams.get("download") === "1";
  const inst = await loadInstitution();
  const refuse = (title: string, status = 409) => NextResponse.json({ status, title }, { status });

  let p: PrelimBlock, appNo: string, session: string, name: string, sex: string | null, email: string | null, phone: string | null;
  let documents: Doc[], payments: Payment[], passportPath: string | null;
  if (office) {
    const r = await api<OfficeDetail>(`/api/v1/admissions/preliminary/applications/${id}`);
    if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
    const d = r.data;
    p = d.preliminary; appNo = d.application.application_no; session = d.application.session; name = `${d.application.surname}, ${d.application.other_names}`;
    sex = d.application.sex; email = d.application.email ?? null; phone = d.application.phone ?? null; documents = d.documents; payments = d.payments;
    const pass = d.documents.find((x) => x.kind === "PASSPORT");
    passportPath = pass ? `/api/v1/admissions/preliminary/applications/${id}/documents/${pass.id}/content` : null;
  } else {
    const r = await api<PrelimView>("/api/v1/applicant/me/preliminary");
    if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
    const v = r.data;
    p = v.preliminary; appNo = v.applicationNo; session = v.session; name = v.name; sex = p.sex; email = v.email; phone = v.phone;
    documents = v.documents.map((x) => ({ id: x.id, kind: x.kind, filename: x.filename, status: x.status }));
    payments = v.feeReferences.map((f) => ({ reference: f.reference, kind: f.kind, amount: f.amount, confirmedAt: f.confirmedAt, receiptNo: f.receiptNo }));
    const pass = v.documents.find((x) => x.kind === "PASSPORT");
    passportPath = pass ? `/api/v1/applicant/me/documents/${pass.id}/content` : null;
  }
  const photo = await passport(passportPath);
  const label = (kind: string) => p.programmeInfo.documents.find((d) => d.kind === kind)?.label ?? kind.replace(/_/g, " ").toLowerCase();
  const field = (f: string) => p.fields.find((x) => x.field === f)?.value ?? "-";
  const target = p.programmeInfo.targets.find((t) => t.programmeCode === p.targetProgramme)?.name ?? p.targetName ?? "-";
  let pdf: PdfDocument;
  let file: string;

  if (doc === "form") {
    const submitted = !!p.submittedAt;
    pdf = new PdfDocument("FORM", { title: "Preliminary Science application form", subtitle: `${session} academic session`, reference: appNo,
      unit: "Preliminary Science Office", photo, photoBox: true, watermark: submitted ? null : "NOT YET SUBMITTED",
      meta: [["Programme", "Preliminary Science (Preliminary / Remedial)"], ["Session", session]] }, inst);
    pdf.space(8);
    pdf.heading("Applicant");
    pdf.keyValues([["Application number", appNo], ["Name", name], ["Sex", sex === "F" ? "Female" : sex === "M" ? "Male" : "-"], ["Date of birth", formatDocDate(field("date_of_birth"), inst)],
      ["Email", email ?? "-"], ["Phone", phone ?? "-"], ["Nationality", field("nationality")], ["State of origin", field("state_of_origin")], ["Local government area", field("lga")],
      ["Home address", field("home_address")], ["Next of kin", `${field("kin_name")} (${field("kin_relationship")}), ${field("kin_mobile")}`],
      ["Submitted", submitted ? formatDocDateTime(p.submittedAt, inst) : "Not yet submitted"]]);
    pdf.heading("O'Level results");
    pdf.table(["Sitting", "Body", "Examination", "Number", "Year", "Subject", "Grade"],
      p.olevel.map((o) => [String(o.sitting), o.exam_body, o.exam_type ?? "-", o.exam_number, String(o.exam_year), o.subject, o.grade]), { serial: false });
    pdf.heading("Eligibility, as the portal reads the results given");
    pdf.keyValues([["Status", labelOf(ELIGIBILITY, p.eligibility.status)[0]], ["Credit passes", p.eligibility.totalCredits < 0 ? "-" : String(p.eligibility.totalCredits)],
      ["Core science credits", p.eligibility.coreCredits < 0 ? "-" : String(p.eligibility.coreCredits)], ["Sittings", String(p.eligibility.sittings)],
      ["Remediation", p.remediation.status ? `${labelOf(REMEDIATION, p.remediation.status)[0]}${p.remediation.status === "REQUIRED" ? `: ${remediationWords(p.remediation)}` : ""}` : "-"]]);
    pdf.paragraph("The University verifies every result against the documents; this reading is not a decision.", 8.5);
    pdf.heading("Target programme");
    pdf.keyValues([["Intended progression", target]], 1);
    pdf.paragraph(TARGET_NOTE, 8.5);
    pdf.heading("Payment");
    const paid = payments.filter((x) => x.confirmedAt ?? x.confirmed_at);
    pdf.table(["Fee", "Reference", "Amount", "Receipt", "Verified"], paid.map((x) => [x.kind === "APPLICATION" ? "Application fee" : x.kind, x.reference, money(x.amount),
      x.receiptNo ?? x.receipt_no ?? "-", formatDocDate((x.confirmedAt ?? x.confirmed_at) as string, inst)]), { serial: false });
    pdf.heading("Documents submitted");
    pdf.table(["Document", "File", "Status"], documents.map((d) => [d.label ?? label(d.kind), d.filename, d.status === "ACCEPTED" ? "Accepted" : d.status === "REJECTED" ? "Rejected" : "Received"]), { serial: true });
    pdf.heading("Declaration");
    pdf.paragraph("I declare that the particulars given in this application are true, and that the O'Level results given are released results. I understand that a false statement or document ends the application, and any admission that follows from it.");
    pdf.signatures([{ name, designation: "Applicant's signature and date" }, { designation: "Preliminary Science Office (stamp and date)" }]);
    file = `preliminary-science-application-${appNo.replace(/\//g, "-")}`;
  } else if (doc === "letter") {
    if (office) return refuse("The admission letter is printed by the applicant from their own portal.", 403);
    if (p.state !== "ADMITTED") return refuse("The admission letter is issued once your admission into the Preliminary Science Programme is published.");
    const l = await api<Letter>(`/api/v1/applicant/me/letter${url.searchParams.get("print") === "1" ? "?event=PRINTED" : ""}`);
    if (!l.ok) return NextResponse.json(l.problem, { status: l.problem.status });
    const letter = l.data;
    const st = JSON.parse(letter.statement) as { targetProgramme?: string | null; targetFaculty?: string | null; targetDepartment?: string | null; remediationRequired?: boolean;
      remediationSubjects?: string[]; remediationCreditsShort?: number; completionNote?: string | null; decisionReleasedOn?: string | null };
    pdf = new PdfDocument("LETTER", { title: "Offer of provisional admission: Preliminary Science Programme", subtitle: `${session} academic session`, reference: letter.number,
      unit: "Office of the Registrar · Preliminary Science Programme", photo, photoBox: true }, inst);
    pdf.space(8);
    pdf.keyValues([["Name", name], ["Application number", appNo], ["Admission reference", letter.number], ["Date", formatDocDate(letter.issued_on, inst)]]);
    const first = name.includes(",") ? name.split(",")[1].trim().split(" ")[0] : name;
    pdf.paragraph(`Dear ${first},`);
    pdf.paragraph(`I am pleased to inform you that you have been offered provisional admission into the Preliminary Science Programme of ${inst.name} for the ${session} academic session, as below.`);
    pdf.keyValues([["Programme", "Preliminary Science"], ["Programme type", "Preliminary / Remedial"], ["Study mode", "Full-time"], ["Academic session", session],
      ["Admission status", "Admitted"], ["Intended progression (target programme)", st.targetProgramme ? `${st.targetProgramme}${st.targetDepartment ? ` (${st.targetDepartment})` : ""}` : "-"]], 1);
    pdf.heading("Conditions");
    const conditions = [
      `This admission is into the Preliminary Science Programme only. ${TARGET_NOTE}`,
      "This offer is provisional and subject to the verification of your credentials. Should any of them be found false, the offer is withdrawn.",
      ...(st.remediationRequired ? [`Before completing the programme you are to make up: ${remediationWords({ subjects: st.remediationSubjects ?? [], creditsShort: st.remediationCreditsShort ?? 0 })}. ${st.completionNote ?? ""}`.trim()] : []),
      "The University will tell you of the next steps of the programme on the portal.",
    ];
    conditions.forEach((t, i) => pdf.paragraph(`${i + 1}. ${t}`));
    pdf.paragraph("Congratulations.");
    pdf.signatures([{ designation: "Registrar" }]);
    pdf.qr(qrMatrix(`${url.origin}${letter.verifyPath}`), `Document ${letter.number} · version ${letter.version} · verification code ${letter.verification_code}`);
    file = `preliminary-science-admission-letter-${appNo.replace(/\//g, "-")}`;
  } else {
    return refuse("No such paper.", 404);
  }
  const bytes = pdf.finish();
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf",
    "content-disposition": `${download ? "attachment" : "inline"}; filename="${file}.pdf"`, "cache-control": "no-store" } });
}
