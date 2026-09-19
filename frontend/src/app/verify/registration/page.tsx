import { api } from "@/lib/api";
import { semesterName } from "@/lib/student-portal";

export const dynamic = "force-dynamic";

interface Course { course_code: string; title: string; units: number; entry_type: string; kind?: string }
interface RegVerify {
  genuine: boolean; name?: string; matricNo?: string | null; programme?: string | null; level?: number;
  session?: string; semester?: number; status?: string; approvedOn?: string | null; units?: number; courses?: Course[];
}

/** the academic type shown: GST, Elective or Core (Compulsory/Required → Core), Carryover flagged */
function courseType(co: Course): string {
  if ((co.entry_type ?? "").toUpperCase() === "CARRYOVER") return "Carryover";
  const k = (co.kind ?? "").toLowerCase();
  if (k === "gst") return "GST";
  if (k === "elective") return "Elective";
  if (k === "compulsory" || k === "required") return "Core";
  const t = (co.entry_type ?? "").toUpperCase();
  return t === "GST" ? "GST" : t === "ELECTIVE" ? "Elective" : "Core";
}

/** /verify/registration?m=&s=&sem=&c= — the public verification of a course registration form.
 *  It shows the University's own record: the student, the approved courses, the units and the
 *  approval date, so a forged or altered form is exposed. Public. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const g = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  const m = g("m"), s = g("s"), sem = g("sem") || "1", c = g("c");
  const r = await api<RegVerify>(`/api/v1/verify/registration?matric=${encodeURIComponent(m)}&session=${encodeURIComponent(s)}&semester=${encodeURIComponent(sem)}&c=${encodeURIComponent(c)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const approved = v.approvedOn ? new Date(v.approvedOn).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—";

  return (
    <div style={{ minHeight: "100vh", background: "#f6f3ea", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "40px 16px", fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif", color: "#16273a" }}>
      <div style={{ width: "100%", maxWidth: 600, background: "#fff", border: "1px solid #e4ddcd", borderRadius: 14, overflow: "hidden", boxShadow: "0 1px 3px rgba(20,39,58,.08)" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "16px 20px", borderBottom: "2px solid #0e3f55" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div>
            <div style={{ fontSize: 11, letterSpacing: ".14em", textTransform: "uppercase", color: "#b0842e", fontWeight: 700 }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "#0e3f55" }}>Course registration verification</div>
          </div>
        </div>

        <div style={{ padding: 20 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "12px 14px", borderRadius: 10, marginBottom: 16,
            background: ok ? "#e6f0e8" : "#f5e9ef", border: `1px solid ${ok ? "#c4ddca" : "#e2c6d3"}`, color: ok ? "#2f6b45" : "#7a3b52" }}>
            <span style={{ fontSize: 22 }}>{ok ? "✓" : "✕"}</span>
            <div>
              <div style={{ fontWeight: 700, fontSize: 15 }}>{ok ? "Genuine form — this is the University's record" : "Not verified"}</div>
              <div style={{ fontSize: 12.5 }}>{ok
                ? "Check that the courses, units and approval date below match the form in hand."
                : "No approved registration matches this code. Treat the form as not genuine."}</div>
            </div>
          </div>

          {ok ? (
            <>
              <div style={{ marginBottom: 16 }}>
                {[["Name", v.name], ["Matriculation number", v.matricNo ?? "—"], ["Programme", v.programme ?? "—"],
                  ["Level", v.level ? `${v.level} Level` : "—"], ["Session", v.session ?? "—"], ["Semester", v.semester ? semesterName(v.semester) : "—"],
                  ["Total credit units", v.units != null ? String(v.units) : "—"], ["Approved on", approved]].map(([k, val], i) => (
                  <div key={i} style={{ display: "flex", justifyContent: "space-between", gap: 12, padding: "6px 0", borderBottom: "1px solid #eef1f4", fontSize: 13.5 }}>
                    <span style={{ color: "#5d6b79", fontSize: 12, textTransform: "uppercase", letterSpacing: ".04em" }}>{k}</span>
                    <span style={{ fontWeight: k === "Name" ? 700 : 500, textAlign: "right" }}>{val}</span>
                  </div>
                ))}
              </div>
              <div style={{ fontSize: 12, fontWeight: 700, color: "#5d6b79", textTransform: "uppercase", letterSpacing: ".04em", margin: "4px 0 6px" }}>Registered courses</div>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13.5 }}>
                <tbody>
                  {(v.courses ?? []).map((co, i) => (
                    <tr key={i} style={{ borderBottom: "1px solid #eef1f4" }}>
                      <td style={{ padding: "7px 8px 7px 0", fontWeight: 600, whiteSpace: "nowrap" }}>{co.course_code}</td>
                      <td style={{ padding: "7px 0" }}>{co.title}</td>
                      <td style={{ padding: "7px 8px", textAlign: "right", color: "#5d6b79", whiteSpace: "nowrap" }}>{co.units}u</td>
                      <td style={{ padding: "7px 0", textAlign: "right", color: "#5d6b79", whiteSpace: "nowrap" }}>{courseType(co)}</td>
                    </tr>
                  ))}
                  {!(v.courses ?? []).length ? <tr><td style={{ padding: "7px 0", color: "#8a97a3" }}>No approved courses on record for this semester.</td></tr> : null}
                </tbody>
              </table>
            </>
          ) : null}

          <p style={{ fontSize: 11.5, color: "#8a97a3", marginTop: 18, lineHeight: 1.5 }}>
            This page reads the University&rsquo;s register directly. The form is a view of the register, not the register
            itself; where the printed courses, units or approval date differ from what is shown here, the record here is the
            truth. Verified {new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.
          </p>
        </div>
      </div>
    </div>
  );
}
