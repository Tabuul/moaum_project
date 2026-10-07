"use client";

/**
 * The JUPEB lecture timetable as the University prints it (V351): the days down the side, the hours across, each cell the
 * courses taught in that hour with their room — "GEO 001 (LR8)", a practical as "PHY PRACTICAL (LAB)" — and an hour no day
 * uses marked BREAK. A slot of two hours shows in both. The same grid prints as the branded PDF. Also the Board's rules the
 * JUPEB Office checks its timetable against: every course at least three hours a week, every practical at least two, every
 * slot with its room.
 */
import type { ReactNode } from "react";
import { brandedPrint, docSerial } from "@/lib/exportbrand";
import { WEEKDAYS, type Slot } from "@/lib/jupeb";

const minutes = (t: string) => { const [h, m] = t.split(":").map(Number); return h * 60 + (m || 0); };
const clock = (min: number) => { const h = Math.floor(min / 60); const h12 = h % 12 === 0 ? 12 : h % 12; return `${h12}:${String(min % 60).padStart(2, "0")}${h < 12 ? "AM" : "PM"}`; };
const ORDINAL = ["", "first", "second"];

/** the programme's day for a semester, from the whole timetable: first and last hour, and the hours no lecture uses (BREAK) */
export interface Frame { semester: number; from: number; to: number; breaks: number[] }

/** what a slot shows in a cell */
export const cellText = (s: Slot) => `${s.practical ? `${s.code.split("/")[0]} PRACTICAL` : s.course_code ?? s.code} (${s.venue ?? "room to confirm"})`;

function hoursOf(slots: Slot[]) {
  if (!slots.length) return [] as number[];
  const from = Math.floor(Math.min(...slots.map((s) => minutes(s.starts_at))) / 60);
  const to = Math.ceil(Math.max(...slots.map((s) => minutes(s.ends_at))) / 60);
  return Array.from({ length: to - from }, (_, i) => (from + i) * 60);
}

/** with a frame (a student's own subjects), the programme's hours and breaks; without (the whole timetable), worked out from the slots */
function layout(slots: Slot[], frame?: Frame) {
  const days = [...new Set(slots.map((s) => s.weekday))].sort((a, b) => a - b);
  const at = (day: number, h: number) => slots.filter((s) => s.weekday === day && minutes(s.starts_at) < h + 60 && h < minutes(s.ends_at))
    .sort((a, b) => Number(!!b.practical) - Number(!!a.practical) || (a.course_code ?? a.code).localeCompare(b.course_code ?? b.code));
  if (frame) {
    const own = hoursOf(slots);
    const from = Math.min(frame.from * 60, ...own), to = Math.max(frame.to * 60, ...own.map((h) => h + 60));
    return { hours: Array.from({ length: (to - from) / 60 }, (_, i) => from + i * 60), days, at, breakHour: (h: number) => frame.breaks.includes(h / 60) };
  }
  return { hours: hoursOf(slots), days, at, breakHour: (h: number) => days.every((d) => at(d, h).length === 0) };
}

export function TimetableGrid({ slots, frame }: { slots: Slot[]; frame?: Frame }) {
  const { hours, days, at, breakHour } = layout(slots, frame);
  if (!slots.length) return null;
  const th: React.CSSProperties = { border: "1px solid var(--line-2)", padding: "6px 8px", textAlign: "left", fontSize: 12, background: "var(--panel-2)", whiteSpace: "nowrap" };
  const td: React.CSSProperties = { border: "1px solid var(--line-2)", padding: "6px 8px", verticalAlign: "top", fontSize: 12.5, minWidth: 96 };
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ borderCollapse: "collapse", width: "100%" }}>
        <thead>
          <tr>
            <th style={th}>DAY/TIME</th>
            {hours.map((h) => <th key={h} style={th}>{clock(h)}–<br />{clock(h + 60)}</th>)}
          </tr>
        </thead>
        <tbody>
          {days.map((d) => (
            <tr key={d}>
              <th style={{ ...th, background: "var(--panel)" }}>{WEEKDAYS[d].toUpperCase()}</th>
              {hours.map((h) => {
                const here = at(d, h);
                return (
                  <td key={h} style={{ ...td, ...(breakHour(h) ? { textAlign: "center", fontWeight: 700, color: "var(--muted)" } : {}) }}>
                    {breakHour(h) ? "BREAK" : here.map((s): ReactNode => (
                      <div key={s.id} style={{ fontWeight: s.practical ? 700 : 400 }} title={s.note ?? undefined}>{cellText(s)}{s.class_name ? <span className="sub2"> · {s.class_name}</span> : null}</div>
                    ))}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** the grid as the University's branded PDF */
export function printGrid(slots: Slot[], session: string, semester: number, sub = "", frame?: Frame) {
  const { hours, days, at, breakHour } = layout(slots, frame);
  brandedPrint(`Joint Universities Preliminary Examinations Board (JUPEB) — lecture time table for ${ORDINAL[semester] ?? ""} semester ${session} academic session`, sub,
    ["Day/Time", ...hours.map((h) => `${clock(h)}–${clock(h + 60)}`)],
    days.map((d) => [WEEKDAYS[d].toUpperCase(), ...hours.map((h) => (breakHour(h) ? "BREAK" : at(d, h).map(cellText).join("; ")))]),
    docSerial("JUPEBTT"), { orientation: "landscape" });
}

/** the Board's rules: every course at least three hours a week, every practical at least two, every slot with its room */
export function boardRules(slots: Slot[]) {
  const dur = (s: Slot) => (minutes(s.ends_at) - minutes(s.starts_at)) / 60;
  const courses = new Map<string, number>();
  for (const s of slots.filter((x) => !x.practical)) courses.set(s.course_code ?? s.code, (courses.get(s.course_code ?? s.code) ?? 0) + dur(s));
  const practicals = new Map<string, number>();
  for (const s of slots.filter((x) => x.practical)) practicals.set(s.code, (practicals.get(s.code) ?? 0) + dur(s));
  return {
    short: [...courses.entries()].filter(([, h]) => h < 3).map(([c, h]) => ({ course: c, hours: h })),
    shortPractical: [...practicals.entries()].filter(([, h]) => h < 2).map(([c, h]) => ({ subject: c, hours: h })),
    noRoom: slots.filter((s) => !s.venue),
    courses: courses.size, practicals: practicals.size,
  };
}
