import { api } from "@/lib/api";
import { semesterName } from "@/lib/student-portal";

export const dynamic = "force-dynamic";

interface Course { course_code: string; title: string; units: number; entry_type: string }
interface ExamVerify {
  genuine: boolean; name?: string; matricNo?: string | null; programme?: string | null; level?: number;
  session?: string; semester?: number; cleared?: boolean | null; photo?: string | null; courses?: Course[];
}

/** /verify/exam?m=&s=&sem=&c= — the public verification of a student's examination card.
 *  It shows the University's own record: the name, PHOTO (checked against the face at the hall) and
 *  the courses, so a cloned or altered card is exposed. Public. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const g = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  const m = g("m"), s = g("s"), sem = g("sem") || "1", c = g("c");
  const r = await api<ExamVerify>(`/api/v1/verify/exam?matric=${encodeURIComponent(m)}&session=${encodeURIComponent(s)}&semester=${encodeURIComponent(sem)}&c=${encodeURIComponent(c)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;

  return (
    <div style={{ minHeight: "100vh", background: "#f6f3ea", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "20px 12px", fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif", color: "#16273a" }}>
      <div style={{ width: "100%", maxWidth: 600, background: "#fff", border: "1px solid #e4ddcd", borderRadius: 14, overflow: "hidden", boxShadow: "0 1px 3px rgba(20,39,58,.08)" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "14px 16px", borderBottom: "2px solid #0e3f55" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div>
            <div style={{ fontSize: 11, letterSpacing: ".14em", textTransform: "uppercase", color: "#b0842e", fontWeight: 700 }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "#0e3f55" }}>Examination card verification</div>
          </div>
        </div>

        <div style={{ padding: 16 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "12px 14px", borderRadius: 10, marginBottom: 16,
            background: ok ? "#e6f0e8" : "#f5e9ef", border: `1px solid ${ok ? "#c4ddca" : "#e2c6d3"}`, color: ok ? "#2f6b45" : "#7a3b52" }}>
            <span style={{ fontSize: 22 }}>{ok ? "✓" : "✕"}</span>
            <div>
              <div style={{ fontWeight: 700, fontSize: 15 }}>{ok ? "Genuine card — this is the University's record" : "Not verified"}</div>
              <div style={{ fontSize: 12.5 }}>{ok
                ? "Check that the face below matches the candidate, and the courses match the card in hand."
                : "No examination card matches this code. Treat the card as not genuine, and refuse admission."}</div>
            </div>
          </div>

          {ok ? (
            <>
              {/* identity sits beside the photo so the photo's right side is not wasted on a phone */}
              <div style={{ display: "flex", gap: 12, alignItems: "flex-start", marginBottom: 14 }}>
                {v.photo ? (
                  /* eslint-disable-next-line @next/next/no-img-element */
                  <img src={v.photo} alt="Candidate photograph" style={{ width: 76, height: 92, objectFit: "cover", border: "1px solid #e4ddcd", borderRadius: 4, flexShrink: 0 }} />
                ) : <div style={{ width: 76, height: 92, border: "1px dashed #c3c3c3", borderRadius: 4, display: "flex", alignItems: "center", justifyContent: "center", color: "#9aa", fontSize: 11, flexShrink: 0 }}>No photo</div>}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 16, fontWeight: 700, lineHeight: 1.25 }}>{v.name}</div>
                  <div style={{ fontSize: 13, marginTop: 3, fontVariantNumeric: "tabular-nums", overflowWrap: "anywhere" }}>{v.matricNo ?? "—"}</div>
                  <div style={{ fontSize: 12.5, color: "#5d6b79", marginTop: 3 }}>{v.programme ?? "—"}</div>
                  <div style={{ fontSize: 12.5, color: "#5d6b79", marginTop: 2 }}>{v.level ? `${v.level} Level` : "—"}</div>
                </div>
              </div>
              {/* short facts as compact cells — two or three to a row, never a stretched full-width line */}
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(110px, 1fr))", gap: 8, marginBottom: 16 }}>
                {([["Session", v.session ?? "—"], ["Semester", v.semester ? semesterName(v.semester) : "—"], ["Cleared", v.cleared ? "Yes" : "No"]] as [string, string][]).map(([k, val], i) => (
                  <div key={i} style={{ border: "1px solid #eef1f4", borderRadius: 8, padding: "7px 10px", background: "#fafbfc" }}>
                    <div style={{ fontSize: 10.5, color: "#5d6b79", textTransform: "uppercase", letterSpacing: ".04em" }}>{k}</div>
                    <div style={{ fontSize: 13.5, fontWeight: 600, marginTop: 2, color: k === "Cleared" ? (v.cleared ? "#2f6b45" : "#7a3b52") : undefined }}>{val}</div>
                  </div>
                ))}
              </div>
              <div style={{ fontSize: 12, fontWeight: 700, color: "#5d6b79", textTransform: "uppercase", letterSpacing: ".04em", margin: "4px 0 6px" }}>Courses to sit</div>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
                <tbody>
                  {(v.courses ?? []).map((co, i) => (
                    <tr key={i} style={{ borderBottom: "1px solid #eef1f4" }}>
                      <td style={{ padding: "5px 8px 5px 0", fontWeight: 600, whiteSpace: "nowrap", verticalAlign: "top" }}>{co.course_code}</td>
                      <td style={{ padding: "5px 0", verticalAlign: "top" }}>{co.title}</td>
                      <td style={{ padding: "5px 0 5px 8px", textAlign: "right", color: "#5d6b79", whiteSpace: "nowrap", verticalAlign: "top" }}>{co.units}u</td>
                    </tr>
                  ))}
                  {!(v.courses ?? []).length ? <tr><td style={{ padding: "7px 0", color: "#8a97a3" }}>No approved courses on record for this semester.</td></tr> : null}
                </tbody>
              </table>
            </>
          ) : null}

          <p style={{ fontSize: 11.5, color: "#8a97a3", marginTop: 18, lineHeight: 1.5 }}>
            This page reads the University&rsquo;s register directly. The photograph is the one captured at admission; the
            invigilator admits a candidate only when the face matches it and this card verifies. Verified {new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.
          </p>
        </div>
      </div>
    </div>
  );
}
