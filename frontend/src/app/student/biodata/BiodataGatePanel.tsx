"use client";

/**
 * V423 — the student's view of the biodata gate, above the biodata form. Held by the gate, the student sees who they
 * are signed in as, how far the required biodata is complete, what is missing and, when the photograph is missing,
 * where to give it; the rest of the portal opens by itself once nothing is missing — nobody approves it. With the gate
 * OFF the same progress is shown, without the hold, so the record can be completed before it is required.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Passport } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import type { StudentGate } from "@/lib/biodata-gate";
import type { Me } from "@/lib/student-portal";

const MAX = 2 * 1024 * 1024;

export function BiodataGatePanel({ gate, student }: { gate: StudentGate; student: Me }) {
  const router = useRouter();
  const [file, setFile] = useState<{ url: string; name: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const c = gate.completion;
  const held = gate.gate === "REQUIRED";
  const needsPhoto = c.missing.some((m) => m.item === "PASSPORT");
  const number = student.matricNo ?? student.jambRegNo ?? student.admissionNo ?? "";

  if (c.required === 0) return null;

  function choose(f: File | undefined) {
    if (!f) return;
    if (!/^image\/(jpeg|png)$/.test(f.type)) { notifyProblem({ status: 422, title: "A passport photograph is a JPEG or a PNG." }); return; }
    if (f.size > MAX) { notifyProblem({ status: 422, title: "A passport photograph is up to 2 MB." }); return; }
    const reader = new FileReader();
    reader.onload = () => setFile({ url: String(reader.result), name: f.name });
    reader.readAsDataURL(f);
  }

  async function upload() {
    if (!file) return;
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/me/passport", {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Passport photograph given by the student") },
        body: JSON.stringify({ dataUrl: file.url }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify("Passport photograph saved");
      setFile(null);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const progress = (
    <div className="stack" style={{ gap: 6, minWidth: 0, flex: "1 1 260px" }}>
      <div className="row row--tight" style={{ justifyContent: "space-between" }}>
        <b>Biodata completion</b>
        <span className="tnum b600">{c.percent}%</span>
      </div>
      <div className="bgate__bar" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={c.percent} aria-label="Biodata completion">
        <span style={{ width: `${c.percent}%` }} />
      </div>
      <div className="sub2">Required items: <b className="tnum">{c.completed} / {c.required}</b> completed</div>
      {c.missing.length ? (
        <>
          <div className="sub2 mt-1">Missing information</div>
          <ul className="bgate__miss">{c.missing.map((m) => <li key={m.item}><Pil kind={held ? "bad" : "warn"}>{m.label}</Pil></li>)}</ul>
        </>
      ) : null}
    </div>
  );

  const photo = needsPhoto ? (
    <div className="stack" style={{ gap: 8, flex: "1 1 240px", minWidth: 0 }}>
      <b>Passport photograph</b>
      <div className="sub2">A recent photograph of your face on a plain background, as a JPEG or PNG of up to 2 MB. It appears on your identity card, course form and examination documents.</div>
      <div className="row row--tight" style={{ flexWrap: "wrap", gap: 10 }}>
        {file ? <Passport w={72} h={88} src={file.url} alt="The photograph chosen" /> : null}
        <label className="btn btn--ghost btn--sm" style={{ cursor: "pointer" }}>
          {file ? "Choose another" : "Choose a photograph"}
          <input type="file" accept="image/jpeg,image/png" style={{ display: "none" }} onChange={(e) => choose(e.target.files?.[0])} />
        </label>
        {file ? <Btn kind="primary" disabled={busy} onClick={() => void upload()}>{busy ? "Saving…" : "Save photograph"}</Btn> : null}
      </div>
    </div>
  ) : null;

  if (held) {
    return (
      <Panel title="Complete your biodata" right={<Pil kind="bad">Biodata completion required</Pil>}>
        <PBody>
          <div className="bgate__who">
            <Passport w={64} h={78} src="/api/bff/api/v1/me/passport" alt={`${student.name} — passport photograph`} />
            <div style={{ minWidth: 0 }}>
              <div className="b600">{student.name}</div>
              <div className="sub2 tnum">{number}</div>
              <div className="sub2">{student.programme}</div>
            </div>
          </div>
          <Note kind="info" title="Please complete your required biodata before continuing to the Student Portal.">
            The rest of the portal opens as soon as every required item below is saved. Nobody needs to approve it.
          </Note>
          <div className="bgate">{progress}{photo}</div>
          <div className="row mt-1">
            <Btn kind="primary" onClick={() => document.querySelector(".bio")?.scrollIntoView({ behavior: "smooth", block: "start" })}>Complete biodata</Btn>
          </div>
        </PBody>
      </Panel>
    );
  }

  if (gate.enabled && c.complete) {
    return (
      <Note kind="ok" title="Your required biodata is complete" action={<LinkBtn kind="primary" href="/student">Continue to the dashboard</LinkBtn>}>
        Keep it current: a change of phone number, address or next of kin is saved here.
      </Note>
    );
  }

  if (c.complete) return null;
  return (
    <Panel title="Biodata completion" right={gate.gate === "EXCEPTION" && gate.exception ? <span className="sub2">Access allowed until {new Date(gate.exception.expires_at).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })}</span> : null}>
      <PBody>
        <div className="bgate">{progress}{photo}</div>
      </PBody>
    </Panel>
  );
}
