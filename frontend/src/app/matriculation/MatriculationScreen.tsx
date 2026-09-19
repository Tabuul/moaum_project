"use client";

/** tMatriculation — proto/part39.html: one run, one sequence, one transaction, over the confirmed lists. */
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { MatriculationOverview } from "@/lib/matriculation";
import { Note, Panel, PBody, Pil, RoleLine, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Steps, TwoCol, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function MatriculationScreen({ overview: o, actingOffice }: { overview: MatriculationOverview; actingOffice: string | null }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const t = o.totals;
  const done = o.runs.length > 0;
  const last = o.runs[0];
  const may = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const outstanding = o.faculties.filter((f) => f.registered > 0 && f.state !== "CONFIRMED");

  async function run() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/matriculation/sessions/${o.session}/run`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Matriculation run for ${o.session}`) }, body: "{}" });
      if (!r.ok) setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
      else { notify(`Matriculation run for ${o.session}`); router.refresh(); }
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <RoleLine allowed={["academic", "registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may}
        action="Confirming faculty lists and issuing matriculation numbers" />
      <Note kind={done && !t.confirmed ? "ok" : t.pending ? "bad" : t.confirmed ? "info" : "info"}
        title={done && !t.confirmed ? `${last.issued.toLocaleString()} matriculation numbers issued in one run`
          : t.pending ? `${t.pending} faculty list${t.pending === 1 ? " is" : "s are"} not confirmed, so the run cannot start`
          : t.confirmed ? "Every faculty list is confirmed — the run may start"
          : `Nobody is on a faculty list for ${o.session} yet`}>
        {done && !t.confirmed ? `One transaction, one sequence, ${day(last.runAt)}. Every number is contiguous within its department and session, and every one belongs to a student who paid, registered and was confirmed by her Faculty Officer. The numbers are now circulated to the faculties and to the students.`
          : t.pending ? "The run allocates every number or none. Starting it with a faculty outstanding would either leave those students unmatriculated after their classmates, or force a second run whose numbers sit at the end of the sequence rather than beside their department’s — and a matriculation number, once issued, cannot be exchanged for a tidier one."
          : t.confirmed ? "Confirm nothing further and press the button. The run is a single transaction: if it fails at the four-thousandth student it allocates nothing, and is repeated."
          : "A faculty list is generated from approved course registrations. Students appear on it the moment their registration for the session is approved; nobody types a name."}
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["Registered students", t.registered.toLocaleString(), null, "Approved registrations, all faculties"],
        ["Confirmed by Faculty Officers", t.confirmed.toLocaleString(), t.queried ? "var(--red-ink)" : null, t.queried ? `${t.queried} under query` : "Ready to matriculate"],
        ["Faculties outstanding", String(t.pending), t.pending ? "var(--red-ink)" : "var(--green-ink)", t.pending ? `${outstanding.map((f) => f.name).slice(0, 2).join(", ")}${outstanding.length > 2 ? " and more" : ""} not returned` : `All ${o.faculties.length} in`],
        ["Numbers issued", done ? o.runs.reduce((n, r) => n + r.issued, 0).toLocaleString() : "—", done ? "var(--green-ink)" : "var(--faint)", done ? `Run ${last.ref}, ${day(last.runAt)}` : "No run has been made"],
      ]} />
      <Note kind="info" title="The faculty list is generated, not typed">
        A Faculty Officer opens the list of students with an approved course registration for the session and confirms it. He does not key names, and he cannot add one: a student who did not register does not appear, and a student who registered cannot be left off. It is the same rule as the score sheet, for the same reason — a list somebody typed is a list somebody can leave a name off, and the omission is invisible because the list still looks complete.
      </Note>
      <Panel title="Faculty lists" right={`Generated from approved registrations for ${o.session}`}>
        <DTable
          cols={["Faculty", "Faculty Officer", "Registered|mid", "Confirmed|mid", "State|mid", "Action|num"]}
          rows={o.faculties.map((f) => [
            <strong key="f">{f.name}</strong>, <span className="sub2" key="o">{f.officer ?? "—"}</span>,
            <span className="tnum" key="r">{f.registered}</span>,
            <span className="tnum" key="c" style={f.confirmed < f.registered ? { color: "var(--red-ink)" } : undefined}>{f.confirmed}</span>,
            f.state === "CONFIRMED" ? <Pil kind="ok" key="s">Confirmed</Pil> : f.queried ? <Pil kind="bad" key="s">{f.queried} under query</Pil> : f.registered ? <Pil kind="info" key="s">Not returned</Pil> : <Pil kind="grey" key="s">Nobody registered</Pil>,
            <Link key="a" href={`/matriculation/faculty/${f.code}?session=${encodeURIComponent(o.session)}`} className="btn btn--ghost btn--sm">Open</Link>,
          ])}
          texts={o.faculties.map((f) => `${f.name} ${f.officer ?? ""}`)}
        />
      </Panel>
      <TwoCol>
        <Panel title="What the run does" right="One transaction, one sequence">
          <PBody>
            <Steps list={[
              [done ? "done" : "now", "Reconcile the confirmed lists against admissions and finance", "Every student on a faculty list must have accepted an offer, been cleared, paid and registered. A name that fails any of the four is held back with the reason, not silently dropped."],
              [done ? "done" : "todo", "Allocate serially, within department and session", "MOAUM/MTC/26/1874 is the 1,874th Mathematics and Computer Science student of the 2026 entry. The serial comes from one sequence per department, so the numbers are contiguous."],
              [done ? "done" : "todo", "Commit, or allocate nothing at all", "A partially matriculated list leaves gaps in the sequence, and BR-007 forbids reusing them. The run is a single transaction for that reason and no other."],
              [done ? "done" : "todo", "Publish, and queue the identity cards", "The Library cannot make a card before this moment, because the card is keyed on the matriculation number."],
            ]} />
          </PBody>
        </Panel>
        <Panel title="Held back from this run" right={o.heldBack.length ? `${o.heldBack.length} student${o.heldBack.length === 1 ? "" : "s"}` : "Nobody held back"}>
          <PBody>
            <DTable cols={["Admission number", "Name", "Why|num"]} rows={o.heldBack.map((h) => [<span className="tnum" key="a">{h.admissionNo}</span>, <strong key="n">{h.surname}, {h.otherNames}</strong>, <span className="sub2" key="w">{h.reason} — {h.office}</span>])} />
            <Note kind="bad" title="Held back is not rejected, and it is not silent">
              Each of these keeps an admission number, keeps their registration and keeps their fee record. Each has a named reason and a named office to go to. They are matriculated in the next run once the reason is cleared — what they must not do is acquire a permanent number while the reason stands.
            </Note>
          </PBody>
        </Panel>
      </TwoCol>
      <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
        <button className="btn btn--primary" disabled={busy || !may || t.pending > 0 || t.confirmed === 0} onClick={() => void run()}>{busy ? "Running…" : `Run matriculation for ${t.confirmed.toLocaleString()} students`}</button>
        <span className="sub2">{t.pending ? `Disabled while ${outstanding.map((f) => f.name).join(", ")} ${outstanding.length === 1 ? "is" : "are"} outstanding` : t.confirmed === 0 ? (done ? `Run ${last.ref} · ${day(last.runAt)} · nobody is waiting for the next run` : "Nobody is on a confirmed list yet") : "This cannot be undone. A matriculation number is permanent."}</span>
      </div>
      {done ? (
        <Panel title={`Run ${last.ref}`} right="A sample of what was allocated">
          <DTable cols={["Admission number", "Matriculation number", "Name", "Department|num"]} rows={o.sample.map((s) => [<span className="tnum sub2" key="a">{s.admissionNo}</span>, <b className="tnum" key="m">{s.matricNo}</b>, <strong key="n">{s.surname}, {s.otherNames}</strong>, <span className="sub2" key="d">{s.deptName}</span>])} />
          <PBody>
            <Note kind="info" title="The admission number is retired, not deleted">
              It stays on the record. A receipt, a screening slip or a clearance note issued under it is still that student’s document, and must still resolve to her years later.
            </Note>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
