"use client";

/** The record's classification (V469): programme type, admission route, study mode and centre, where each was read from, and the
 *  programme-type history — the decisions and the progressions from an earlier JUPEB or Preliminary record, all kept. The Academic
 *  Office and the Registry may correct the classification or record a progression, each with its reason. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { reasonHeader } from "@/lib/reason";
import { modeWord } from "@/lib/student-query";

export interface Classification {
  student_id: string; programme_type: string | null; programme_type_name: string | null; proposed_type: string | null; proposed_type_name: string | null;
  type_source: string | null; classification_status: string; classification_issue: string | null; classification_note: string | null;
  admission_route: string | null; admission_route_name: string | null; study_mode: string | null; centre_code: string | null; centre_name: string | null;
  centre_source: string | null; study_mode_differs: boolean;
  history: { id: string; event: string; kind: string; from_type_name: string | null; to_type_name: string | null; reason: string; at: string; by_office: string | null; earlier_application_no: string | null }[];
}

const SOURCE_WORD: Record<string, string> = { DECISION: "an office's decision", ENTRY_MODE: "the entry mode", PROGRAMME_CATEGORY: "the programme's category" };
const day = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });

export function ClassificationPanel({ data, decides }: { data: Classification; decides: boolean }) {
  const router = useRouter();
  const [mode, setMode] = useState<"" | "decide" | "progress">("");
  const [lists, setLists] = useState<{ types: { code: string; name: string }[]; routes: { code: string; name: string }[]; centres: { code: string; name: string }[] } | null>(null);
  const [type, setType] = useState("");
  const [route, setRoute] = useState("");
  const [centre, setCentre] = useState("");
  const [source, setSource] = useState("PRELIMINARY");
  const [appNo, setAppNo] = useState("");
  const [reason, setReason] = useState("");
  const [err, setErr] = useState<string | null>(null);

  async function open(m: "decide" | "progress") {
    setErr(null); setReason(""); setAppNo(""); setType(data.programme_type ?? data.proposed_type ?? ""); setRoute(""); setCentre("");
    if (m === "decide" && !lists) {
      const r = await fetch("/api/bff/api/v1/student/classification/review?size=1", { cache: "no-store" });
      if (r.ok) setLists(await r.json());
    }
    setMode(m);
  }
  async function send() {
    if (!reason.trim()) { setErr("Say why — it is kept with the record."); return; }
    const decide = mode === "decide";
    if (decide && !type) { setErr("Choose the programme type."); return; }
    if (!decide && !appNo.trim()) { setErr("Give the earlier record's application number."); return; }
    const r = await fetch(`/api/bff/api/v1/student/classification/${data.student_id}${decide ? "" : "/progression"}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason.trim()) },
      body: JSON.stringify(decide ? { programmeType: type, admissionRoute: route || null, centre: centre || null, reason: reason.trim() }
        : { source, applicationNo: appNo.trim(), reason: reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); setErr((j as { detail?: string; title?: string } | null)?.detail ?? (j as { title?: string } | null)?.title ?? "Not recorded."); return; }
    notify(decide ? "Classification recorded" : "Progression recorded");
    setMode("");
    router.refresh();
  }

  const typeWord = data.programme_type_name ?? "Requires classification";
  return (
    <Panel title="Classification" right={data.programme_type_name ? <Pil kind="info">{data.programme_type_name.toUpperCase()} STUDENT</Pil> : <Pil kind="warn">REQUIRES CLASSIFICATION</Pil>}>
      <PBody>
        {data.classification_status !== "CLASSIFIED" ? (
          <Note kind="bad" title="This record's classification is to be decided">
            {data.classification_note}{data.proposed_type_name ? ` The fields propose ${data.proposed_type_name}; the record is counted in no type until the Academic Office or the Registry decides.` : ""}
          </Note>
        ) : null}
        <KvGrid pairs={[
          ["Programme type", <span key="t"><b>{typeWord}</b>{data.type_source ? <div className="sub2">From {SOURCE_WORD[data.type_source] ?? data.type_source}</div> : null}</span>],
          ["Admission route", data.admission_route_name ?? "—"],
          ["Study mode", <span key="m">{modeWord(data.study_mode)}{data.study_mode_differs ? <div className="sub2 ink-amber">Not the type&rsquo;s usual mode</div> : null}</span>],
          ["Centre", <span key="c">{data.centre_name ?? "—"}{data.centre_source ? <div className="sub2">{data.centre_source === "RECORDED" ? "Recorded for the student" : "The programme type's centre"}</div> : null}</span>],
        ]} />
        {decides ? (
          <div className="row mt-3">
            <Btn kind="ghost" onClick={() => open("decide")}>Correct classification</Btn>
            <Btn kind="ghost" onClick={() => open("progress")}>Record progression from JUPEB or Preliminary</Btn>
          </div>
        ) : null}
      </PBody>
      {data.history.length ? (
        <DTable pageSize={0} cols={["Date|mid", "Change", "From", "To", "Reason", "Office"]}
          rows={data.history.map((h) => [
            <span key="d" className="tnum">{day(h.at)}</span>,
            <span key="k">{h.event === "PROGRESSION" ? `Progression — ${h.kind.replace(/_/g, " ").toLowerCase()}` : "Correction"}{h.earlier_application_no ? <div className="sub2 tnum">{h.earlier_application_no}</div> : null}</span>,
            h.from_type_name ?? "—", h.to_type_name ?? "—", <span key="r" className="sub2">{h.reason}</span>, h.by_office ?? "—",
          ])} />
      ) : null}

      {mode ? (
        <Modal title={mode === "decide" ? "Correct the classification" : "Record a progression"} onClose={() => setMode("")}
          foot={<><Btn kind="ghost" onClick={() => setMode("")}>Cancel</Btn><Btn kind="primary" onClick={() => send()}>Record</Btn></>}>
          {mode === "decide" ? (
            <>
              <Field id="cp-type" label="Programme type" required>
                <select id="cp-type" className="ctl" value={type} onChange={(e) => setType(e.target.value)}>
                  <option value="">Choose…</option>{(lists?.types ?? []).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="cp-route" label="Admission route">
                <select id="cp-route" className="ctl" value={route} onChange={(e) => setRoute(e.target.value)}>
                  <option value="">As the entry mode reads</option>{(lists?.routes ?? []).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="cp-centre" label="Centre">
                <select id="cp-centre" className="ctl" value={centre} onChange={(e) => setCentre(e.target.value)}>
                  <option value="">Keep as it is</option>{(lists?.centres ?? []).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
            </>
          ) : (
            <>
              <Note kind="info" title="The earlier record stays">The JUPEB or Preliminary record is kept as it was and reads &ldquo;progressed&rdquo;; the progression is on this student&rsquo;s history.</Note>
              <Field id="cp-src" label="Earlier programme">
                <select id="cp-src" className="ctl" value={source} onChange={(e) => setSource(e.target.value)}>
                  <option value="PRELIMINARY">Preliminary</option><option value="JUPEB">JUPEB</option>
                </select>
              </Field>
              <Field id="cp-app" label="Earlier application number" required>
                <input id="cp-app" className="ctl tnum" value={appNo} onChange={(e) => setAppNo(e.target.value)} maxLength={40} placeholder="e.g. APP/26/000123" />
              </Field>
            </>
          )}
          <Field id="cp-reason" label="Reason" required error={err ?? undefined}>
            <textarea id="cp-reason" className="ctl" rows={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
