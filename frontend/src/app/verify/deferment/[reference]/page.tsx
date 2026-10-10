import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

type V = { genuine: boolean } & Record<string, string | number | boolean | null | undefined>;
const day = (iso: unknown) => (iso ? new Date(String(iso)).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const word = (s: unknown) => String(s ?? "").replace(/_/g, " ").toLowerCase();

/** /verify/deferment/{reference} — the public verification of a deferment approval letter (V286): the QR on the paper opens the University's record */
export default async function Page({ params }: { params: Promise<{ reference: string }> }) {
  const p = await params;
  const r = await api<V>(`/api/v1/verify/deferment/${encodeURIComponent(p.reference)}`);
  const v: V = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const rows: [string, string][] = ok ? [["Reference", String(v.reference ?? "")], ["Student", String(v.student_name ?? "")], ["Number", String(v.student_number ?? "")], ["Programme", String(v.programme ?? "")], ["Faculty", String(v.faculty ?? "")], ["Kind", word(v.kind)], ["Deferred", `${v.session ?? ""}${v.semester ? ` · semester ${v.semester}` : ""}`], ["Returns", `${v.return_session ?? ""}${v.return_semester ? ` · semester ${v.return_semester}` : ""}`], ["Approved on", day(v.decided_at)], ["State", word(v.state)]] : [];
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div><div className="phead__t ink-chrome">Deferment approval verification</div></div>
        </div>
        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine — this is the University's record" : "Not verified"}>
            {ok ? "The deferment named on the letter was approved by the University and stands on the student's record as shown." : "No approved deferment matches this reference. Treat the letter as not genuine."}
          </Note>
          {ok ? (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--s-2)" }}>
              {rows.map(([k, val], i) => (
                <div key={i} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}><div className="eyebrow">{k}</div><div className="b600">{val || "—"}</div></div>
              ))}
            </div>
          ) : null}
          <div className="sub2 mt-3">Only publicly disclosed details are shown.</div>
        </div>
      </div>
    </div>
  );
}
