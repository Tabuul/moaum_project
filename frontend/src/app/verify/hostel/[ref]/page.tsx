import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface HostelVerify {
  genuine: boolean; reference_no?: string; state?: string; session?: string; student_name?: string; student_number?: string; programme?: string; hall_name?: string; block?: string; floor?: number; room_no?: string; bed_label?: string;
  start_on?: string | null; end_on?: string | null; checked_in_at?: string | null; checked_out_at?: string | null; clearance_ref?: string | null; clearance_state?: string | null; photo?: string | null;
}
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

/** /verify/hostel/{ref} — the public verification of a hostel allocation letter or clearance certificate (V261): the porter scans
 *  the QR and sees the University's record — the student, the photograph, the placing and the state of the stay. */
export default async function Page({ params }: { params: Promise<{ ref: string }> }) {
  const { ref } = await params;
  const r = await api<HostelVerify>(`/api/v1/verify/hostel/${encodeURIComponent(ref)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div><div className="phead__t ink-chrome">Hostel allocation verification</div></div>
        </div>
        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine — this is the University's record" : "Not verified"}>
            {ok ? "Check that the face below matches the student, and the hostel, room and bed match the letter in hand." : "No hostel allocation matches this reference. Treat the letter as not genuine."}
          </Note>
          {ok ? (
            <>
              <div className="row row--top" style={{ gap: "var(--s-3)", flexWrap: "nowrap" }}>
                {v.photo ? (
                  /* eslint-disable-next-line @next/next/no-img-element */
                  <img src={v.photo} alt="Student photograph" style={{ width: 76, height: 92, objectFit: "cover", border: "1px solid var(--line)", borderRadius: "var(--r-sm)", flexShrink: 0 }} />
                ) : <div className="sub2 ink-faint" style={{ width: 76, height: 92, border: "1px dashed var(--field)", borderRadius: "var(--r-sm)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>No photo</div>}
                <div className="grow"><div className="b700 t-lg" style={{ lineHeight: 1.25 }}>{v.student_name}</div><div className="tnum mt-1">{v.student_number}</div><div className="t-sm ink-muted mt-1">{v.programme ?? "—"}</div><div className="t-sm ink-muted">{v.session} · {v.reference_no}</div></div>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(120px, 1fr))", gap: "var(--s-2)" }}>
                {([["Hostel", v.hall_name ?? "—"], ["Block · floor", `${v.block ?? "—"} · ${v.floor ?? 0}`], ["Room", v.room_no ?? "—"], ["Bed", v.bed_label ?? "—"], ["State", (v.state ?? "").replace(/_/g, " ").toLowerCase()], ["Stay", `${day(v.start_on)} – ${day(v.end_on)}`], ["Checked in", day(v.checked_in_at)], ["Clearance", v.clearance_ref ? `${v.clearance_ref} · ${(v.clearance_state ?? "").toLowerCase()}` : "none"]] as [string, string][]).map(([k, val], i) => (
                  <div key={i} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}><div className="eyebrow">{k}</div><div className="b600" style={{ textTransform: k === "State" ? "capitalize" : undefined }}>{val}</div></div>
                ))}
              </div>
            </>
          ) : null}
        </div>
      </div>
    </div>
  );
}
