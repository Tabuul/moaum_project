"use client";

/** V766 (D13): the documents a transfer applicant is asked for — a short list the Academic Office keeps: each with its label and hint, whether
 *  it is required, whether a photograph (JPEG or PNG) is taken besides a PDF, its order, and whether it is asked at all. The four seeded
 *  with V763's incoming codes count as those documents on the transfer the approval registers; that mapping is never edited. A change of
 *  "required" applies to submissions made after it: a submitted application is never held back by it. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { documentWords } from "@/lib/university-transfer";
import { KEEPERS, kindProblem, type DocumentKind } from "@/lib/transfer-application";
import { OFFICE, call } from "@/app/transfer/call";

type Edit = { code: string; label: string; hint: string; required: boolean; imagesAllowed: boolean; ord: string; active: boolean; isNew: boolean };
const blank = (ord: number): Edit => ({ code: "", label: "", hint: "", required: false, imagesAllowed: true, ord: String(ord), active: true, isNew: true });

export function KindsPanel({ kinds, office }: { kinds: DocumentKind[]; office: string | null }) {
  const router = useRouter();
  const may = KEEPERS.includes(office ?? "");
  const [edit, setEdit] = useState<Edit | null>(null);
  const sorted = [...kinds].sort((a, b) => (a.ord ?? 0) - (b.ord ?? 0));
  const next = (sorted.at(-1)?.ord ?? 0) + 10;

  async function save() {
    if (!edit) return;
    const why = kindProblem(edit);
    if (why) { notifyProblem({ status: 400, title: "The document kind cannot be saved", detail: why }); return; }
    const r = await call<DocumentKind[]>("PUT", `${OFFICE}/document-kinds`, {
      // a hint emptied is sent blank, which clears it (null would keep the one there)
      code: edit.code, label: edit.label.trim(), hint: edit.hint.trim(), required: edit.required, imagesAllowed: edit.imagesAllowed, ord: Number(edit.ord) || next, active: edit.active,
    }, `Transfer application document ${edit.code} ${edit.isNew ? "added" : "changed"}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`${edit.label.trim()}: saved`);
    setEdit(null);
    router.refresh();
  }

  return (
    <Panel title="Documents asked of an applicant" right={`${kinds.filter((k) => k.active !== false).length} asked · ${kinds.filter((k) => k.active !== false && k.required).length} required`}>
      <PBody><div className="sub2">PDF is always taken; a photograph (JPEG or PNG) only where the kind allows it; at most 5 MB a file. A document made required is asked
        of every application not yet with the Head of Department (one already submitted is returned to its applicant for it); an application the
        department has seen is never held for it.</div></PBody>
      <DTable cols={["Order|num", "Code", "Document", "Required", "Photographs", "Counts on the transfer as", "Asked", "|num"]} rows={sorted.map((k) => [
        <span key="o" className="tnum sub2">{k.ord ?? ""}</span>,
        <span key="c" className="tnum">{k.code}</span>,
        <span key="l"><b>{k.label}</b>{k.hint ? <div className="sub2">{k.hint}</div> : null}</span>,
        <span key="r">{k.required ? <Pil kind="info">Required</Pil> : <span className="sub2">Optional</span>}</span>,
        <span key="i" className="sub2">{k.imagesAllowed === false ? "PDF only" : "Taken"}</span>,
        <span key="t" className="sub2">{k.transferCode ? documentWords([k.transferCode]) : "—"}</span>,
        <Pil key="a" kind={k.active === false ? "grey" : "ok"}>{k.active === false ? "Not asked" : "Asked"}</Pil>,
        may ? <Btn key="e" kind="ghost" size="sm" onClick={() => setEdit({ code: k.code, label: k.label, hint: k.hint ?? "", required: !!k.required, imagesAllowed: k.imagesAllowed !== false,
          ord: String(k.ord ?? ""), active: k.active !== false, isNew: false })}>Edit</Btn> : <span key="e" />,
      ])} texts={sorted.map((k) => `${k.code} ${k.label}`)} />
      {may ? (
        <PBody>
          {edit ? (
            <>
              <div className="eyebrow mb-1">{edit.isNew ? "A new document kind" : `Change ${edit.code}`}</div>
              <div className="grid grid--4">
                <Field id="ik-code" label="Code" required hint="Capital letters, digits and _">
                  <input id="ik-code" className="ctl tnum" value={edit.code} disabled={!edit.isNew} maxLength={40} onChange={(e) => setEdit({ ...edit, code: e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, "") })} />
                </Field>
                <Field id="ik-label" label="Label" required style={{ gridColumn: "span 2" }}>
                  <input id="ik-label" className="ctl" value={edit.label} maxLength={160} onChange={(e) => setEdit({ ...edit, label: e.target.value })} />
                </Field>
                <Field id="ik-ord" label="Order">
                  <input id="ik-ord" className="ctl tnum" value={edit.ord} inputMode="numeric" onChange={(e) => setEdit({ ...edit, ord: e.target.value.replace(/[^0-9]/g, "") })} />
                </Field>
              </div>
              <Field id="ik-hint" label="Hint" hint="At most 400 characters: what the applicant should upload">
                <input id="ik-hint" className="ctl" value={edit.hint} maxLength={400} onChange={(e) => setEdit({ ...edit, hint: e.target.value })} />
              </Field>
              <div className="row row--inline mt-1" style={{ gap: 16, flexWrap: "wrap" }}>
                <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={edit.required} onChange={(e) => setEdit({ ...edit, required: e.target.checked })} /> Required</label>
                <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={edit.imagesAllowed} onChange={(e) => setEdit({ ...edit, imagesAllowed: e.target.checked })} /> A photograph (JPEG or PNG) is taken</label>
                <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={edit.active} onChange={(e) => setEdit({ ...edit, active: e.target.checked })} /> Asked of applicants</label>
              </div>
              <div className="row mt-2"><Btn kind="ghost" onClick={() => setEdit(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" onClick={() => save()}>Save</Btn></div>
            </>
          ) : <Btn kind="secondary" onClick={() => setEdit(blank(next))}>Add a document kind</Btn>}
        </PBody>
      ) : null}
    </Panel>
  );
}
