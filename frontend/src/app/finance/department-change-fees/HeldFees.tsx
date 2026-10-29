"use client";

/**
 * V702: the students held a level behind after a change of department (V696). They are charged the held level's fee (the University's
 * word of 29 October 2026); beside it, what the session would charge without the hold — the cohort they entered with, the record where
 * it stood — read on the server with the hold lifted and undone, so nothing on a record changes. For the Bursary to see what the hold
 * does to each student's fees, and to answer a student who asks.
 */
import { useState } from "react";
import { useJson } from "@/lib/use-json";
import { Btn, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Problem } from "@/lib/api";
import { differenceWords, HELD_HEADERS, heldCells, naira, narrowHeld, type HeldFees } from "@/lib/held-fees";

type Only = "changed" | "higher" | "lower" | "all";

export function HeldFeesDesk({ session: first, sessions }: { session: string; sessions: string[] }) {
  const [session, setSession] = useState(first);
  const [only, setOnly] = useState<Only>("changed");
  const [q, setQ] = useState("");
  const { data, failed, loading } = useJson<HeldFees>(`/api/bff/api/v1/finance/department-change-fees?session=${encodeURIComponent(session)}`, 0);
  const rows = data ? narrowHeld(data.rows, q, only) : [];

  async function exportXlsx() {
    if (!data) return;
    try {
      const cells = rows.map((r) => heldCells(r));
      downloadBlob(await brandedXlsx("Held students' fees", HELD_HEADERS, cells, {
        serial: docSerial("HSF"), sheetName: "Held students",
        meta: [["Session", data.session], ["Listed", only === "all" ? "Every held student" : only === "changed" ? "Those whose fee the hold changes" : only === "higher" ? "Charged more held" : "Charged less held"]],
      }), `Held students fees ${data.session.replace("/", "-")}.xlsx`);
      notify(`Export completed — ${cells.length.toLocaleString()} student${cells.length === 1 ? "" : "s"}.`);
    } catch (e) {
      notifyProblem(e as Problem, "The export did not complete");
    }
  }

  return (
    <>
      {failed ? <Note kind="bad" title="Unable to read the held students' fees">{failed}</Note> : null}
      <Note kind="info" title="Charged the held level's fee">
        A student who changed department is held a level behind the cohort they entered with, and charged the fee of the level held. Beside it is what the session would charge without the hold; nothing here changes a charge or a record.
      </Note>
      {data ? (
        <Tiles items={[
          ["Held students", data.students.toLocaleString(), null, `In ${data.session}`],
          ["Charged more held", data.higher.toLocaleString(), data.higher ? "var(--red-ink)" : null, `${naira(data.higherBy)} in all`],
          ["Charged less held", data.lower.toLocaleString(), data.lower ? "var(--green-ink)" : null, `${naira(data.lowerBy)} in all`],
          ["Charged held", naira(data.chargedHeld), null, `${naira(data.chargedUnheld)} without the hold`],
        ]} />
      ) : null}
      <Panel title={data ? `Held students' fees · ${data.session}` : "Held students' fees"} right={<span className="row row--inline">
        {loading ? <span className="sub2">Reading the charges…</span> : null}
        <select className="ctl" value={session} onChange={(e) => setSession(e.target.value)} aria-label="Session">
          {(sessions.includes(session) ? sessions : [session, ...sessions]).map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
        <Btn kind="ghost" disabled={!rows.length} onClick={() => void exportXlsx()}>Excel</Btn>
      </span>}>
        <PBody>
          <div className="row" style={{ gap: 6, margin: "0 0 8px" }}>
            <Tabs<Only> label="Which students" value={only} onChange={setOnly} items={[
              { id: "changed", label: "Fee changed" }, { id: "higher", label: "More held", count: data?.higher ?? 0 },
              { id: "lower", label: "Less held", count: data?.lower ?? 0 }, { id: "all", label: "Every held student", count: data?.students ?? 0 }]} />
            <span className="grow" />
            <input className="ctl" style={{ maxWidth: 300 }} placeholder="Search name, matric, programme" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Search the held students" />
          </div>
          {data ? (
            <DTable pageSize={50} cols={["S/N|num", "Student", "Programme", "Level held|mid", "Without the hold|mid", "Charged held|num", "Without the hold|num", "Difference"]}
              rows={rows.map((r, i) => [i + 1,
                <span key="s">{r.studentName}<span className="sub2 tnum" style={{ display: "block" }}>{r.number ?? "—"}</span></span>,
                r.programme ?? r.programmeCode, `${r.heldLevel}${r.heldSpillover?.startsWith("SPILLOVER") ? " (spillover)" : ""}`, r.unheldLevel,
                naira(r.chargedHeld), naira(r.chargedUnheld),
                <Pil key="d" kind={Number(r.difference) > 0 ? "bad" : Number(r.difference) < 0 ? "ok" : "grey"}>{differenceWords(Number(r.difference))}</Pil>])}
              texts={rows.map((r) => `${r.studentName} ${r.number ?? ""} ${r.programmeCode}`)} />
          ) : null}
          {data && !rows.length && !loading ? <Note kind="ok" title="No student listed">{only === "all" ? "No student is held after a change of department in this session." : "No held student's fee is changed by the hold in this session."}</Note> : null}
        </PBody>
      </Panel>
    </>
  );
}
