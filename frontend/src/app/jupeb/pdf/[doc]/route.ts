import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { jpegSize } from "@/lib/pdf-write";
import { qrMatrix } from "@/lib/qr";
import { loadInstitution } from "@/lib/document/institution-server";
import { PdfDocument, type DocumentMeta } from "@/lib/document/pdf";
import { formatDocDate } from "@/lib/document/institution";
import { ADMISSION_STATUS, FEE_KIND, feeCategoryLabel, fullName, streamLabel, type Candidate } from "@/lib/jupeb";

export const dynamic = "force-dynamic";

/** the papers that carry a verification code (V343), by the route's name */
const PAPER: Record<string, string> = {
  acknowledgement: "ACKNOWLEDGEMENT", status: "STATUS_SLIP", letter: "ADMISSION_LETTER", acceptance: "ACCEPTANCE_LETTER",
  receipt: "RECEIPT", slip: "REGISTRATION_SLIP", result: "RESULT",
};

const money = (n: number | string | null | undefined) => (n == null ? "-" : "NGN " + Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 }));

/** the passport photograph, as a JPEG the API converts (a PNG upload included); null when none or unreadable */
async function passport(c: Candidate, office: boolean): Promise<DocumentMeta["photo"]> {
  if (!c.has_passport) return null;
  try {
    const tok = await sessionToken();
    const path = office ? `/api/v1/jupeb/office/applications/${c.id}/documents/PASSPORT/content?format=jpeg` : "/api/v1/jupeb/me/documents/PASSPORT/content?format=jpeg";
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
 * A JUPEB candidate's papers (V339, V342), on the University's document writer, each with the candidate's passport at the
 * top right: the application acknowledgement and summary, the admission status slip, the admission letter, the acceptance
 * letter, the school fees invoice, payment receipts, the registration slip and the statement of result (the Board's sample
 * layout). The candidate reads their own (/api/v1/jupeb/me); the JUPEB Office prints any candidate's with ?id= (its own
 * endpoint decides who may). Each paper is issued only when the record supports it — the server's record, never the page's:
 * the status slip and the admission letter once the candidate may see the decision (the status checking fee confirmed),
 * the acceptance letter on the confirmed acceptance fee, a receipt for a confirmed payment, the slip after registration, the
 * statement after publication.
 */
export async function GET(req: Request, { params }: { params: Promise<{ doc: string }> }) {
  const { doc } = await params;
  const url = new URL(req.url);
  const id = url.searchParams.get("id");
  const office = !!id && /^[0-9a-f-]{36}$/i.test(id);
  const inst = await loadInstitution();
  const res = await api<Candidate>(office ? `/api/v1/jupeb/office/applications/${id}` : "/api/v1/jupeb/me");
  if (!res.ok) return NextResponse.json(res.problem, { status: res.problem.status });
  const c = res.data;
  const admitted = ["ADMITTED", "STUDENT", "COMPLETED"].includes(c.state);
  /* the candidate sees the decision only once checking is paid (the server masks it otherwise); the office always */
  const mayCheck = office || c.statusChecking.may_check;
  const refuse = (title: string) => NextResponse.json({ status: 409, title }, { status: 409 });
  const photo = await passport(c, office);
  const comb = c.combination_code ? `${c.combination_code}: ${c.subjects.map((s) => s.title).join(", ")}` : "-";
  const who: [string, string][] = [["Name", fullName(c)], ["Application number", c.application_no], ["Session", c.session], ["Programme", streamLabel(c.stream)]];
  const paper = (profile: string, meta: DocumentMeta) => { const d = new PdfDocument(profile, { ...meta, photo, photoBox: true }, inst); d.space(8); return d; };
  const paidRef = (kind: string) => c.references.find((r) => r.kind === kind && r.confirmed_at) ?? null;
  let pdf: PdfDocument;
  let name: string;

  if (doc === "acknowledgement") {
    if (!c.submitted_at) return refuse("The acknowledgement is issued once the application is submitted.");
    const fee = paidRef("APPLICATION");
    pdf = paper("FORM", { title: "JUPEB application acknowledgement", reference: c.application_no, subtitle: `${c.session} academic session`, unit: "JUPEB Office" });
    pdf.keyValues([...who, ["Subject combination", comb], ["Email", c.email], ["Phone", c.phone ?? "-"], ["Submitted", formatDocDate(c.submitted_at, inst)],
      ["Application fee", fee ? `${money(fee.amount)} · ${fee.reference}` : "-"]]);
    pdf.heading("Documents received");
    pdf.table(["Document", "File"], c.documents.filter((d) => d.filename).map((d) => [d.label, d.filename]), { serial: true });
    pdf.paragraph("This acknowledges that your application for the JUPEB programme has been received. It is not an offer of admission. "
      + "When the Directorate of ICT opens admission status checking, sign in to the JUPEB portal with your application number to check your status.");
    name = `jupeb-acknowledgement-${c.application_no}`;
  } else if (doc === "status") {
    if (!mayCheck || !c.statusChecking.status) return refuse("The admission status slip is issued once you have checked your admission status.");
    const st = ADMISSION_STATUS[c.statusChecking.status]?.[0] ?? c.statusChecking.status;
    const fee = paidRef("STATUS_CHECKING");
    pdf = paper("FORM", { title: "JUPEB admission status slip", reference: c.application_no, subtitle: `${c.session} academic session`, unit: "JUPEB Office" });
    pdf.keyValues([...who, ["Subject combination", comb], ["Admission status", st.toUpperCase()], ["Admission reference", c.admission_ref ?? "-"],
      ["Decided", formatDocDate(c.admission_decided_at, inst)], ["Status checking fee", fee ? `${money(fee.amount)} · ${fee.reference}` : "-"]]);
    if (c.statusChecking.status === "ADMITTED") pdf.paragraph("You are offered provisional admission. Pay the acceptance fee on the JUPEB portal to accept it; your acceptance letter is issued once the payment is confirmed, and school fees follow.");
    else if (c.admission_note) pdf.paragraph(c.admission_note);
    name = `jupeb-status-${c.application_no}`;
  } else if (doc === "letter") {
    if (!admitted || !mayCheck) return refuse("The admission letter is issued once you are admitted and have checked your admission status.");
    pdf = paper("LETTER", { title: "Offer of provisional admission: JUPEB programme", reference: c.admission_ref, subtitle: `${c.session} academic session`, unit: "JUPEB Office" });
    pdf.keyValues([["Name", fullName(c)], ["Application number", c.application_no], ["Admission reference", c.admission_ref ?? "-"], ["Date", formatDocDate(c.admission_decided_at, inst)]]);
    pdf.paragraph(`Dear ${c.first_name},`);
    pdf.paragraph(`I am pleased to inform you that you have been offered provisional admission into the Joint Universities Preliminary Examinations Board (JUPEB) programme of ${inst.name} for the ${c.session} academic session, as below.`);
    pdf.keyValues([["Programme", streamLabel(c.stream)], ["Duration", "One academic session"], ["Subject combination", c.combination_code ? comb : "Chosen at subject registration"]], 1);
    pdf.heading("Conditions");
    [
      "This offer is provisional and subject to the verification of your credentials. Should any of them be found false, the offer is withdrawn.",
      `Accept the offer by paying the acceptance fee of ${money(c.feeRule.acceptance_fee)} on the JUPEB portal; your acceptance letter is issued once the payment is confirmed.`,
      `Then pay the school fee. Your studentship is activated when ${c.feeRule.activation === "FULL" ? "the full school fee" : "the first semester's share"} is confirmed, after which you register your three subjects.`,
      c.screeningSetting.screening_required ? "Attend physical screening with the originals of every document you uploaded; school fees open once you are cleared." : "Bring the originals of every document you uploaded when the JUPEB Office asks for them.",
      "Your official JUPEB examination number is issued by the Board and shown on your portal once assigned.",
      "Admission into 200 level of a University programme after JUPEB depends on your JUPEB result and the University's direct-entry requirements.",
    ].forEach((t, i) => pdf.paragraph(`${i + 1}. ${t}`));
    pdf.paragraph("Congratulations.");
    pdf.signatures([{ designation: "Coordinator, JUPEB Office" }]);
    name = `jupeb-admission-letter-${c.application_no}`;
  } else if (doc === "acceptance") {
    const fee = paidRef("ACCEPTANCE");
    if (!c.accepted_at || !fee) return refuse("The acceptance letter is issued once the acceptance fee is confirmed.");
    pdf = paper("LETTER", { title: "Acceptance of the offer of admission: JUPEB programme", reference: c.admission_ref ?? c.application_no, subtitle: `${c.session} academic session`, unit: "JUPEB Office" });
    pdf.keyValues([["Name", fullName(c)], ["Application number", c.application_no], ["Admission reference", c.admission_ref ?? "-"], ["Date", formatDocDate(c.accepted_at, inst)]]);
    pdf.paragraph(`Dear ${c.first_name},`);
    pdf.paragraph(`This confirms that you have accepted the offer of provisional admission into the JUPEB programme of ${inst.name} for the ${c.session} academic session. The acceptance fee is confirmed as below.`);
    pdf.keyValues([["Programme", streamLabel(c.stream)], ["Subject combination", c.combination_code ? comb : "Chosen at subject registration"],
      ["Acceptance fee", money(fee.amount)], ["Payment reference", fee.reference], ["Confirmed", formatDocDate(fee.confirmed_at, inst)]], 1);
    pdf.heading("What follows");
    [
      c.screeningSetting.screening_required ? "Attend screening with the originals of your documents; the school fee opens once you are cleared." : "Pay the school fee on the JUPEB portal.",
      `Your studentship is activated when ${c.feeRule.activation === "FULL" ? "the full school fee" : "the first semester's share"} is confirmed; you then register your three subjects.`,
    ].forEach((t, i) => pdf.paragraph(`${i + 1}. ${t}`));
    pdf.signatures([{ designation: "Coordinator, JUPEB Office" }]);
    name = `jupeb-acceptance-letter-${c.application_no}`;
  } else if (doc === "invoice") {
    const f = c.fees;
    if (!f || (!office && !c.accepted_at)) return refuse("The school fees invoice is issued once your admission is accepted.");
    pdf = paper("FORM", { title: "JUPEB school fees invoice", reference: c.application_no, subtitle: `${c.session} academic session`, unit: "Bursary · JUPEB programme" });
    pdf.keyValues([...who, ["Category", `${feeCategoryLabel(f.category)} · ${f.indigene ? `${c.feeRule.indigene_state} indigene` : "non-indigene"}`], ["School fee", money(f.total)]]);
    pdf.table(["Instalment", "Amount", "Status"], [
      [`First semester (${Number(f.first_percent)}%)`, money(f.first_amount), f.first_paid || f.full_paid ? "PAID" : "UNPAID"],
      [`Second semester (${100 - Number(f.first_percent)}%)`, money(f.second_amount), f.second_paid || f.full_paid ? "PAID" : "UNPAID"],
    ], { serial: true });
    pdf.keyValues([["Paid to date", money(f.paid)], ["Outstanding", money(f.outstanding)]]);
    pdf.paragraph(`Pay on the JUPEB portal only; the amount is the Bursary's.${f.allow_full ? " The full school fee may be paid at once." : ""} A receipt is issued for each confirmed payment.`);
    name = `jupeb-invoice-${c.application_no}`;
  } else if (doc === "receipt") {
    const ref = (url.searchParams.get("ref") ?? "").toUpperCase();
    const r = c.references.find((x) => x.reference.toUpperCase() === ref && x.confirmed_at);
    if (!r) return refuse("A receipt is issued for a confirmed payment only.");
    pdf = paper("RECEIPT", { title: "Official payment receipt", reference: r.reference, subtitle: FEE_KIND[r.kind] ?? r.kind, unit: "Bursary · JUPEB programme" });
    pdf.keyValues([...who, ["Payment", FEE_KIND[r.kind] ?? r.kind], ["Reference", r.reference], ["Amount", money(r.amount)], ["Confirmed", formatDocDate(r.confirmed_at, inst)], ["Channel", r.channel ?? "-"],
      ["Semester", r.semester ? String(r.semester) : "-"], ["Status", "PAID"]]);
    if (r.kind.startsWith("SCHOOL_") && c.fees) {
      pdf.keyValues([["School fee", money(c.fees.total)], ["Paid to date", money(c.fees.paid)], ["Outstanding", money(c.fees.outstanding)], ["Category", `${feeCategoryLabel(c.fees.category)} · ${c.fees.indigene ? "indigene" : "non-indigene"}`]]);
    }
    pdf.paragraph("This receipt is generated from the University's confirmed record of the payment. The reference can be verified with the Bursary.");
    name = `jupeb-receipt-${r.reference}`;
  } else if (doc === "slip") {
    if (!c.subjects_registered_at) return refuse("The registration slip is issued once your three subjects are registered.");
    pdf = paper("FORM", { title: "JUPEB subject registration slip", reference: c.application_no, subtitle: `${c.session} academic session`, unit: "JUPEB Office" });
    pdf.keyValues([...who, ["Class", c.class_name ?? "-"], ["JUPEB examination number", c.exam_no ?? "Not yet assigned"], ["Registered", formatDocDate(c.subjects_registered_at, inst)], ["Combination", c.combination_code ?? "-"]]);
    pdf.table(["Code", "Subject"], c.registered.map((r) => [r.code, r.title]), { serial: true });
    pdf.signatures([{ designation: "Candidate" }, { designation: "JUPEB Office" }]);
    name = `jupeb-registration-slip-${c.application_no}`;
  } else if (doc === "result") {
    if (!c.resultsPublished && !office) return refuse("Results are shown once the JUPEB Office publishes them.");
    const gp = c.gradePoint;
    const year = c.screeningSetting.exam_month ?? c.session.slice(5);
    const examYear = (year.match(/[0-9]{4}/) ?? [c.session.slice(5)])[0];
    pdf = paper("RESULT", { title: "Statement of Result", subtitle: "Joint Universities Preliminary Examinations Board (JUPEB)", reference: c.exam_no ?? c.application_no,
      unit: "JUPEB Programme", watermark: c.resultsPublished ? null : "UNPUBLISHED" });
    pdf.keyValues([["Name", `${c.surname.toUpperCase()} ${c.first_name}${c.middle_name ? ` ${c.middle_name}` : ""}`], ["Examination number", c.exam_no ?? "-"],
      ["Examination year", year], ["Centre", inst.name]], 1);
    pdf.heading(`${examYear} JUPEB EXAM (A-Level Equivalent)`);
    pdf.table(["Subject", "Grade Letter", "Grade Point"], c.registered.map((r) => [r.title, r.grade ?? "-", r.points == null ? "-" : Number(r.points).toFixed(1)]), { serial: true, numeric: [false, false, true] });
    pdf.keyValues([["Grade Point", gp ? `${Number(gp.total)}/${gp.out_of}` : "-"]], 1);
    pdf.heading("Key to grades", 9.5);
    pdf.table(["Grade", "A", "B", "C", "D", "E", "F"], [["Grade point", "5", "4", "3", "2", "1", "0"]], { serial: false, size: 8.5 });
    pdf.paragraph("X = Absent; Q = Result cancelled; W = Result withheld. One point is added to the grade point of a candidate who passes all three subjects.", 8.5);
    pdf.paragraph("Any alteration to this statement renders it invalid. This statement reproduces the result the Board issued; the Board's certificate is authoritative.", 8.5);
    pdf.signatures([{ designation: "Authorized Signature (Programme Director or an officer designated by the University)" }]);
    const notes = c.registered.filter((r) => r.units && r.units.length);
    if (notes.length) {
      pdf.heading("Note", 9.5);
      notes.forEach((r) => pdf.paragraph(`${r.title}: ${(r.units ?? []).map((u) => `${u.code} ${u.title}`).join("; ")}.`, 8.5));
    }
    name = `jupeb-statement-of-result-${c.exam_no ?? c.application_no}`;
  } else if (doc === "summary") {
    pdf = paper("FORM", { title: "JUPEB application summary", reference: c.application_no, subtitle: `${c.session} academic session`, unit: "JUPEB Office" });
    pdf.heading("Biodata");
    pdf.keyValues([["Name", fullName(c)], ["Sex", c.sex === "F" ? "Female" : c.sex === "M" ? "Male" : "-"], ["Date of birth", formatDocDate(c.date_of_birth, inst)], ["NIN", c.nin ?? "-"],
      ["Email", c.email], ["Phone", c.phone ?? "-"], ["Nationality", c.nationality ?? "-"], ["State of origin", c.state_of_origin ?? "-"], ["LGA", c.lga ?? "-"], ["Home town", c.home_town ?? "-"],
      ["Contact address", c.contact_address ?? "-"], ["Next of kin", `${c.next_of_kin_name ?? "-"} ${c.next_of_kin_phone ? `(${c.next_of_kin_phone})` : ""}`]]);
    pdf.heading("Programme");
    pdf.keyValues([["Programme", streamLabel(c.stream)], ["Subject combination", c.combination_code ? comb : "Not chosen"]]);
    pdf.heading(`O'Level (${c.olevel_sittings === 2 ? "two sittings" : "one sitting"})`);
    pdf.table(["Sitting", "Examination", "Number", "Year", "Subject", "Grade"], c.olevel.map((o) => [o.sitting, o.exam_type, o.exam_number ?? "-", o.exam_year ?? "-", o.subject, o.grade]), { serial: true });
    pdf.heading("Documents");
    pdf.table(["Document", "File", "Status"], c.documents.map((d) => [d.label, d.filename ?? "Not uploaded", d.status ?? "-"]), { serial: true });
    name = `jupeb-application-${c.application_no}`;
  } else {
    return NextResponse.json({ status: 404, title: "No such JUPEB document" }, { status: 404 });
  }
  /* V343: the verification code, issued by the server for the record as it stands; its QR opens the public verifier. A paper the
     record does not support as verifiable (an unpublished statement printed by the office) carries none */
  const kind = PAPER[doc];
  if (kind) {
    const issued = await api<{ code: string }>(office ? `/api/v1/jupeb/office/applications/${c.id}/papers` : "/api/v1/jupeb/me/papers",
      { method: "POST", body: { kind, reference: doc === "receipt" ? url.searchParams.get("ref") : null } });
    if (issued.ok) {
      const h = req.headers;
      const host = h.get("x-forwarded-host") ?? h.get("host");
      const origin = host ? `${h.get("x-forwarded-proto") ?? "https"}://${host}` : url.origin;
      pdf.space(6);
      pdf.qr(qrMatrix(`${origin}/verify/jupeb/${issued.data.code}`), `Verify at ${origin}/verify/jupeb with the code ${issued.data.code}`, 64);
    }
  }
  const bytes = pdf.finish();
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${name.replace(/[^A-Za-z0-9._-]+/g, "-")}.pdf"`, "cache-control": "no-store" },
  });
}
