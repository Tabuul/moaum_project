"use client";

/** rCertificates — proto/part9.html: the register, and the stock it is printed on. */
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { CertificateRegister } from "@/lib/credentials";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

const SHORT: Record<string, string> = { "First Class Honours": "1st", "Second Class Honours (Upper)": "2:1", "Second Class Honours (Lower)": "2:2", "Third Class Honours": "3rd", Pass: "Pass" };

export function Certificates({ register, actingOffice }: { register: CertificateRegister; actingOffice: string | null }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [modal, setModal] = useState<"batch" | "print" | "hold" | "reissue" | null>(null);
  const [target, setTarget] = useState<string | null>(null);
  const [f, setF] = useState({ batch: "", serialFrom: "", serialTo: "", receivedOn: "", studentId: "", batchId: "", reason: "" });
  const t = register.tiles;
  const year = new Date().getFullYear();
  const signer = ["registrar", "dregistrar", "academic"].includes(actingOffice ?? "");

  async function post(path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) {
        setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
        return false;
      }
      notify(reason);
      router.refresh();
      setModal(null);
      return true;
    } finally {
      setBusy(false);
    }
  }

  const status = (c: CertificateRegister["certificates"][number]) =>
    c.status === "COLLECTED" ? <Pil kind="ok">Collected {day(c.collectedOn, false)}</Pil>
    : c.status === "PRINTED" ? <Pil kind="info">Printed, awaiting collection</Pil>
    : c.status === "HELD" ? <Pil kind="bad">Held — {c.heldReason}</Pil>
    : c.status === "REISSUED" ? <Pil kind="ok">Reissued — duplicate</Pil>
    : <Pil kind="bad">Revoked</Pil>;

  return (
    <>
      <Tiles items={[
        [`Graduands ${year}`, t.graduands.toLocaleString(), null, "Senate-approved list"],
        ["Certificates printed", t.printed.toLocaleString(), null, t.graduands ? `${Math.round((100 * t.printed) / t.graduands)}% of the list` : "None yet"],
        ["Collected", t.collected.toLocaleString(), "var(--green-ink)", "Identity verified at collection"],
        ["Security stock left", t.stockLeft.toLocaleString(), t.stockLeft < 1000 ? "var(--red-ink)" : null, "Reorder at 1,000"],
      ]} />
      <Note kind="info" title="A certificate cannot be printed before Senate approves the award">
        The graduand list, the classification and the clearance are all checked by the system first. Stationery serial numbers are tracked from issue to collection, so a spoiled certificate is accounted for.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title="Certificate register" right={register.convocation ?? `Convocation ${year}`}>
        <DTable
          cols={["Certificate no.", "Graduand", "Award", "Class|mid", "Status|num"]}
          rows={register.certificates.map((c) => [
            <span className="tnum" key="n">{c.number}</span>,
            <Two key="g" a={`${c.surname}, ${c.otherNames}`} b={c.matricNo ?? "—"} />,
            <span key="a">{c.award}</span>,
            <span className="sub2" key="c">{SHORT[c.classOfDegree] ?? c.classOfDegree}</span>,
            <span key="s">{status(c)} {c.status === "PRINTED" ? <><Btn kind="ghost" disabled={busy} onClick={() => void post(`/api/bff/api/v1/credentials/certificates/${c.id}/collect`, {}, `${c.number} collected`)}>Collected</Btn> <Btn kind="ghost" onClick={() => { setTarget(c.id); setF({ ...f, reason: "" }); setModal("hold"); }}>Hold</Btn></> : null}{c.status === "COLLECTED" && signer ? <> <Btn kind="ghost" onClick={() => { setTarget(c.id); setF({ ...f, reason: "" }); setModal("reissue"); }}>Reissue</Btn></> : null}</span>,
          ])}
          texts={register.certificates.map((c) => `${c.number} ${c.surname} ${c.otherNames} ${c.matricNo ?? ""} ${c.award}`)}
        />
        <PBody>
          <div className="row">
            <Btn kind="primary" disabled={!register.awaitingPrint.length} onClick={() => { setF({ ...f, studentId: register.awaitingPrint[0]?.studentId ?? "", batchId: register.batches[0]?.id ?? "" }); setModal("print"); }}>Print a certificate</Btn>
            <span className="sub2">{register.awaitingPrint.length ? `${register.awaitingPrint.length} approved graduand${register.awaitingPrint.length === 1 ? "" : "s"} not yet printed` : "Every approved graduand has a certificate; the next ones arrive when Senate approves a list"}</span>
          </div>
        </PBody>
      </Panel>

      <Note kind="info" title="Certificates awarded before 30 December 2024">
        They were issued as Benue State University, Makurdi and carry that name. Both names resolve in verification, so an older certificate is never mistaken for a forgery.
      </Note>

      <Panel title="Stationery control" right="Pre-printed security stock">
        <DTable
          cols={["Batch", "Serial range", "Issued|mid", "Used|mid", "Spoiled|mid", "Returned|mid", "|num"]}
          rows={register.batches.map((b) => [
            <span className="tnum" key="b">{b.batch}</span>,
            <span className="tnum" key="r">{String(b.serialFrom).padStart(6, "0")} – {String(b.serialTo).padStart(6, "0")}</span>,
            <span className="tnum" key="i">{b.issued.toLocaleString()}</span>, <span className="tnum" key="u">{b.used.toLocaleString()}</span>,
            <span className="tnum" key="s">{b.spoiled}</span>, <span className="tnum" key="t">{b.returned}</span>,
            <span key="a"><Btn kind="ghost" disabled={busy} onClick={() => void post(`/api/bff/api/v1/credentials/stationery/${b.id}/spoil`, { count: 1 }, `${b.batch}: one certificate spoiled`)}>Spoiled one</Btn></span>,
          ])}
        />
        <PBody><Btn kind="primary" onClick={() => { setF({ ...f, batch: "", serialFrom: "", serialTo: "", receivedOn: "" }); setModal("batch"); }}>+ New batch</Btn></PBody>
      </Panel>

      {modal === "batch" ? (
        <Modal title="New stationery batch" sub="Serial numbers are tracked from issue to collection" onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !f.batch || !f.serialFrom || !f.serialTo || !f.receivedOn} onClick={() => void post("/api/bff/api/v1/credentials/stationery", { batch: f.batch, serialFrom: Number(f.serialFrom), serialTo: Number(f.serialTo), receivedOn: f.receivedOn }, `Stationery batch ${f.batch} received`)}>Record the batch</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="b-batch" label="Batch"><input id="b-batch" className="ctl tnum" value={f.batch} placeholder={`B-${year}-01`} onChange={(e) => setF({ ...f, batch: e.target.value })} autoComplete="off" /></Field>
            <Field id="b-on" label="Received on"><input id="b-on" className="ctl" type="date" value={f.receivedOn} onChange={(e) => setF({ ...f, receivedOn: e.target.value })} /></Field>
            <Field id="b-from" label="First serial"><input id="b-from" className="ctl tnum" value={f.serialFrom} onChange={(e) => setF({ ...f, serialFrom: e.target.value })} autoComplete="off" /></Field>
            <Field id="b-to" label="Last serial"><input id="b-to" className="ctl tnum" value={f.serialTo} onChange={(e) => setF({ ...f, serialTo: e.target.value })} autoComplete="off" /></Field>
          </div>
        </Modal>
      ) : null}
      {modal === "print" ? (
        <Modal title="Print a certificate" sub="Only against a Senate-approved, cleared graduand" onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !f.studentId} onClick={() => void post("/api/bff/api/v1/credentials/certificates", { studentId: f.studentId, batchId: f.batchId || null, convocation: `Convocation ${year}` }, "Certificate printed")}>Print</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="p-who" label="Graduand"><select id="p-who" className="ctl" value={f.studentId} onChange={(e) => setF({ ...f, studentId: e.target.value })}>{register.awaitingPrint.map((g) => <option key={g.studentId} value={g.studentId}>{g.surname}, {g.otherNames} — {g.award}</option>)}</select></Field>
            <Field id="p-batch" label="Stationery batch" hint="The next unused serial is taken from it"><select id="p-batch" className="ctl" value={f.batchId} onChange={(e) => setF({ ...f, batchId: e.target.value })}><option value="">No serial recorded</option>{register.batches.map((b) => <option key={b.id} value={b.id}>{b.batch}</option>)}</select></Field>
          </div>
        </Modal>
      ) : null}
      {modal === "hold" || modal === "reissue" ? (
        <Modal title={modal === "hold" ? "Hold this certificate" : "Reissue as a duplicate"} sub={modal === "hold" ? "Name the clearance outstanding" : "Affidavit and police report reference"} onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind={modal === "hold" ? "urgent" : "primary"} disabled={busy || !f.reason.trim()} onClick={() => void post(`/api/bff/api/v1/credentials/certificates/${target}/${modal}`, { reason: f.reason, batchId: f.batchId || null }, modal === "hold" ? `Certificate held: ${f.reason}` : `Certificate reissued: ${f.reason}`)}>{modal === "hold" ? "Hold" : "Reissue"}</Btn></>}>
          <Field id="c-reason" label={modal === "hold" ? "Reason" : "Evidence"}><input id="c-reason" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} autoComplete="off" /></Field>
        </Modal>
      ) : null}
    </>
  );
}
