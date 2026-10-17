"use client";

/** V506: a session's fee lines filled from another — the preview first (each line of the source session, and whether it is
 *  copied or already stated here and kept), then the copy of what this session lacks; a line stated here is never overwritten.
 *  The Bursary adjusts the amounts afterwards as for any line. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { COPY_ACTION, copyScope, type CopyLine } from "@/lib/fee-copy";

interface Copied { from: string; to: string; copy: number; kept: number; applied: boolean; lines: CopyLine[] }

export function FeeCopy({ session, sessions, may }: { session: string; sessions: string[]; may: boolean }) {
  const router = useRouter();
  const others = sessions.filter((s) => s !== session);
  const [from, setFrom] = useState(others[0] ?? "");
  const [preview, setPreview] = useState<Copied | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [asking, setAsking] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const path = `/api/bff/api/v1/finance/sessions/${session}/schedule/copy`;

  async function look() {
    setBusy("look"); setSaid(null);
    try {
      const r = await fetch(`${path}?from=${encodeURIComponent(from)}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setPreview(null); notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return; }
      setPreview(j as Copied);
    } finally { setBusy(null); }
  }

  async function copy() {
    setBusy("copy");
    try {
      const r = await fetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Fee lines of ${from} copied into ${session}`) },
        body: JSON.stringify({ from }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return; }
      const c = j as Copied;
      setSaid(`${c.copy.toLocaleString()} fee line${c.copy === 1 ? "" : "s"} of ${from} copied into ${session}; ${c.kept.toLocaleString()} already stated here kept as they were. Adjust any amount on the list above.`);
      notify(`${c.copy.toLocaleString()} fee line${c.copy === 1 ? "" : "s"} copied`);
      setPreview(null);
      setAsking(false);
      router.refresh();
    } finally { setBusy(null); }
  }

  if (!others.length) return null;
  return (
    <Panel title="Copy the fees from another session" right={`Into ${session}: what ${session} does not state yet`}>
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
          <Field id="fc-from" label="Copy from" style={{ flex: "0 1 180px" }}>
            <select id="fc-from" className="ctl" value={from} onChange={(e) => { setFrom(e.target.value); setPreview(null); }} disabled={!!busy}>
              {others.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </Field>
          <Btn kind="ghost" disabled={!!busy || !from} onClick={() => void look()}>{busy === "look" ? "Reading…" : "See what is copied"}</Btn>
        </div>
        <div className="sub2 mt-2">
          Every live line of the session chosen is copied into {session} — school fees, late payment and late registration, by level, entry mode,
          faculty, programme, fee group, semester and indigeneship — unless {session} already states a line for the same students: that one is kept,
          never overwritten. Read the list first; afterwards adjust any amount on the charges above.
        </div>
        {said ? <Note kind="ok" title="Copied">{said}</Note> : null}
      </PBody>
      {preview ? (
        <>
          <PBody>
            <Tiles items={[
              ["To be copied", preview.copy.toLocaleString(), preview.copy ? "var(--green-ink)" : null, `Lines of ${preview.from} that ${preview.to} does not state`],
              ["Already stated here", preview.kept.toLocaleString(), null, "Kept as they are"],
            ]} />
            {may && preview.copy > 0 ? (
              <div className="row mt-2"><Btn kind="primary" disabled={!!busy} onClick={() => setAsking(true)}>{`Copy ${preview.copy.toLocaleString()} line${preview.copy === 1 ? "" : "s"} into ${session}`}</Btn></div>
            ) : null}
            {!preview.copy ? <div className="sub2 mt-2">{session} already states every line {preview.from} does: nothing to copy.</div> : null}
          </PBody>
          <DTable cols={["Item", "Applies to", "Amount|num", `In ${preview.to}|num`, ""]} rows={preview.lines.map((l) => [
            <strong key="i">{l.item}</strong>,
            <span key="a" className="sub2">{copyScope(l)}</span>,
            <span key="m" className="tnum">{money(Number(l.amount))}</span>,
            <span key="t" className="tnum sub2">{l.target_amount != null ? money(Number(l.target_amount)) : "—"}</span>,
            <Pil key="p" kind={COPY_ACTION[l.action][1]}>{COPY_ACTION[l.action][0]}</Pil>,
          ])} />
        </>
      ) : null}
      {asking && preview ? (
        <Modal title={`Copy ${preview.copy.toLocaleString()} fee line${preview.copy === 1 ? "" : "s"} into ${session}`} onClose={() => { if (!busy) setAsking(false); }}
          foot={<><Btn kind="ghost" disabled={!!busy} onClick={() => setAsking(false)}>Cancel</Btn>
            <Btn kind="primary" disabled={!!busy} onClick={() => void copy()}>{busy === "copy" ? "Copying…" : "Copy"}</Btn></>}>
          <p>
            The {preview.copy.toLocaleString()} line{preview.copy === 1 ? "" : "s"} of {preview.from} that {session} does not state {preview.copy === 1 ? "is" : "are"} added
            to {session} with {preview.from}&rsquo;s amounts. The {preview.kept.toLocaleString()} already stated here stay as they are. Students are charged the new lines
            at once; adjust or end any of them on the list of charges.
          </p>
        </Modal>
      ) : null}
    </Panel>
  );
}
