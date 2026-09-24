"use client";

/** s/reghistory — the student's course registration. The current session shows first; History
 *  reveals every earlier session. Each course carries its code, title, lecturer, unit and type
 *  (GST / Elective / Core), with carryovers listed first. Read from the record; nothing is entered here. */
import { useMemo, useState } from "react";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Entry { courseCode: string; title: string; units: number; entryType: string; status: string; kind?: string; lecturer?: string | null; courseSemester?: number }
interface Reg { id: string; session: string; semester: number; status: string; level: number; submitted_at: string | null; approved_at: string | null; units: number; entries: Entry[] }
export interface RegHistory { matricNo: string | null; admissionNo: string | null; name: string; programme: string; history: Reg[] }

const SEM = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");
const REG_PILL: Record<string, "ok" | "info" | "warn" | "grey" | "bad"> = { APPROVED: "ok", LOCKED: "ok", SUBMITTED: "info", DRAFT: "warn", RETURNED: "bad" };
const day = (s: string | null) => (s ? new Date(s).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

/** the academic type shown in the Type column: GST, Elective or Core (Core/Required → Core) */
function courseType(e: Entry): string {
  const k = (e.kind ?? "").toLowerCase();
  if (k === "gst") return "GST";
  if (k === "elective") return "Elective";
  if (k === "core" || k === "compulsory" || k === "required") return "Core";
  const t = (e.entryType ?? "").toUpperCase();
  if (t === "GST") return "GST";
  if (t === "ELECTIVE") return "Elective";
  return "Core";
}

/** display order: carryover first, then GST, then Core, then Elective */
function orderRank(e: Entry): number {
  if ((e.entryType ?? "").toUpperCase() === "CARRYOVER") return 0;
  const t = courseType(e);
  return t === "GST" ? 1 : t === "Core" ? 2 : 3;
}

function RegPanel({ r }: { r: Reg }) {
  return (
    <Panel
      title={`${r.session} · ${SEM(r.semester)} semester`}
      right={<span className="row row--inline">
        <span className="sub2">{r.level} Level · {r.units} units</span>
        <Pil kind={REG_PILL[r.status] ?? "grey"}>{r.status}</Pil>
      </span>}>
      {r.entries.length ? (
        <DTable cols={["Course code", "Course title", "Lecturer", "Unit|mid", "Type|mid", "Status|mid"]} rows={[...r.entries].sort((a, b) => orderRank(a) - orderRank(b) || a.courseCode.localeCompare(b.courseCode)).map((e) => {
          const co = e.entryType === "CARRYOVER";
          return [
            <b className="tnum" key="c">{e.courseCode}</b>,
            <span key="t">{e.title}</span>,
            <span className="sub2" key="l">{e.lecturer ?? "—"}</span>,
            <span className="tnum" key="u">{e.units}</span>,
            <span className="sub2" key="ty">{courseType(e)}</span>,
            co ? <Pil kind="bad" key="s">Carryover</Pil> : <span className="sub2" key="s">{e.status === "APPROVED" || e.status === "REGISTERED" ? "Registered" : e.status.charAt(0) + e.status.slice(1).toLowerCase()}</span>,
          ];
        })} />
      ) : <PBody><div className="sub2">No course on this registration.</div></PBody>}
      <PBody><div className="sub2">Submitted {day(r.submitted_at)} · approved {day(r.approved_at)}</div></PBody>
    </Panel>
  );
}

export function RegistrationHistory({ d }: { d: RegHistory }) {
  const h = d.history;
  const [showAll, setShowAll] = useState(false);

  const latestSession = h[0]?.session ?? null;
  const current = useMemo(() => h.filter((r) => r.session === latestSession), [h, latestSession]);
  const earlier = useMemo(() => h.filter((r) => r.session !== latestSession), [h, latestSession]);

  const sessions = new Set(h.map((r) => r.session)).size;
  const entries = h.reduce((n, r) => n + r.entries.length, 0);
  const carryovers = h.reduce((n, r) => n + r.entries.filter((e) => e.entryType === "CARRYOVER").length, 0);

  return (
    <>
      <Note kind="info" title="Your course registration">
        The current session shows here. A course carries its code, title, lecturer, unit and type — GST, Elective or Core —
        and any <b>carryover</b> is listed first. This is the record the Faculty Officer approved and the score sheets were
        built from; it is read here, never entered. Open <b>History</b> for earlier sessions.
      </Note>

      <Tiles items={[
        ["Registrations", String(h.length), null, `${sessions} session${sessions === 1 ? "" : "s"}`],
        ["Courses registered", String(entries), null, "across all semesters"],
        ["Carryovers", String(carryovers), carryovers ? "var(--red-ink)" : "var(--green-ink)", carryovers ? "repeated courses" : "none repeated"],
        ["Identifier", d.matricNo ?? d.admissionNo ?? "—", null, d.programme],
      ]} />

      {current.length ? current.map((r) => <RegPanel key={r.id} r={r} />) : (
        <Panel title="No registration yet">
          <PBody><div className="sub2">You have not registered courses in any session yet. Your registrations will appear here once you register and your Faculty Officer approves them.</div></PBody>
        </Panel>
      )}

      {earlier.length ? (
        <>
          <div className="row mt-1">
            <Btn kind="ghost" onClick={() => setShowAll((v) => !v)}>{showAll ? "Hide history" : `History — ${earlier.length} earlier registration${earlier.length === 1 ? "" : "s"}`}</Btn>
          </div>
          {showAll ? earlier.map((r) => <RegPanel key={r.id} r={r} />) : null}
        </>
      ) : null}
    </>
  );
}
