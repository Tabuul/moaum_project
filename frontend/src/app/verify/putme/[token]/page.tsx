import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface PutmeVerify {
  genuine: boolean; application_no?: string; name?: string; jamb_reg_no?: string; programme?: string; session?: string;
  batch?: string; held_on?: string; starts_at?: string; ends_at?: string; batch_state?: string; centre?: string | null; location?: string | null; room?: string | null; seat?: string;
  exam?: string | null; checkin_minutes?: number | null; attendance?: string | null; checked_in_at?: string | null; photo?: string | null;
}

const day = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
const clock = (t: string) => String(t).slice(0, 5);

/** /verify/putme/{token} — the public verification of a Post-UTME examination slip (V260). The door scans
 *  the slip's QR and sees the University's own record: the name, PHOTO, batch, day, time, centre, room and
 *  seat, and whether the candidate is already checked in — so a cloned or altered slip is exposed. Public. */
export default async function Page({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const r = await api<PutmeVerify>(`/api/v1/verify/putme/${encodeURIComponent(token)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const off = v.batch_state === "POSTPONED" || v.batch_state === "CANCELLED";

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="phead__t ink-chrome">Post-UTME examination slip verification</div>
          </div>
        </div>
        <div className="card__body">
          <Note kind={ok ? (off ? "bad" : "ok") : "bad"} title={ok ? (off ? `Genuine slip — but the batch is ${String(v.batch_state).toLowerCase()}` : "Genuine slip — this is the University's record") : "Not verified"}>
            {ok
              ? off ? "A new date is to be published for this candidate. Do not admit them on this slip." : "Check that the face below matches the candidate, and the batch, seat and day match the slip in hand."
              : "No published examination slip matches this code. Treat the slip as not genuine, and refuse admission."}
          </Note>
          {ok ? (
            <>
              <div className="row row--top" style={{ gap: "var(--s-3)", flexWrap: "nowrap" }}>
                {v.photo ? (
                  /* eslint-disable-next-line @next/next/no-img-element */
                  <img src={v.photo} alt="Candidate photograph" style={{ width: 76, height: 92, objectFit: "cover", border: "1px solid var(--line)", borderRadius: "var(--r-sm)", flexShrink: 0 }} />
                ) : <div className="sub2 ink-faint" style={{ width: 76, height: 92, border: "1px dashed var(--field)", borderRadius: "var(--r-sm)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>No photo</div>}
                <div className="grow">
                  <div className="b700 t-lg" style={{ lineHeight: 1.25 }}>{v.name}</div>
                  <div className="tnum mt-1" style={{ overflowWrap: "anywhere" }}>{v.application_no} · JAMB {v.jamb_reg_no}</div>
                  <div className="t-sm ink-muted mt-1">{v.programme ?? "—"}</div>
                  <div className="t-sm ink-muted">{v.exam ?? "Post-UTME examination"} · {v.session}</div>
                </div>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(130px, 1fr))", gap: "var(--s-2)" }}>
                {([
                  ["Batch", v.batch ?? "—"], ["Day", v.held_on ? day(v.held_on) : "—"], ["Time", `${clock(v.starts_at ?? "")} – ${clock(v.ends_at ?? "")}`],
                  ["Centre", v.centre ?? "—"], ["Room", v.room ?? "—"], ["Seat", v.seat ?? "—"],
                  ["Attendance", v.attendance ? v.attendance.replace(/_/g, " ").toLowerCase() : "not checked in"],
                ] as [string, string][]).map(([k, val], i) => (
                  <div key={i} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}>
                    <div className="eyebrow">{k}</div>
                    <div className="b600" style={{ textTransform: k === "Attendance" ? "capitalize" : undefined }}>{val}</div>
                  </div>
                ))}
              </div>
              {v.checked_in_at ? <div className="sub2">Checked in at {new Date(v.checked_in_at).toLocaleString("en-GB")} — a second arrival on this slip is an impersonation.</div> : null}
            </>
          ) : null}
        </div>
      </div>
    </div>
  );
}
