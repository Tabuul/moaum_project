"use client";

/** s/reghistory — the student's course-registration history: every session and semester they
 *  registered, the courses on each, carryovers marked, and the status of the registration. Read
 *  from the record; nothing is entered here. */
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Entry { courseCode: string; title: string; units: number; entryType: string; status: string }
interface Reg { id: string; session: string; semester: number; status: string; level: number; submitted_at: string | null; approved_at: string | null; units: number; entries: Entry[] }
export interface RegHistory { matricNo: string | null; admissionNo: string | null; name: string; programme: string; history: Reg[] }

const SEM = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");
const REG_PILL: Record<string, "ok" | "info" | "warn" | "grey" | "bad"> = { APPROVED: "ok", LOCKED: "ok", SUBMITTED: "info", DRAFT: "warn", RETURNED: "bad" };
const day = (s: string | null) => (s ? new Date(s).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function RegistrationHistory({ d }: { d: RegHistory }) {
  const h = d.history;
  const sessions = new Set(h.map((r) => r.session)).size;
  const entries = h.reduce((n, r) => n + r.entries.length, 0);
  const carryovers = h.reduce((n, r) => n + r.entries.filter((e) => e.entryType === "CARRYOVER").length, 0);

  return (
    <>
      <Note kind="info" title="Your course registration, session by session">
        Every semester you registered courses, with the courses on each, the units, and whether a course was a fresh registration or a <b>carryover</b>. This is the record the Faculty Officer approved and the score sheets were built from &mdash; it is read here, never entered.
      </Note>

      <Tiles items={[
        ["Registrations", String(h.length), null, `${sessions} session${sessions === 1 ? "" : "s"}`],
        ["Courses registered", String(entries), null, "across all semesters"],
        ["Carryovers", String(carryovers), carryovers ? "var(--red-ink)" : "var(--green-ink)", carryovers ? "repeated courses" : "none repeated"],
        ["Identifier", d.matricNo ?? d.admissionNo ?? "—", null, d.programme],
      ]} />

      {h.length ? h.map((r) => (
        <Panel key={r.id}
          title={`${r.session} · ${SEM(r.semester)} semester`}
          right={<span style={{ display: "inline-flex", gap: 8, alignItems: "center" }}>
            <span className="sub2">{r.level} Level · {r.units} units</span>
            <Pil kind={REG_PILL[r.status] ?? "grey"}>{r.status}</Pil>
          </span>}>
          {r.entries.length ? (
            <DTable cols={["Course", "Title", "Units|mid", "Type|mid", "Status|mid"]} rows={r.entries.map((e) => [
              <b className="tnum" key="c">{e.courseCode}</b>,
              <span key="t">{e.title}</span>,
              <span className="tnum" key="u">{e.units}</span>,
              e.entryType === "CARRYOVER" ? <Pil kind="bad" key="ty">Carryover</Pil> : <span className="sub2" key="ty">Current</span>,
              <span className="sub2" key="s">{e.status}</span>,
            ])} />
          ) : <PBody><div className="sub2">No course on this registration.</div></PBody>}
          <PBody><div className="sub2">Submitted {day(r.submitted_at)} · approved {day(r.approved_at)}</div></PBody>
        </Panel>
      )) : (
        <Panel title="No registration yet">
          <PBody><div className="sub2">You have not registered courses in any session yet. Your registrations will appear here once you register and your Faculty Officer approves them.</div></PBody>
        </Panel>
      )}
    </>
  );
}
