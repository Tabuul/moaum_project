"use client";

/** tMatList — proto/part39.html: the Faculty Officer's side of it. */
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { FacultyList } from "@/lib/matriculation";
import { csv, download } from "@/lib/results";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function FacultyListScreen({ list, actingOffice }: { list: FacultyList; actingOffice: string | null }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [office, setOffice] = useState("Faculty Officer");
  const conf = list.state === "CONFIRMED";
  const may = ["academic", "registrar", "dregistrar", "facultyofficer"].includes(actingOffice ?? "");
  const mayIssue = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const queried = list.rows.filter((r) => r.queryReason);
  const ready = list.rows.length - queried.length;
  const min = list.minUnits ?? 15;
  const base = `/api/bff/api/v1/matriculation/sessions/${list.session}/faculties/${list.code}`;

  async function send(method: "PUT" | "POST", path: string, body: unknown, reasonText: string): Promise<boolean> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reasonText) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) {
        { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); }
        return false;
      }
      notify(reasonText);
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind={conf ? "ok" : "info"} title={conf ? "Your list is confirmed and has gone to the Academic Office" : "This list is generated from approved registrations"}>
        {conf ? `${list.rows.length} students registered; ${ready} confirmed. ${queried.length ? `${queried.length} ${queried.length === 1 ? "is" : "are"} under query and ${queried.length === 1 ? "is" : "are"} named below with the reason. They keep their registrations and are matriculated in the next run.` : "Nobody is under query."}`
          : `You are not keying names. The list is every student in the Faculty of ${list.name} with an approved course registration for ${list.session} — you cannot add a name to it and you cannot leave one off. What you are confirming is that these are the students who actually turned up and registered.`}
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["Registered in the faculty", String(list.rows.length), null, "Approved registrations"],
        ["Under query", String(queried.length), queried.length ? "var(--red-ink)" : null, queried.length ? "Named below, with reasons" : "Nobody"],
        ["To be confirmed", String(ready), null, "Goes to the Academic Office"],
        ["State", conf ? "Confirmed" : "Draft", conf ? "var(--green-ink)" : null, conf ? day(list.confirmedAt) : "Not yet submitted"],
      ]} />
      <Panel title={`Faculty of ${list.name} — students registered for ${list.session}`} right={`${list.rows.length} registered`}>
        <DTable
          cols={["Admission number", "Name", "Department", "Units|mid", "Fees|mid", "State|mid", "|num"]}
          rows={list.rows.map((r) => [
            <span className="tnum" key="a">{r.admissionNo}</span>, <strong key="n">{r.surname}, {r.otherNames}</strong>,
            <span className="sub2" key="d">{r.deptName}</span>,
            <span className={`tnum${r.units < min ? " ink-red" : ""}`} key="u">{r.units}</span>,
            <span className="sub2" key="f">—</span>,
            r.queryReason ? <Pil kind="bad" key="s">Query</Pil> : <Pil kind="ok" key="s">For matriculation</Pil>,
            r.queryReason
              ? <Btn kind="ghost" key="q" disabled={busy || !may || conf} onClick={() => void send("POST", `${base}/queries/${r.studentId}/withdraw`, {}, `Query withdrawn for ${r.admissionNo}`)}>Withdraw query</Btn>
              : <span key="act" className="row row--inline row--tight row--right">
                  <Btn kind="go" disabled={busy || !mayIssue} onClick={() => void send("POST", `/api/bff/api/v1/matriculation/sessions/${list.session}/students/${r.studentId}/matriculate`, {}, `Matriculation number issued for ${r.admissionNo}`)}>Issue number</Btn>
                  <Btn kind="ghost" disabled={busy || !may || conf} onClick={() => { setQuery(r.studentId); setReason(r.units < min ? `Registered ${r.units} units. The minimum at 100 level is ${min}` : ""); }}>Query</Btn>
                </span>,
          ])}
          texts={list.rows.map((r) => `${r.admissionNo} ${r.surname} ${r.otherNames} ${r.deptName}`)}
        />
        {!list.rows.length ? <PBody><div className="sub2">No student of this faculty has an approved registration for {list.session} yet.</div></PBody> : null}
      </Panel>
      <div className="row">
        <Btn kind="primary" size="md" disabled={busy || conf || !may || !list.rows.length} onClick={() => void send("POST", `${base}/confirm`, {}, `${list.name} list confirmed for ${list.session}`)}>{conf ? `Confirmed ${day(list.confirmedAt, false)}` : `Confirm ${ready} students to the Academic Office`}</Btn>
        <Btn kind="ghost" onClick={() => download(`${list.code}-${list.session.replace("/", "-")}-list.csv`, csv([["Admission number", "Name", "Department", "Units", "State"], ...list.rows.map((r) => [r.admissionNo, `${r.surname}, ${r.otherNames}`, r.deptName, r.units, r.queryReason ? `Query: ${r.queryReason}` : "For matriculation"])]))}>Export the list</Btn>
      </div>
      {query ? (
        <Modal title="Put this name under query" sub="With the reason, and the office that clears it" onClose={() => setQuery(null)}
          foot={<><Btn kind="ghost" onClick={() => setQuery(null)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={busy || !reason.trim()} onClick={async () => { if (await send("PUT", `${base}/queries/${query}`, { reason, office }, `Query: ${reason}`)) setQuery(null); }}>Query</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="q-why" label="Reason" full><input id="q-why" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} autoComplete="off" /></Field>
            <Field id="q-office" label="Who clears it"><select id="q-office" className="ctl" value={office} onChange={(e) => setOffice(e.target.value)}><option>Faculty Officer</option><option>Bursary</option><option>Head of Department</option><option>Academic Office</option></select></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
