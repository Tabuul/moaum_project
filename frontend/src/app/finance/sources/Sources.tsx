"use client";

/** t/fundsources — the sources of income a wallet is funded from, kept in the database as a setting.
 *  The Bursary (and admin/super) add as many as they need; every wallet credit names one of them,
 *  and a student's wallet shows one card per source with the balance as their total (V079). */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import type { FundingSource } from "@/lib/wallet";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

const NAT: Record<string, [string, "ok" | "info" | "grey"]> = { LOAN: ["Loan", "info"], GRANT: ["Grant", "ok"], SELF: ["Own money", "grey"] };

const BLANK = { code: "", name: "", nature: "GRANT", sponsor: "", account: "", note: "", sort: "50" };

export function Sources({ sources, actingOffice }: { sources: FundingSource[]; actingOffice: string | null }) {
  const router = useRouter();
  const canEdit = ["bursar", "admin", "super"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [src, setSrc] = useState({ ...BLANK });
  const [editing, setEditing] = useState<string | null>(null);

  async function save(body: Record<string, unknown>, reason: string): Promise<boolean> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/funding/sources", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return false; }
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  function edit(x: FundingSource) {
    setEditing(x.code);
    setSrc({ code: x.code, name: x.name, nature: x.nature, sponsor: x.sponsor ?? "", account: x.account ?? "", note: x.note ?? "", sort: String(x.sort) });
    if (typeof window !== "undefined") window.scrollTo({ top: document.body.scrollHeight, behavior: "smooth" });
  }

  async function toggle(x: FundingSource) {
    if (await save({ code: x.code, name: x.name, nature: x.nature, sponsor: x.sponsor, account: x.account, active: !x.active, note: x.note, sort: x.sort }, `Funding source ${x.code} turned ${x.active ? "off" : "on"}`)) {
      setSaid(`${x.name} turned ${x.active ? "off" : "on"}`);
    }
  }

  return (
    <>
      <Note kind="info" title="The sources of income, kept in the database">
        Every source here is a row the University keeps and can add to at any time. A source is a <b>loan</b> the student repays the Fund (NELFUND), a <b>grant</b> that is never repaid (a scholarship or bursary), or the student&rsquo;s <b>own money</b> (a top-up). Every wallet credit names one of these, and a student&rsquo;s wallet shows one card per source with the balance as their total.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      <Panel title="Funding sources" right={`${sources.length} on the list · ${sources.filter((x) => x.active).length} active`}>
        {sources.length ? (
          <DTable cols={["Code|mid", "Name", "Nature|mid", "Sponsor", "Holding account", "Active|mid", "|num"]} rows={sources.map((x) => [
            <span className="tnum" key="c">{x.code}</span>,
            <span key="n">{x.name}<div className="sub2">{x.note ?? ""}</div></span>,
            <Pil kind={NAT[x.nature]?.[1] ?? "grey"} key="na">{NAT[x.nature]?.[0] ?? x.nature}</Pil>,
            <span className="sub2" key="sp">{x.sponsor ?? "—"}</span>,
            <span className="sub2" key="ac">{x.account ?? "Main school account"}</span>,
            x.active ? <Pil kind="ok" key="a">Active</Pil> : <Pil kind="grey" key="a">Off</Pil>,
            canEdit ? <span key="x" style={{ display: "flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
              <Btn kind="ghost" onClick={() => edit(x)}>Edit</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => void toggle(x)}>{x.active ? "Turn off" : "Turn on"}</Btn>
            </span> : <span className="sub2" key="x">—</span>,
          ])} texts={sources.map((x) => `${x.code} ${x.name} ${x.nature} ${x.sponsor ?? ""}`)} />
        ) : <PBody><div className="sub2">No source on the list yet.</div></PBody>}
      </Panel>
      {canEdit ? (
        <Panel title={editing ? `Edit ${editing}` : "Add a source of income"} right={editing ? "Saving the same code edits it" : "A new scholarship, sponsor, fund or loan"}>
          <PBody>
            <div className="grid grid--3">
              <Field id="fs-code" label="Code" hint="Short, e.g. TETFUND"><input id="fs-code" className="ctl tnum" value={src.code} disabled={!!editing} onChange={(e) => setSrc({ ...src, code: e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, "") })} /></Field>
              <Field id="fs-name" label="Name"><input id="fs-name" className="ctl" value={src.name} onChange={(e) => setSrc({ ...src, name: e.target.value })} placeholder="TETFund scholarship" /></Field>
              <Field id="fs-nat" label="Nature"><select id="fs-nat" className="ctl" value={src.nature} onChange={(e) => setSrc({ ...src, nature: e.target.value })}><option value="LOAN">Loan — repaid</option><option value="GRANT">Grant — never repaid</option><option value="SELF">Own money</option></select></Field>
            </div>
            <div className="grid grid--3">
              <Field id="fs-sp" label="Sponsor" hint="Optional"><input id="fs-sp" className="ctl" value={src.sponsor} onChange={(e) => setSrc({ ...src, sponsor: e.target.value })} /></Field>
              <Field id="fs-ac" label="Holding account" hint="Blank = main school account"><input id="fs-ac" className="ctl" value={src.account} onChange={(e) => setSrc({ ...src, account: e.target.value })} /></Field>
              <Field id="fs-so" label="Sort order"><input id="fs-so" className="ctl tnum" value={src.sort} onChange={(e) => setSrc({ ...src, sort: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            </div>
            <Field id="fs-note" label="Note" hint="Shown under the name on the list"><input id="fs-note" className="ctl" value={src.note} onChange={(e) => setSrc({ ...src, note: e.target.value })} /></Field>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
              <Btn kind="primary" disabled={busy || !src.code.trim() || !src.name.trim()} onClick={async () => {
                const code = src.code.trim();
                if (await save({ code, name: src.name.trim(), nature: src.nature, sponsor: src.sponsor || null, account: src.account || null, active: true, note: src.note || null, sort: Number(src.sort) || 100 }, `Funding source ${code} ${editing ? "edited" : "added"}`)) {
                  setSaid(`Source ${code} ${editing ? "saved" : "added"}`);
                  setSrc({ ...BLANK }); setEditing(null);
                }
              }}>{editing ? "Save the source" : "Add the source"}</Btn>
              {editing ? <Btn kind="ghost" onClick={() => { setSrc({ ...BLANK }); setEditing(null); }}>Cancel</Btn> : null}
              <Link href="/finance/nelfund?tab=report" className="btn btn--ghost btn--sm">Funding report</Link>
            </div>
            <div className="sub2" style={{ marginTop: 6 }}>NELFUND, Scholarship and Self top-up are seeded; add TETFund, a state scholarship, a sponsor or a bursary here. Add as many as you need.</div>
          </PBody>
        </Panel>
      ) : (
        <Note kind="info" title="Read-only">Only the Bursary, admin or super administrator can add or change a source of income.</Note>
      )}
    </>
  );
}
