"use client";

/**
 * JUPEB identity cards (V349): the active students of a session (or a class), each with the live card's code, or none yet.
 * The JUPEB Office issues cards for those chosen — a student needs a passport photograph on file — and prints them at the
 * card's own size, front and back, each with a QR that opens /verify/jupeb/{code}. A lost or damaged card is replaced: its code
 * stops verifying (revoked with the reason) and a new card is issued.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { day, jcall, streamLabel } from "@/lib/jupeb";

export interface CardRow {
  id: string; application_no: string; exam_no: string | null; surname: string; first_name: string; middle_name: string | null; session: string; stream: string | null;
  next_of_kin_phone: string | null; state: string; combination_code: string | null; combination_name: string | null; class_name: string | null; has_passport: boolean;
  card_code: string | null; card_issued_at: string | null; replaced: number;
}
export interface CardsData { session: string; sessions: { session: string; applications: number }[]; classes: { id: string; name: string }[]; students: CardRow[] }

export function JupebIdCards({ canWrite }: { canWrite: boolean }) {
  const [session, setSession] = useState("");
  const [klass, setKlass] = useState("");
  const [data, setData] = useState<CardsData | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [tick, setTick] = useState(0);
  const [busy, setBusy] = useState(false);
  const [replace, setReplace] = useState<{ row: CardRow; reason: string } | null>(null);
  useEffect(() => {
    let live = true;
    const qs = new URLSearchParams({ ...(session ? { session } : {}), ...(klass ? { classId: klass } : {}) });
    void jcall<CardsData>(`/api/v1/jupeb/office/id-cards?${qs.toString()}`).then((r) => {
      if (!live) return;
      if (r.ok) { setData(r.data); if (!session) setSession(r.data.session); } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [session, klass, tick]);

  const rows = data?.students ?? [];
  const eligible = rows.filter((r) => r.has_passport);
  const chosen = rows.filter((r) => picked.has(r.id));
  async function issue(ids: string[]) {
    setBusy(true);
    try {
      const r = await jcall<{ cards: { id: string; code: string }[]; skipped: { id: string; reason: string }[] }>("/api/v1/jupeb/office/id-cards/issue", "POST", { ids }, "JUPEB identity cards issued");
      if (!r.ok) { notifyProblem(r.problem); return null; }
      notify(`${r.data.cards.length} card${r.data.cards.length === 1 ? "" : "s"} ready${r.data.skipped.length ? `; ${r.data.skipped.length} skipped (${r.data.skipped[0].reason})` : ""}.`);
      setTick((t) => t + 1);
      return r.data.cards;
    } finally { setBusy(false); }
  }
  async function issueAndPrint() {
    const ids = chosen.filter((r) => r.has_passport).map((r) => r.id);
    if (!ids.length) { notifyProblem({ status: 400, title: "Choose students with a passport photograph on file." }); return; }
    const cards = canWrite ? await issue(ids) : rows.filter((r) => ids.includes(r.id) && r.card_code).map((r) => ({ id: r.id, code: r.card_code as string }));
    if (!cards || !cards.length) return;
    window.open(`/jupeb/idcards/print?session=${encodeURIComponent(session)}&ids=${cards.map((c) => c.id).join(",")}`, "_blank", "noopener");
  }
  async function doReplace() {
    if (!replace) return;
    setBusy(true);
    try {
      const r = await jcall<{ code: string; replaced: string }>(`/api/v1/jupeb/office/id-cards/${replace.row.id}/replace`, "POST", { reason: replace.reason.trim() }, "JUPEB identity card replaced");
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Card ${r.data.replaced} no longer verifies; the new card is ${r.data.code}.`);
      setReplace(null); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  const all = eligible.length > 0 && eligible.every((r) => picked.has(r.id));
  return (
    <>
      <PageHead title="JUPEB identity cards" description="Cards for the session's active students, printed at the card's own size, each with a QR that opens the University's record. A lost card is replaced and its code stops verifying."
        actions={<span className="row">
          <select className="ctl" aria-label="Session" value={session} onChange={(e) => { setSession(e.target.value); setKlass(""); setPicked(new Set()); }}>
            {(data?.sessions ?? []).map((x) => <option key={x.session} value={x.session}>{x.session}</option>)}</select>
          <select className="ctl" aria-label="Class" value={klass} onChange={(e) => { setKlass(e.target.value); setPicked(new Set()); }}>
            <option value="">Every class</option>{(data?.classes ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
        </span>} />
      <Panel title={`${rows.length} active student${rows.length === 1 ? "" : "s"} · ${rows.filter((r) => r.card_code).length} with a card`} right={<span className="row">
        <span className="sub2">{chosen.length} chosen</span>
        <Btn kind="ghost" disabled={!eligible.length} onClick={() => setPicked(all ? new Set() : new Set(eligible.map((r) => r.id)))}>{all ? "Choose none" : "Choose all with a photograph"}</Btn>
        <Btn kind="primary" disabled={busy || !chosen.length} onClick={() => void issueAndPrint()}>{canWrite ? "Issue and print the chosen" : "Print the chosen"}</Btn>
      </span>}>
        {!data ? <PBody><p className="sub2">Loading…</p></PBody> : !rows.length ? <PBody><Note kind="info" title="No active student">A card is for a student whose school fee has activated their studentship.</Note></PBody> : (
          <DTable pageSize={50} cols={["", "Student", "Application No.", "Class", "Programme", "Photograph", "Card", ...(canWrite ? [""] : [])]}
            texts={rows.map((r) => `${r.surname} ${r.first_name} ${r.application_no} ${r.card_code ?? ""}`)}
            rows={rows.map((r) => [
              <input key="c" type="checkbox" aria-label={`Choose ${r.surname}`} disabled={!r.has_passport} checked={picked.has(r.id)}
                onChange={(e) => setPicked((p) => { const n = new Set(p); if (e.target.checked) n.add(r.id); else n.delete(r.id); return n; })} />,
              <b key="n">{r.surname}, {r.first_name}</b>, <span key="a" className="tnum">{r.application_no}</span>, r.class_name ?? "—",
              `${streamLabel(r.stream)}${r.combination_code ? ` · ${r.combination_code}` : ""}`,
              r.has_passport ? <Pil key="p" kind="ok">On file</Pil> : <Pil key="p" kind="bad">Missing</Pil>,
              r.card_code ? <span key="k"><span className="tnum">{r.card_code}</span><div className="sub2">{day(r.card_issued_at)}{r.replaced ? ` · ${r.replaced} replaced` : ""}</div></span> : <span key="k" className="sub2">Not issued</span>,
              ...(canWrite ? [r.card_code ? <Btn key="r" kind="ghost" onClick={() => setReplace({ row: r, reason: "" })}>Replace</Btn> : ""] : []),
            ])} />
        )}
      </Panel>
      {replace ? (
        <Modal title={`Replace ${replace.row.surname}, ${replace.row.first_name}'s card`} onClose={() => setReplace(null)}
          foot={<><Btn kind="ghost" onClick={() => setReplace(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || replace.reason.trim().length < 5} onClick={() => void doReplace()}>Replace the card</Btn></>}>
          <p className="sub2">Card <b className="tnum">{replace.row.card_code}</b> stops verifying at once; a new card with a new code is issued for printing.</p>
          <Field id="ic-r" label="Why" required hint="Lost, damaged, stolen…"><input id="ic-r" className="ctl" maxLength={500} value={replace.reason} onChange={(e) => setReplace({ ...replace, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
