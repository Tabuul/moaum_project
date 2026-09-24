import { api } from "@/lib/api";
import { semesterName } from "@/lib/student-portal";

export const dynamic = "force-dynamic";

interface Row { course_code: string; title: string; units: number; total: number | null; grade: string | null; points: number | null; outcome: string | null }
interface ResultVerify {
  genuine: boolean; name?: string; matricNo?: string | null; programme?: string | null; level?: number;
  session?: string; semester?: number; gpa?: number | null; cgpa?: number | null; standing?: string | null;
  approvedOn?: string | null; senateMinute?: string | null; rows?: Row[];
}

/** /verify/results?m=&s=&sem=&c= — the public verification of a semester results statement.
 *  It shows the University's own record: the published grades, the GPA/CGPA, the class of standing
 *  and the Senate approval date, so an altered statement is exposed. Public. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const g = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  const m = g("m"), s = g("s"), sem = g("sem") || "1", c = g("c");
  const r = await api<ResultVerify>(`/api/v1/verify/results?matric=${encodeURIComponent(m)}&session=${encodeURIComponent(s)}&semester=${encodeURIComponent(sem)}&c=${encodeURIComponent(c)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const approved = v.approvedOn ? new Date(v.approvedOn).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—";
  const scoreOf = (row: Row) => row.outcome === "GRADED" ? (row.total == null ? "—" : String(row.total)) : (row.outcome ? row.outcome.charAt(0) + row.outcome.slice(1).toLowerCase() : "—");

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "40px 16px", fontFamily: "var(--sans)", color: "var(--ink)" }}>
      <div style={{ width: "100%", maxWidth: 620, background: "#fff", border: "1px solid var(--line)", borderRadius: 14, overflow: "hidden", boxShadow: "0 1px 3px rgba(20,39,58,.08)" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "16px 20px", borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div>
            <div style={{ fontSize: 11, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--amber)", fontWeight: 700 }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "var(--chrome)" }}>Semester results verification</div>
          </div>
        </div>

        <div style={{ padding: 20 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "12px 14px", borderRadius: 10, marginBottom: 16,
            background: ok ? "var(--green-bg)" : "var(--red-bg)", border: `1px solid ${ok ? "var(--green-line)" : "var(--red-line)"}`, color: ok ? "var(--green-ink)" : "var(--red-deep)" }}>
            <span style={{ fontSize: 22 }}>{ok ? "✓" : "✕"}</span>
            <div>
              <div className="b700 t-md">{ok ? "Genuine statement — this is the University's record" : "Not verified"}</div>
              <div style={{ fontSize: 12.5 }}>{ok
                ? "Check that the grades, GPA and approval date below match the statement in hand."
                : "No published statement matches this code. Treat the statement as not genuine."}</div>
            </div>
          </div>

          {ok ? (
            <>
              <div style={{ marginBottom: 16 }}>
                {[["Name", v.name], ["Matriculation number", v.matricNo ?? "—"], ["Programme", v.programme ?? "—"],
                  ["Level", v.level ? `${v.level} Level` : "—"], ["Session", v.session ?? "—"], ["Semester", v.semester ? semesterName(v.semester) : "—"],
                  ["Semester GPA", v.gpa != null ? String(v.gpa) : "—"], ["Cumulative GPA", v.cgpa != null ? String(v.cgpa) : "—"],
                  ["Class of standing", v.standing ?? "—"], ["Approved by Senate on", v.senateMinute ? `${approved} · minute ${v.senateMinute}` : approved]].map(([k, val], i) => (
                  <div key={i} style={{ display: "flex", justifyContent: "space-between", gap: 12, padding: "6px 0", borderBottom: "1px solid var(--line-2)", fontSize: 13.5 }}>
                    <span style={{ color: "var(--muted)", fontSize: 12, textTransform: "uppercase", letterSpacing: ".04em" }}>{k}</span>
                    <span style={{ fontWeight: k === "Name" ? 700 : 500, textAlign: "right" }}>{val}</span>
                  </div>
                ))}
              </div>
              <div style={{ fontSize: 12, fontWeight: 700, color: "var(--muted)", textTransform: "uppercase", letterSpacing: ".04em", margin: "4px 0 6px" }}>Published grades</div>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13.5 }}>
                <tbody>
                  {(v.rows ?? []).map((row, i) => (
                    <tr key={i} style={{ borderBottom: "1px solid var(--line-2)" }}>
                      <td style={{ padding: "7px 8px 7px 0", fontWeight: 600, whiteSpace: "nowrap" }}>{row.course_code}</td>
                      <td style={{ padding: "7px 0" }}>{row.title}</td>
                      <td style={{ padding: "7px 8px", textAlign: "right", color: "var(--muted)", whiteSpace: "nowrap" }}>{row.units}u</td>
                      <td style={{ padding: "7px 8px", textAlign: "right", whiteSpace: "nowrap" }}>{scoreOf(row)}</td>
                      <td style={{ padding: "7px 0", textAlign: "right", fontWeight: 700, whiteSpace: "nowrap", color: row.grade === "F" ? "#b71c1c" : undefined }}>{row.grade ?? "—"}</td>
                    </tr>
                  ))}
                  {!(v.rows ?? []).length ? <tr><td style={{ padding: "7px 0", color: "var(--faint)" }}>No published result on record for this semester.</td></tr> : null}
                </tbody>
              </table>
            </>
          ) : null}

          <p style={{ fontSize: 11.5, color: "var(--faint)", marginTop: 18, lineHeight: 1.5 }}>
            This page reads the University&rsquo;s register directly. The statement is a view of the register, not the register
            itself; where the printed grades, GPA or approval date differ from what is shown here, the record here is the
            truth. A grade that is not on a published sheet is not shown. Verified {new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.
          </p>
        </div>
      </div>
    </div>
  );
}
