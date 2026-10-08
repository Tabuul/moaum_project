"use client";
/** V367: which courses are the office's. A course is the GST office's when its subject is a General Studies code family, the EPS
 *  office's for an Entrepreneurship family or an entrepreneurship title, and no office's otherwise — such a course was marked general
 *  by a course upload (status G) but is a department's. The office claims a course its families miss, gives back to its department
 *  a course it does not run, and keeps its own families; nothing here touches a registration, a result or a payment. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { num } from "@/lib/gst";

export interface GstFamily { prefix: string; office: "GST" | "EPS" | string; added_at: string }
export interface UnassignedCourse { code: string; title: string; level: number; semester: number; units: number; dept_code: string | null; department: string | null; programmes: number; offered_this_session: boolean }

export function GstClassification({ office, may, families, unassigned }: { office: "GST" | "EPS"; may: boolean; families: GstFamily[]; unassigned: UnassignedCourse[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [prefix, setPrefix] = useState("");
  const mine = families.filter((f) => f.office === office);
  const other = families.filter((f) => f.office !== office);

  async function call(path: string, method: string, body: unknown, reason: string, done: string) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/gst${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(done);
      router.refresh();
    } finally { setBusy(false); }
  }
  const slug = (code: string) => encodeURIComponent(code.replace(/ /g, "_"));

  return (
    <Panel title={`WHICH COURSES ARE THE ${office} OFFICE'S`} right={<span className="sub2">{num(unassigned.length)} marked general, no office&rsquo;s</span>}>
      <PBody>
        <div className="sub2">
          A course is the {office} office&rsquo;s when its subject is one of its code families{office === "EPS" ? " or its title is entrepreneurship" : ""}: {mine.length ? mine.map((f) => f.prefix).join(", ") : "none yet"}
          {other.length ? <> (the {office === "GST" ? "EPS" : "GST"} office&rsquo;s: {other.map((f) => f.prefix).join(", ")})</> : null}. Only those courses are on this desk, owe the GST fee and are examined by this office.
        </div>
        {may ? (
          <form className="row row--inline row--tight mt-1" onSubmit={(e) => { e.preventDefault(); const p = prefix.trim().toUpperCase(); if (!/^[A-Z]{2,5}$/.test(p)) { notifyProblem({ status: 422, title: "A family is the two to five letters of a course code, e.g. GNS." }); return; } void call(`/families/${p}`, "PUT", { office }, `${office} code family ${p} added`, `${p} is now a ${office} family`).then(() => setPrefix("")); }}>
            <Field id="gc-family" label={`Add a ${office} code family`}><input id="gc-family" className="ctl tnum" maxLength={5} value={prefix} onChange={(e) => setPrefix(e.target.value.toUpperCase())} placeholder={office === "GST" ? "GNS" : "ENT"} /></Field>
            <Btn kind="secondary" size="sm" type="submit" disabled={busy}>Add</Btn>
            {mine.map((f) => <Btn key={f.prefix} kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Remove ${f.prefix} from the ${office} families? Courses already filed under the office stay; new ${f.prefix} courses no longer come to it.`)) void call(`/families/${f.prefix}`, "PUT", { office: null }, `${office} code family ${f.prefix} removed`, `${f.prefix} removed`); }}>Remove {f.prefix}</Btn>)}
          </form>
        ) : null}
        {unassigned.length ? (
          <Note kind="info" title="Courses a course upload marked general that no office runs">
            A programme structure gave these courses status G (or a GST/EPS classification), but their subject is in no office&rsquo;s family. They stay with their department: they are not on this desk, owe no GST fee, and the examinations office examines them. Take one this office runs, or give it back to its department as a Core course.
          </Note>
        ) : null}
      </PBody>
      {unassigned.length ? (
        <DTable pageSize={20} cols={["Course", "Level|mid", "Department", "Programmes|num", "This session|mid", "|mid"]} rows={unassigned.map((c) => [
          <span key="c"><b className="tnum">{c.code}</b><div className="sub2">{c.title} · {c.units} units · semester {c.semester}</div></span>,
          <span key="l" className="tnum">{c.level}</span>, <span key="d" className="sub2">{c.department ?? c.dept_code ?? "—"}</span>,
          <span key="p" className="tnum">{num(c.programmes)}</span>,
          <Pil key="o" kind={c.offered_this_session ? "info" : "grey"}>{c.offered_this_session ? "Offered" : "Not offered"}</Pil>,
          may ? <span key="a" className="row row--inline row--tight">
            <Btn kind="secondary" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Take ${c.code} as a ${office} course? Its students then owe the GST fee for it, and this office examines it.`)) void call(`/${office}/courses/${slug(c.code)}/claim`, "POST", {}, `${c.code} taken by the ${office} office`, `${c.code} is now a ${office} course`); }}>This office&rsquo;s</Btn>
            <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt(`Give ${c.code} back to its department as a Core course? Say why:`, "A departmental course the structure marked G"); if (why && why.trim()) void call(`/courses/${slug(c.code)}/return`, "POST", { reason: why.trim() }, `${c.code} given back to its department: ${why.trim()}`, `${c.code} is its department's again`); }}>Give back to its department</Btn>
          </span> : <span key="a" />,
        ])} />
      ) : null}
    </Panel>
  );
}
