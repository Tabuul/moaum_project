"use client";

/**
 * V532: how fast e-mail goes over SMTP — a minute's and a day's most (Microsoft 365 allows one mailbox 30 and 10,000), what was
 * tried, what may go now and how long the waiting e-mail takes; set by the Directorate of ICT, admin and super. The dispatcher
 * counts the pace in the database, so it holds across every instance of the API.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { limitOf, paceWords, type SmtpPace } from "@/lib/mail-sending";

export function SmtpPaceBlock({ pace, smtp, waiting, may }: { pace: SmtpPace; smtp: boolean; waiting: number; may: boolean }) {
  const router = useRouter();
  const [perMinute, setPerMinute] = useState(pace.perMinute ? String(pace.perMinute) : "");
  const [perDay, setPerDay] = useState(pace.perDay ? String(pace.perDay) : "");
  const [problem, setProblem] = useState<Problem | null>(null);

  async function save() {
    setProblem(null);
    const m = limitOf(perMinute);
    const d = limitOf(perDay);
    const r = await fetch("/api/bff/api/v1/platform/notices/smtp-pace", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`SMTP pace set: ${m ?? "no limit"} a minute, ${d ?? "no limit"} a day`) },
      body: JSON.stringify({ perMinute: m, perDay: d }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
      setProblem(p);
      notifyProblem(p);
      return;
    }
    notify("SMTP pace saved");
    router.refresh();
  }

  return (
    <PBody style={{ borderTop: "1px solid var(--line-2)" }}>
      <div className="row"><b>E-mail pace</b>{smtp ? <Pil kind="ok">applies: e-mail goes over SMTP</Pil> : <Pil kind="grey">not in use: e-mail is not going over SMTP</Pil>}</div>
      <div className="sub2">{paceWords(pace, waiting)}</div>
      <div className="sub2">
        Microsoft 365 allows one mailbox 30 e-mails a minute and 10,000 a day; sending faster gets it throttled and then blocked from sending. Leave a box empty for
        no limit, only for an SMTP service with limits of its own.
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {may ? (
        <div className="row row--wrap mt-1" style={{ alignItems: "flex-end", gap: 8 }}>
          <Field id="pace-minute" label="E-mails a minute"><input id="pace-minute" className="ctl tnum" inputMode="numeric" value={perMinute} onChange={(e) => setPerMinute(e.target.value.replace(/[^0-9]/g, ""))} placeholder="no limit" style={{ maxWidth: 140 }} /></Field>
          <Field id="pace-day" label="E-mails a day"><input id="pace-day" className="ctl tnum" inputMode="numeric" value={perDay} onChange={(e) => setPerDay(e.target.value.replace(/[^0-9]/g, ""))} placeholder="no limit" style={{ maxWidth: 160 }} /></Field>
          <Btn kind="secondary" onClick={save}>Save the pace</Btn>
        </div>
      ) : null}
    </PBody>
  );
}
