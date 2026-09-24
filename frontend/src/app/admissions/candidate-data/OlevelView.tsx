"use client";

/**
 * One candidate's O'Level results as JAMB sent them, sitting by sitting —
 * WAEC, NECO and NABTEB shown apart — and, for the Academic Office only,
 * the screening score they carry under the session's grading. The API
 * withholds the score from every other office and from the applicant; this
 * modal shows what it is given and says whose the score is.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface OlevelGrade { subject: string; grade: string; points: number }
export interface OlevelSitting { body: string; type: string | null; year: string | null; examNumber: string | null; subjects: OlevelGrade[] }
export interface Screening { sittings: number; relevantKnown: boolean; counted: OlevelGrade[]; points: number; bonus: number; total: number }
export interface Olevel {
  session: string;
  jambKey: string;
  programme: string | null;
  programmeCode: string | null;
  sittings: OlevelSitting[];
  screening: Screening | null;
  screeningIs: string;
}

const BODY: Record<string, string> = { WAEC: "WAEC", NECO: "NECO", NABTEB: "NABTEB", OTHER: "Other body" };

export function OlevelView({ session, jambKey, name, onClose }: { session: string; jambKey: string; name: string; onClose: () => void }) {
  const [data, setData] = useState<Olevel | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/candidate-data/${encodeURIComponent(jambKey)}/olevel`, { cache: "no-store" });
      const body = await r.json().catch(() => null);
      if (!live) return;
      if (r.ok) setData(body as Olevel);
      else setProblem(body && typeof body === "object" && "status" in body ? (body as Problem) : { status: r.status, title: r.statusText });
    })();
    return () => { live = false; };
  }, [session, jambKey]);

  const s = data?.screening ?? null;
  return (
    <Modal
      title={`O’Level results · ${name}`}
      sub={`${jambKey}${data?.programme ? ` · ${data.programme}` : ""} · ${data ? `${data.sittings.length} sitting${data.sittings.length === 1 ? "" : "s"}` : "reading…"}`}
      wide
      onClose={onClose}
      foot={<><span className="grow" /><Btn kind="ghost" onClick={onClose}>Close</Btn></>}
    >
      {problem ? <ProblemNotice problem={problem} /> : null}
      {data && !data.sittings.length ? (
        <Note kind="info" title="No O’Level result has been recorded for this candidate">
          The results arrive in JAMB&rsquo;s O&rsquo;Level download, one row per subject; upload it above and it attaches on the registration number.
        </Note>
      ) : null}
      {data?.sittings.map((st, i) => (
        <div key={i} className="mb-3">
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
            <Pil kind="grey">{BODY[st.body] ?? st.body}</Pil>
            <b>{st.type ?? st.body}</b>
            <span className="sub2">{st.year ? `${st.year}` : ""}{st.examNumber ? ` · exam no. ${st.examNumber}` : ""}</span>
          </div>
          <DTable
            cols={["Subject", "Grade|mid", ...(s ? ["Points|num"] : [])]}
            rows={st.subjects.map((g) => [
              <span key="s">{g.subject}</span>,
              <b className="tnum" key="g">{g.grade}</b>,
              ...(s ? [<span className="tnum" key="p">{g.points}</span>] : []),
            ])}
          />
        </div>
      ))}
      {data && data.sittings.length ? (
        s ? (
          <>
            <Tiles items={[
              ["Subjects counted", String(s.counted.length), null, s.relevantKnown ? "The programme’s relevant subjects" : "Every subject sat · relevant subjects not stated"],
              ["Points", String(s.points), null, "Best grade per subject, across the sittings"],
              ["Sitting bonus", String(s.bonus), null, s.sittings === 1 ? "One sitting" : `${s.sittings} sittings combined`],
              ["O’Level screening score", String(s.total), "var(--chrome)", `${data.session} grading`],
            ]} />
            <DTable
              cols={["Counted subject", "Grade|mid", "Points|num"]}
              rows={s.counted.map((g) => [<strong key="s">{g.subject}</strong>, <b className="tnum" key="g">{g.grade}</b>, <b className="tnum" key="p">{g.points}</b>])}
            />
            {!s.relevantKnown ? (
              <Note kind="info" title="Provisional: the programme’s relevant subjects are not stated">
                Until the admission settings name the O&rsquo;Level subjects relevant to {data.programme ?? "this programme"}, the best subjects of all those sat are counted. State them on the programme&rsquo;s rule under Admission settings.
              </Note>
            ) : null}
          </>
        ) : (
          <Note kind="info" title={`The screening score is the ${data.screeningIs}’s`}>
            The results are shown as JAMB sent them. The score they carry is computed for the {data.screeningIs} and shown to nobody else &mdash; not to other offices, and not to the applicant.
          </Note>
        )
      ) : null}
    </Modal>
  );
}
