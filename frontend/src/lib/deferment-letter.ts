/** The official Deferment Approval Letter (V259), drawn with the portal's PDF writer: the crest, the reference, the
 *  student and their programme, the period deferred, the expected return, the approving officer, and a QR that
 *  names the reference. One function, used by the student's copy and the desk's. */
import { A4, Page, pdf } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";
import type { DefermentFull } from "@/lib/deferments";
import { SEM } from "@/lib/deferments";

const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }) : "");

export function defermentLetter(d: DefermentFull, verifyUrl: string): Uint8Array {
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
  p.text(A4.w - L - 170, y, "DATE: " + day(d.decided_at ?? new Date().toISOString()), 10, true);
  p.text(L, y, "REF: " + clean(d.reference), 10, true);
  y -= 30;
  p.textCenter(cx, y, "DEFERMENT APPROVAL LETTER", 12.5, true); y -= 16;
  p.textCenter(cx, y, d.kind === "SESSION" ? `${clean(d.session)} ACADEMIC SESSION` : `${clean(d.session)} ACADEMIC SESSION - ${SEM(d.semester).toUpperCase()}`, 10.5, true); y -= 26;

  const line = (k: string, v: string) => { p.text(L, y, k, 10.5, true); p.text(L + 150, y, clean(v), 10.5, false); y -= 17; };
  line("STUDENT:", `${d.surname}, ${d.other_names}`);
  line("STUDENT ID:", d.number);
  line("PROGRAMME:", d.programme);
  line("DEPARTMENT:", d.department);
  line("FACULTY:", d.faculty);
  line("LEVEL:", `${d.level} Level`);
  y -= 8;
  y = p.paragraph(L, y, `The University has considered your request to defer ${d.kind === "SESSION" ? `the ${d.session} academic session` : `the ${SEM(d.semester).toLowerCase()} of the ${d.session} academic session`} on ${d.reason.toLowerCase()} grounds, recommended by your department and faculty, and approves it as follows:`, A4.w - 2 * L, 10, 1.45) - 8;
  line("DEFERMENT TYPE:", d.kind === "SESSION" ? "Academic session" : "Semester");
  line("PERIOD DEFERRED:", d.kind === "SESSION" ? `${d.session} academic session` : `${d.session}, ${SEM(d.semester)}`);
  line("EFFECTIVE FROM:", day(d.period_from) || d.session);
  line("EXPECTED RETURN:", `${d.return_session ?? ""}, ${SEM(d.return_semester)}${d.return_on ? ` (${day(d.return_on)})` : ""}`);
  line("APPROVED ON:", day(d.decided_at));
  line("APPROVED BY:", d.decided_officer ? `${d.decided_officer}, Office of the Registrar` : "Office of the Registrar");
  if (d.decision_note) line("REMARKS:", d.decision_note);
  y -= 8;
  const notes = [
    "During the deferred period you are not academically active and may not register courses, sit examinations or be assessed for that period.",
    "Your registrations, payments, results and academic history for other periods remain on your record unchanged.",
    "Present yourself at your department at the start of your return period; the department confirms your return and your record is reactivated for registration and fees as usual.",
    "The University may verify this letter by its reference on the portal.",
  ];
  notes.forEach((n, i) => { y = p.paragraph(L, y, `${i + 1}. ${n}`, A4.w - 2 * L, 9.5, 1.4) - 4; });
  y -= 24;
  p.text(L, y, "______________________________", 10); y -= 14;
  p.text(L, y, "Registrar", 10, true); y -= 13;
  p.text(L, y, "For: Rev. Fr. Moses Orshio Adasu University, Makurdi", 9.5, false, [0.35, 0.35, 0.35]);

  const qr = qrMatrix(verifyUrl);
  const cell = 2.2, size = qr.size * cell, qx = A4.w - L - size, qy = 60;
  for (let r = 0; r < qr.size; r++) for (let c = 0; c < qr.size; c++) if (qr.dark[r * qr.size + c]) p.fill(qx + c * cell, qy + (qr.size - 1 - r) * cell, cell, cell, 0);
  p.text(L, 46, `Verify: ${clean(verifyUrl)}`, 8, false, [0.4, 0.4, 0.4]);
  p.text(L, 36, `Deferment ${clean(d.reference)} · generated ${day(new Date().toISOString())}`, 8, false, [0.4, 0.4, 0.4]);
  return pdf([p], `Deferment ${d.reference}`);
}
