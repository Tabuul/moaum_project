import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { qrMatrix } from "@/lib/qr";
import { publicOrigin } from "@/lib/public-origin";
import { loadInstitution } from "@/lib/document/institution-server";
import { formatDocDate, formatDocDateTime } from "@/lib/document/institution";
import { PdfDocument } from "@/lib/document/pdf";
import { naira, num, type IutView } from "@/lib/transfer-application";

export const dynamic = "force-dynamic";

/** what GET /api/v1/transfer-applications/me/acknowledgement answers, from SUBMITTED onwards */
interface Acknowledgement {
  applicationNo: string; session: string; submittedAt?: string | null; lastSubmittedAt?: string | null;
  applicant?: IutView["applicant"]; previous?: IutView["previous"]; applied?: IutView["applied"];
  documents?: { label: string; filename: string }[];
  fee?: { basis?: string | null; receiptNo?: string | null; amount?: number | string | null } | null;
  checkCode: string; verifyPath: string;
}

const v = (x: string | number | null | undefined) => (x === null || x === undefined || x === "" ? "-" : String(x));

/** V766: the acknowledgement of a submitted inter-university transfer application, on the University's document writer: who applied,
 *  from where, for what, the documents sent and the fee, under the declaration made at submission, with a QR that opens the public
 *  verification page (/verify/transfer-application/…), whose code the API signed. It attests the submission only — never a decision. */
export async function GET(req: Request) {
  const inst = await loadInstitution();
  const download = new URL(req.url).searchParams.get("download") === "1";
  const r = await api<Acknowledgement>("/api/v1/transfer-applications/me/acknowledgement");
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const a = r.data;
  const ap = a.applicant ?? {}, pr = a.previous ?? {}, ad = a.applied ?? {};
  const name = `${(ap.surname ?? "").toUpperCase()}, ${ap.otherNames ?? ""}`;
  const pdf = new PdfDocument("FORM", {
    title: "Inter-university transfer application: acknowledgement", subtitle: `${a.session} academic session`, reference: a.applicationNo,
    unit: "Office of the Registrar, Admissions",
    meta: [["Application number", a.applicationNo], ["Session", a.session], ["Submitted", a.submittedAt ? formatDocDateTime(a.submittedAt, inst) : "-"]],
  }, inst);
  pdf.space(8);
  pdf.heading("Applicant");
  pdf.keyValues([["Name", name], ["Sex", ap.sex === "F" ? "Female" : ap.sex === "M" ? "Male" : "-"], ["Date of birth", ap.dateOfBirth ? formatDocDate(ap.dateOfBirth, inst) : "-"],
    ["JAMB registration number", v(ap.jambRegNo)], ["E-mail", v(ap.email)], ["Phone", v(ap.phone)]]);
  pdf.heading("Present university");
  pdf.keyValues([["University", v(pr.universityName ?? pr.universityNamed)], ["Matriculation number", v(pr.matricNo)], ["Programme", v(pr.programme)],
    ["Level", pr.level ? `${pr.level} Level` : "-"], ["Session entered", v(pr.entrySession)],
    ["CGPA", pr.cgpa != null && pr.cgpa !== "" ? `${num(pr.cgpa).toFixed(2)} of ${pr.cgpaScale ?? 5}` : "-"]]);
  pdf.heading("Applied for");
  pdf.keyValues([["Programme", v(ad.programmeName ?? ad.programme)], ["Level", ad.level ? `${ad.level} Level` : "-"], ["Department", v(ad.deptName ?? ad.dept)],
    ["Faculty", v(ad.facultyName ?? ad.faculty)]]);
  pdf.heading("Documents sent");
  pdf.table(["Document", "File"], (a.documents ?? []).map((d) => [d.label, d.filename]), { serial: true });
  pdf.heading("Application fee");
  pdf.keyValues([["Fee", a.fee?.basis === "NONE_DUE" ? "None due" : a.fee?.amount != null ? naira(a.fee.amount).replace("₦", "NGN ") : "-"], ["Receipt", v(a.fee?.receiptNo)]]);
  pdf.heading("Declaration");
  pdf.paragraph("I declared, on submitting, that the particulars and documents I have given are true, and that a false one ends this application and any admission it leads to.");
  pdf.paragraph(`This acknowledges that the application above was submitted${a.lastSubmittedAt && a.lastSubmittedAt !== a.submittedAt ? ` (last on ${formatDocDateTime(a.lastSubmittedAt, inst)})` : ""}. It is not an offer of admission: the Registry checks the documents, the Head of Department of the programme assesses the application, and the applicant is told the decision by e-mail and on the portal.`, 9);
  pdf.qr(qrMatrix(`${publicOrigin(req)}${a.verifyPath}`), `Application ${a.applicationNo} · check code ${a.checkCode}`);
  const bytes = pdf.finish();
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: {
    "content-type": "application/pdf", "cache-control": "no-store",
    "content-disposition": `${download ? "attachment" : "inline"}; filename="transfer-acknowledgement-${a.applicationNo.replace(/[^A-Za-z0-9]+/g, "-")}.pdf"`,
  } });
}
