import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

export const dynamic = "force-dynamic";

interface PgMe {
  applicationNo: string; session: string; name: string; surname: string; otherNames: string;
  entryLevel: number; programme: string; award: string | null; faculty: string; department: string;
  state: string; acceptanceConfirmedAt: string | null;
}

const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const today = () => new Date().toISOString().slice(0, 10);
const DURATION: Record<number, string> = { 700: "3 SEMESTERS", 800: "4 SEMESTERS", 900: "6 SEMESTERS" };

const NOTES = [
  "This offer of admission is provisional; only candidates successful at the screening exercise will be registered.",
  "Successfully screened candidates are to proceed and pay the appropriate charges immediately to validate their admission.",
  "There shall be physical screening of certificates at the Postgraduate School.",
  "Should any problem be discovered with your credentials in the course of your study, you will be required to withdraw from the University.",
  "Bring the originals of all uploaded documents for screening.",
  "Congratulations on your admission.",
];

/** the confirmation of offer of admission — available once the applicant has paid the acceptance fee */
export async function GET() {
  const me = await api<PgMe>("/api/v1/pg/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const s = me.data;
  if (!s.acceptanceConfirmedAt && s.state !== "ACCEPTED" && s.state !== "ADMITTED") {
    return NextResponse.json({ status: 409, title: "Offer letter not available yet", detail: "Pay the acceptance fee to accept your offer, then download your offer of admission." }, { status: 409 });
  }

  const p = new Page();
  const L = 64;
  const cx = A4.w / 2;
  const crest = crestImage();
  let y = A4.h - 46;
  if (crest) p.jpeg(cx - 24, y - 46, 48, 48, crest);
  p.textCenter(cx, y - 60, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 13, true);
  p.textCenter(cx, y - 74, "P.M.B 102119, Makurdi, Nigeria", 9.5, false, [0.35, 0.35, 0.35]);
  p.textCenter(cx, y - 87, "(Office of the Registrar)", 9.5, false, [0.35, 0.35, 0.35]);
  y -= 108;
  p.text(A4.w - L - 150, y, "DATE: " + today(), 10, true);
  y -= 22;

  p.text(L, y, "APPLICANT’S NAME:", 10, true); p.text(L + 130, y, clean(`${s.surname}, ${s.otherNames}`), 10, false); y -= 18;
  p.text(L, y, "APPLICATION NUMBER:", 10, true); p.text(L + 150, y, clean(s.applicationNo), 10, false); y -= 26;

  p.textCenter(cx, y, "CONFIRMATION OF OFFER OF ADMISSION:", 11, true); y -= 15;
  p.textCenter(cx, y, `${clean(s.session)} ACADEMIC SESSION`, 11, true); y -= 24;

  y = p.paragraph(L, y, "I am pleased to confirm your offer of provisional admission into the Rev. Fr. Moses Orshio Adasu University, Makurdi, as approved by the Postgraduate School, as follows:", A4.w - 2 * L, 10, 1.4) - 8;

  const line = (k: string, v: string) => { p.text(L, y, k, 10.5, true); p.text(L + 130, y, clean(v), 10.5, true); y -= 17; };
  line("COURSE:", `${s.programme}${s.award ? ` (${s.award})` : ""}`);
  line("PROGRAMME:", "POSTGRADUATE");
  line("FACULTY:", s.faculty);
  line("LEVEL:", `${s.entryLevel} LEVEL`);
  line("DURATION:", DURATION[s.entryLevel] ?? "—");
  y -= 8;

  NOTES.forEach((t, i) => {
    p.text(L, y, `${i + 1}.`, 9.5, true);
    y = p.paragraph(L + 16, y, t, A4.w - 2 * L - 16, 9.5, 1.35) - 4;
  });

  y -= 26;
  p.text(L, y, "Ajuma Isaac Ugbabe", 10.5, true); y -= 13;
  p.text(L, y, "Secretary, Postgraduate School", 9.5, false, [0.35, 0.35, 0.35]);

  // a small verification QR (the application number), bottom-right
  const { size, dark } = qrMatrix(`MOAUM PG ${s.applicationNo}`);
  const cell = 1.7, qDim = size * cell, qx = A4.w - L - qDim, qy = y + 6;
  for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (dark[rr * size + cc]) p.fill(qx + cc * cell, qy + qDim - (rr + 1) * cell, cell, cell, 0);

  p.text(L, 40, `${clean(s.name)} · ${s.applicationNo} · generated ${today()}`, 7.5, false, [0.5, 0.5, 0.5]);

  const bytes = pdf([p], `Offer of admission ${s.applicationNo}`);
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="offer-of-admission-${s.applicationNo.replace(/\//g, "-")}.pdf"` },
  });
}
