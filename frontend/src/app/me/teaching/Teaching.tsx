"use client";

/** sTimetable / my allocation — what the lecturer teaches this session: the offerings the department
 *  allocated to them and each one's class slots (the teaching timetable), in one place. Read-only. */
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { semesterName } from "@/lib/student-portal";

interface Slot { weekday: number; starts_at: string; ends_at: string; venue: string; kind: string }
export interface Offering { id: string; code: string; title: string; units: number; level: number; semester: number; role: string; dept_name: string; roll: number; slots: Slot[] }
export interface Teaching { session: string; offerings: Offering[] }

const DAY = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const ROLE: Record<string, "ok" | "info" | "grey"> = { Lecturer: "ok", "Second examiner": "info", "Co-lecturer": "info" };
const hhmm = (t: string) => (t ?? "").slice(0, 5);

export function TeachingView({ data, sessions }: { data: Teaching; sessions: string[] }) {
  const router = useRouter();
  const units = data.offerings.reduce((n, o) => n + (o.role === "Lecturer" ? o.units : 0), 0);
  const roll = data.offerings.reduce((n, o) => n + o.roll, 0);
  const slots = data.offerings.reduce((n, o) => n + o.slots.length, 0);
  return (
    <>
      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap" }}>
        <div className="field" style={{ minWidth: 160, margin: 0 }}><label htmlFor="tt-s">Session</label>
          <select id="tt-s" className="ctl" value={data.session} onChange={(e) => router.push(`/me/teaching?session=${encodeURIComponent(e.target.value)}`)}>
            {(sessions.includes(data.session) ? sessions : [data.session, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </div>
      </div></div>

      {data.offerings.length === 0 ? (
        <Note kind="info" title={`Nothing is allocated to you for ${data.session}`}>
          A course appears here once your Head of Department allocates it to you for the session. Until then there is
          nothing to teach and nothing on your timetable.
        </Note>
      ) : (
        <>
          <Tiles items={[
            ["Courses", String(data.offerings.length), null, `${data.session} · allocated to you`],
            ["Units you lead", String(units), null, "As the lead lecturer"],
            ["Students", String(roll), null, "On your rolls"],
            ["Class slots", String(slots), slots ? null : "var(--chrome)", slots ? "On your timetable" : "No slots set yet"],
          ]} />
          <Panel title="Your teaching this session" right={`${data.offerings.length} course${data.offerings.length === 1 ? "" : "s"}`}>
            <DTable
              cols={["Course|mid", "Title", "Role|mid", "Level|num", "Semester|mid", "Roll|num", "Timetable"]}
              rows={data.offerings.map((o) => [
                <Link key="c" href={`/lms/${o.id}`} className="tnum" style={{ fontWeight: 600 }}>{o.code}</Link>,
                <span className="sub2" key="t">{o.title}</span>,
                <Pil kind={ROLE[o.role] ?? "grey"} key="r">{o.role}</Pil>,
                <span className="tnum" key="l">{o.level}</span>,
                <span key="s">{semesterName(o.semester)}</span>,
                <span className="tnum" key="n">{o.roll}</span>,
                <span className="sub2" key="tt">{o.slots.length
                  ? o.slots.map((s) => `${DAY[s.weekday]} ${hhmm(s.starts_at)}–${hhmm(s.ends_at)} · ${s.venue}${s.kind !== "LECTURE" ? ` (${s.kind.toLowerCase()})` : ""}`).join("  ·  ")
                  : <span style={{ color: "var(--chrome)" }}>No class slot set</span>}</span>,
              ])}
              texts={data.offerings.map((o) => `${o.code} ${o.title} ${o.role}`)}
            />
            <PBody><div className="sub2">Class slots are set on the class-list screen for each course. A course code links to its course space.</div></PBody>
          </Panel>
        </>
      )}
    </>
  );
}
