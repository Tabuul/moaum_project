import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { LegacyNote } from "../../LegacyNote";

export const dynamic = "force-dynamic";

type V = { genuine: boolean } & Record<string, string | number | boolean | null | undefined>;
const day = (iso: unknown) => (iso ? new Date(String(iso)).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const word = (s: unknown) => String(s ?? "").replace(/_/g, " ").toLowerCase();

/** /verify/pg-offer/{no} — the public verification of a postgraduate offer of admission (V286): the QR on the paper opens the University's record */
export default async function Page({ params, searchParams }: { params: Promise<{ no: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await params;
  const q = await searchParams;
  const t = typeof q.t === "string" ? q.t : "";
  const r = await api<V>(`/api/v1/verify/pg-offer/${encodeURIComponent(p.no)}?t=${encodeURIComponent(t)}`);
  const v: V = r.ok ? r.data : { genuine: false };
  const ok = v.genuine && !v.limited;
  const rows: [string, string][] = ok ? [["Application number", String(v.application_no ?? "")], ["Applicant", String(v.applicant_name ?? "")], ["Programme", String(v.programme ?? "")], ["Award", String(v.award ?? "")], ["Faculty", String(v.faculty ?? "")], ["Department", String(v.department ?? "")], ["Session", String(v.session ?? "")], ["Entry level", String(v.entry_level ?? "")], ["Offered on", day(v.offered_on)], ["Accepted on", day(v.accepted_on)], ["State", word(v.state)]] : [];
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div><div className="phead__t ink-chrome">Postgraduate offer verification</div></div>
        </div>
        <div className="card__body">
          {v.limited ? <LegacyNote document="offer of admission" number={typeof v.number === "string" ? v.number : null} session={typeof v.session === "string" ? v.session : null} /> : (
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine — this is the University's record" : "Not verified"}>
              {ok ? "The offer named on the letter was made by the Postgraduate School and accepted as shown." : "No accepted postgraduate offer matches this number and code. Treat the letter as not genuine."}
            </Note>
          )}
          {ok ? (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--s-2)" }}>
              {rows.map(([k, val], i) => (
                <div key={i} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}><div className="eyebrow">{k}</div><div className="b600">{val || "—"}</div></div>
              ))}
            </div>
          ) : null}
          <div className="sub2 mt-3">Only what the University discloses publicly is shown. The paper is verified against the register, not by its appearance.</div>
        </div>
      </div>
    </div>
  );
}
