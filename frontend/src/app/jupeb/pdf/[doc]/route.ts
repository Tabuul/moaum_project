import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { loadInstitution } from "@/lib/document/institution-server";
import { PdfDocument } from "@/lib/document/pdf";
import { formatDocDate } from "@/lib/document/institution";
import { FEE_KIND, fullName, type Candidate } from "@/lib/jupeb";

export const dynamic = "force-dynamic";

const money = (n: number | string | null | undefined) => (n == null ? "-" : "NGN " + Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 }));

/**
 * A JUPEB candidate's papers (V339), on the University's document writer: the admission letter, a payment receipt, the
 * registration slip, the statement of result and the application summary. The candidate reads their own (/api/v1/jupeb/me);
 * the JUPEB Office prints any candidate's with ?id= (its own endpoint decides who may). Each paper is issued only once the
 * record supports it: a letter after admission, a receipt for a confirmed payment, a slip after registration, a statement
 * after publication.
 */
export async function GET(req: Request, { params }: { params: Promise<{ doc: string }> }) {
  const { doc } = await params;
  const url = new URL(req.url);
  const id = url.searchParams.get("id");
  const inst = await loadInstitution();
  const res = await api<Candidate>(id && /^[0-9a-f-]{36}$/i.test(id) ? `/api/v1/jupeb/office/applications/${id}` : "/api/v1/jupeb/me");
  if (!res.ok) return NextResponse.json(res.problem, { status: res.problem.status });
  const c = res.data;
  const admitted = ["ADMITTED", "STUDENT", "COMPLETED"].includes(c.state);
  const refuse = (title: string) => NextResponse.json({ status: 409, title }, { status: 409 });
  const who: [string, string][] = [["Name", fullName(c)], ["Application number", c.application_no], ["Session", c.session], ["Combination", c.combination_code ?? "-"]];
  let pdf: PdfDocument;
  let name: string;
  const begin = (d: PdfDocument) => { d.space(8); return d; };

  if (doc === "letter") {
    if (!admitted) return refuse("The admission letter is issued once you are admitted.");
    pdf = begin(new PdfDocument("LETTER", { title: "Offer of provisional admission: JUPEB programme", reference: c.admission_ref, subtitle: `${c.session} academic session`, unit: "JUPEB Office" }, inst));
    pdf.keyValues([["Name", fullName(c)], ["Application number", c.application_no], ["Admission reference", c.admission_ref ?? "-"], ["Date", formatDocDate(c.admission_decided_at, inst)]]);
    pdf.paragraph(`Dear ${c.first_name},`);
    pdf.paragraph(`I am pleased to inform you that you have been offered provisional admission into the Joint Universities Preliminary Examinations Board (JUPEB) programme of ${inst.name} for the ${c.session} academic session, in the subject combination below.`);
    pdf.keyValues([["Combination", `${c.combination_code ?? ""}: ${c.subjects.map((s) => s.title).join(", ")}`], ["Programme of interest", c.programme_name ?? "-"], ["Faculty", c.faculty_name ?? "-"], ["Duration", "One academic session"]], 1);
    pdf.heading("Conditions");
    [
      "This offer is provisional and subject to the verification of your credentials. Should any of them be found false, the offer is withdrawn.",
      `Pay the school fee on the JUPEB portal. Your studentship is activated when ${c.feeRule.activation === "FULL" ? "the full school fee" : "the first semester's share"} is confirmed, after which you register your three subjects.`,
      c.screeningSetting.screening_required ? "Attend physical screening with the originals of every document you uploaded; school fees open once you are cleared." : "Bring the originals of every document you uploaded when the JUPEB Office asks for them.",
      "Your official JUPEB examination number is issued by the Board and shown on your portal once assigned.",
      "Admission into 200 level of your programme of interest after JUPEB depends on your JUPEB result and the University's direct-entry requirements.",
    ].forEach((t, i) => pdf.paragraph(`${i + 1}. ${t}`));
    pdf.paragraph("Congratulations.");
    pdf.signatures([{ designation: "Coordinator, JUPEB Office" }]);
    name = `jupeb-admission-letter-${c.application_no}`;
  } else if (doc === "receipt") {
    const ref = (url.searchParams.get("ref") ?? "").toUpperCase();
    const r = c.references.find((x) => x.reference.toUpperCase() === ref && x.confirmed_at);
    if (!r) return refuse("A receipt is issued for a confirmed payment only.");
    pdf = begin(new PdfDocument("RECEIPT", { title: "Official payment receipt", reference: r.reference, subtitle: FEE_KIND[r.kind] ?? r.kind, unit: "Bursary · JUPEB programme" }, inst));
    pdf.keyValues([...who, ["Payment", FEE_KIND[r.kind] ?? r.kind], ["Reference", r.reference], ["Amount", money(r.amount)], ["Confirmed", formatDocDate(r.confirmed_at, inst)], ["Channel", r.channel ?? "-"],
      ["Semester", r.semester ? String(r.semester) : "-"], ["Status", "PAID"]]);
    if (r.kind !== "APPLICATION") {
      pdf.keyValues([["School fee", money(c.fees.total)], ["Paid to date", money(c.fees.paid)], ["Outstanding", money(c.fees.outstanding)], ["Category", `${c.fees.category} · ${c.fees.indigene ? "indigene" : "non-indigene"}`]]);
    }
    pdf.paragraph("This receipt is generated from the University's confirmed record of the payment. The reference can be verified with the Bursary.");
    name = `jupeb-receipt-${r.reference}`;
  } else if (doc === "slip") {
    if (!c.subjects_registered_at) return refuse("The registration slip is issued once your three subjects are registered.");
    pdf = begin(new PdfDocument("FORM", { title: "JUPEB subject registration slip", reference: c.application_no, subtitle: `${c.session} academic session`, unit: "JUPEB Office" }, inst));
    pdf.keyValues([...who, ["Class", c.class_name ?? "-"], ["JUPEB examination number", c.exam_no ?? "Not yet assigned"], ["Registered", formatDocDate(c.subjects_registered_at, inst)], ["Programme of interest", c.programme_name ?? "-"]]);
    pdf.table(["Code", "Subject"], c.registered.map((r) => [r.code, r.title]), { serial: true });
    pdf.signatures([{ designation: "Candidate" }, { designation: "JUPEB Office" }]);
    name = `jupeb-registration-slip-${c.application_no}`;
  } else if (doc === "result") {
    if (!c.resultsPublished && !id) return refuse("Results are shown once the JUPEB Office publishes them.");
    pdf = begin(new PdfDocument("RESULT", { title: "JUPEB statement of result", reference: c.exam_no ?? c.application_no, subtitle: `${c.session} academic session`, unit: "JUPEB Office", watermark: c.resultsPublished ? null : "UNPUBLISHED" }, inst));
    pdf.keyValues([...who, ["JUPEB examination number", c.exam_no ?? "-"], ["Programme of interest", c.programme_name ?? "-"]]);
    pdf.table(["Code", "Subject", "Grade", "Points"], c.registered.map((r) => [r.code, r.title, r.grade ?? "-", r.points ?? "-"]), { serial: true });
    pdf.keyValues([["Total points", String(c.registered.reduce((n, r) => n + Number(r.points ?? 0), 0))]], 1);
    pdf.paragraph("Grades: A = 5, B = 4, C = 3, D = 2, E = 1, F = 0 points. This statement reproduces the result the Board issued; the Board's own certificate is authoritative.");
    name = `jupeb-result-${c.exam_no ?? c.application_no}`;
  } else if (doc === "summary") {
    pdf = begin(new PdfDocument("FORM", { title: "JUPEB application summary", reference: c.application_no, subtitle: `${c.session} academic session`, unit: "JUPEB Office" }, inst));
    pdf.heading("Biodata");
    pdf.keyValues([["Name", fullName(c)], ["Sex", c.sex === "F" ? "Female" : c.sex === "M" ? "Male" : "-"], ["Date of birth", formatDocDate(c.date_of_birth, inst)], ["NIN", c.nin ?? "-"],
      ["Email", c.email], ["Phone", c.phone ?? "-"], ["Nationality", c.nationality ?? "-"], ["State of origin", c.state_of_origin ?? "-"], ["LGA", c.lga ?? "-"], ["Home town", c.home_town ?? "-"],
      ["Contact address", c.contact_address ?? "-"], ["Next of kin", `${c.next_of_kin_name ?? "-"} ${c.next_of_kin_phone ? `(${c.next_of_kin_phone})` : ""}`]]);
    pdf.heading("Programme and combination");
    pdf.keyValues([["Programme of interest", c.programme_name ?? "-"], ["Faculty", c.faculty_name ?? "-"], ["Combination", c.combination_code ?? "-"], ["Subjects", c.subjects.map((s) => s.title).join(", ")]]);
    pdf.heading("O'Level");
    pdf.table(["Sitting", "Examination", "Year", "Subject", "Grade"], c.olevel.map((o) => [o.sitting, o.exam_type, o.exam_year ?? "-", o.subject, o.grade]), { serial: true });
    pdf.heading("Documents");
    pdf.table(["Document", "File", "Status"], c.documents.map((d) => [d.label, d.filename ?? "Not uploaded", d.status ?? "-"]), { serial: true });
    name = `jupeb-application-${c.application_no}`;
  } else {
    return NextResponse.json({ status: 404, title: "No such JUPEB document" }, { status: 404 });
  }
  const bytes = pdf.finish();
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${name.replace(/[^A-Za-z0-9._-]+/g, "-")}.pdf"`, "cache-control": "no-store" },
  });
}
