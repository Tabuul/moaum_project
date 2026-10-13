import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface CardVerify {
  genuine: boolean; codeMissing?: boolean; card_no?: string; state?: string; issued_at?: string | null; valid_to?: string | null; ended_at?: string | null;
  staff_name?: string; staff_number?: string; department?: string | null; photo?: string | null;
}
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

/** /verify/staffcard?no=…&c=… — the public verification of a staff identity card (V439): the guard scans the card's QR and sees the
 *  University's record of the card in force — the member of staff, the photograph, the staff number, the department and the validity.
 *  A card lost, replaced or out of date, or of someone who has left, says so and names no one; without the check code nothing is said. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const card = typeof sp.no === "string" ? sp.no : "";
  const code = typeof sp.c === "string" ? sp.c : "";
  const r = await api<CardVerify>(`/api/v1/verify/staffcard?no=${encodeURIComponent(card)}${code ? `&c=${encodeURIComponent(code)}` : ""}`);
  const v: CardVerify = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const throttled = !r.ok && r.problem.status === 429;
  const ended = !ok && !!v.state;
  const endedWord = v.state === "LOST" ? `reported lost${v.ended_at ? ` on ${day(v.ended_at)}` : ""}` : v.state === "REPLACED" ? `replaced by a new card${v.ended_at ? ` on ${day(v.ended_at)}` : ""}`
    : v.state === "EXPIRED" ? `valid only to ${day(v.valid_to)}` : v.state === "LEFT" ? "carried by someone who has left the University" : `no longer in force (${(v.state ?? "").toLowerCase()})`;
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber-ink)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div><div className="phead__t ink-chrome">Staff identity card verification</div></div>
        </div>
        <div className="card__body">
          <Note kind={ok ? "ok" : throttled || v.codeMissing ? "info" : "bad"}
            title={ok ? "Genuine — this is the University's record" : throttled ? "Too many checks from this connection" : v.codeMissing ? "This card carries no check code" : ended ? `Card ${v.card_no} is not in force` : "Not verified"}>
            {ok ? "Check that the face below matches the holder, and the name and number match the card in hand."
              : throttled ? (r.ok ? "" : r.problem.detail ?? "Try again in a few minutes.")
              : v.codeMissing ? "Staff cards now carry a check code in their QR. A card printed without it is checked at the card desk by its number."
              : ended ? `This card was ${endedWord}. Do not accept it; the holder asks the card desk for the card in force.`
              : "No identity card matches this card number and check code. Treat the card as not genuine."}
          </Note>
          {ok ? (
            <>
              <div className="row row--top" style={{ gap: "var(--s-3)", flexWrap: "nowrap" }}>
                {v.photo ? (
                  /* eslint-disable-next-line @next/next/no-img-element */
                  <img src={v.photo} alt="Staff photograph" style={{ width: 76, height: 92, objectFit: "cover", border: "1px solid var(--line)", borderRadius: "var(--r-sm)", flexShrink: 0 }} />
                ) : <div className="sub2 ink-faint" style={{ width: 76, height: 92, border: "1px dashed var(--field)", borderRadius: "var(--r-sm)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>No photo</div>}
                <div className="grow"><div className="b700 t-lg" style={{ lineHeight: 1.25 }}>{v.staff_name}</div><div className="tnum mt-1">{v.staff_number}</div><div className="t-sm ink-muted mt-1">{v.department ?? "—"}</div></div>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(120px, 1fr))", gap: "var(--s-2)" }}>
                {([["Card", v.card_no ?? "—"], ["Issued", day(v.issued_at)], ["Valid to", day(v.valid_to)]] as [string, string][]).map(([k, val], i) => (
                  <div key={i} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}><div className="eyebrow">{k}</div><div className="b600 tnum">{val}</div></div>
                ))}
              </div>
            </>
          ) : null}
        </div>
      </div>
    </div>
  );
}
