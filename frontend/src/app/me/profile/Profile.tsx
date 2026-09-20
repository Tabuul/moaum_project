"use client";

/**
 * The staff profile a member of staff keeps about themselves — proto house
 * style. Contact and posting, the scholar's record (Google Scholar, research
 * interests, the postgraduates graduated), the lists that grow over a career
 * (publications, grants, collaborations, conferences, assignments, innovations,
 * patents, achievements, contributions to society), and a recent photograph.
 *
 * It is the person's own and no other: every write goes to /api/v1/staff/profile,
 * which takes the person from the signed-in token, never a parameter. The list
 * sections are edited one entry per line, and saved as arrays.
 */
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field, Passport } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

type Raw = Record<string, unknown>;

const SCALARS: [string, string, string?][] = [
  ["email", "Email", "The address the University writes to"],
  ["phone", "Phone contact", "How you are reached"],
  ["department", "Department"],
  ["faculty", "Faculty"],
  ["responsibility", "Current responsibility in the department"],
  ["orcid", "ORCID", "Your ORCID identifier, if you have one"],
];

const OUTPUT: [string, string, string][] = [
  ["publications", "Publications", "One publication per line — a full citation on each"],
  ["grants", "Grants obtained", "One per line — the award, the funder and the year"],
  ["patents", "Patents", "One per line — the title and the patent number"],
  ["innovations", "Innovations", "One per line"],
];

const ENGAGE: [string, string, string][] = [
  ["collaborations", "Research collaborations", "Local and international — one per line"],
  ["conferences", "Conferences attended", "One per line — the conference, the place and the year"],
  ["assignments", "National and international assignments", "One per line"],
  ["achievements", "Achievements", "One per line"],
  ["contributions", "Contributions to society", "One per line"],
];

function str(v: unknown): string {
  return typeof v === "string" ? v : v == null ? "" : String(v);
}
function lines(v: unknown): string {
  return Array.isArray(v) ? v.map((x) => str(x)).join("\n") : "";
}
function toList(s: string): string[] {
  return s.split("\n").map((x) => x.trim()).filter(Boolean);
}

export function Profile({ initial, me }: { initial: Raw | null; me: Me | null }) {
  const router = useRouter();
  const [f, setF] = useState<Record<string, string>>(() => {
    const o: Record<string, string> = {};
    for (const [k] of SCALARS) o[k] = str(initial?.[k]);
    o.scholarUrl = str(initial?.scholarUrl);
    o.researchInterests = str(initial?.researchInterests);
    o.mastersGraduated = str(initial?.mastersGraduated ?? "0");
    o.phdGraduated = str(initial?.phdGraduated ?? "0");
    for (const [k] of [...OUTPUT, ...ENGAGE]) o[k] = lines(initial?.[k]);
    return o;
  });
  const [problem, setProblem] = useState<Problem | null>(null);
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);
  const [photo, setPhoto] = useState<string | null>(null);
  const [photoMsg, setPhotoMsg] = useState<string | null>(null);
  const [photoBusy, setPhotoBusy] = useState(false);

  useEffect(() => {
    let live = true;
    async function load() {
      if (!initial?.photo) return;
      const r = await fetch("/api/bff/api/v1/staff/profile/photo");
      if (!r.ok) return;
      const j = (await r.json().catch(() => null)) as { contentType?: string; dataBase64?: string } | null;
      if (live && j?.dataBase64) setPhoto(`data:${j.contentType};base64,${j.dataBase64}`);
    }
    void load();
    return () => {
      live = false;
    };
  }, [initial?.photo]);

  const set = (k: string, v: string) => {
    setF((p) => ({ ...p, [k]: v }));
    setSaved(false);
  };

  async function save() {
    setBusy(true);
    setProblem(null);
    setSaved(false);
    try {
      const body: Raw = {
        email: f.email.trim() || null,
        phone: f.phone.trim() || null,
        department: f.department.trim() || null,
        faculty: f.faculty.trim() || null,
        responsibility: f.responsibility.trim() || null,
        orcid: f.orcid.trim() || null,
        scholarUrl: f.scholarUrl.trim() || null,
        researchInterests: f.researchInterests.trim() || null,
        mastersGraduated: Number(f.mastersGraduated) || 0,
        phdGraduated: Number(f.phdGraduated) || 0,
      };
      for (const [k] of [...OUTPUT, ...ENGAGE]) body[k] = toList(f[k]);
      const r = await fetch("/api/bff/api/v1/staff/profile", {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Staff profile updated by the holder") },
        body: JSON.stringify(body),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      setSaved(true);
      notify("Profile updated");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function onPhoto(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setPhotoMsg(null);
    setProblem(null);
    if (!["image/jpeg", "image/png"].includes(file.type)) {
      setPhotoMsg("A photograph is a JPEG or PNG image.");
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      setPhotoMsg("A photograph is up to 2 MB.");
      return;
    }
    setPhotoBusy(true);
    try {
      const dataUrl = await new Promise<string>((res, rej) => {
        const rd = new FileReader();
        rd.onload = () => res(String(rd.result));
        rd.onerror = () => rej(new Error("read"));
        rd.readAsDataURL(file);
      });
      const b64 = dataUrl.split(",")[1] ?? "";
      const r = await fetch("/api/bff/api/v1/staff/profile/photo", {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Staff photograph updated by the holder") },
        body: JSON.stringify({ contentType: file.type, dataBase64: b64 }),
      });
      if (!r.ok) {
        const j = await r.json().catch(() => null);
        setProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      setPhoto(dataUrl);
      setPhotoMsg("Photograph updated.");
    } catch {
      setPhotoMsg("The picture could not be read.");
    } finally {
      setPhotoBusy(false);
    }
  }

  const who = me?.name ?? "My profile";
  const listField = ([k, label, hint]: [string, string, string]) => (
    <Field id={k} label={label} hint={hint} full key={k}>
      <textarea id={k} className="ctl" rows={4} value={f[k]} onChange={(e) => set(k, e.target.value)} />
    </Field>
  );

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Note kind="info" title="This is your profile — yours to keep current">
        Everything below is your own record. It is saved against your staff account and no other, and it feeds the
        University&rsquo;s academic returns. Keep it accurate: the publications, grants and postgraduates you record here are
        what the Faculty and the NUC see against your name.
      </Note>

      <div className="grid grid--2">
        <Panel title="Photograph" right="A recent picture · JPEG or PNG, up to 2 MB">
          <PBody>
            <div style={{ display: "flex", gap: 16, alignItems: "center" }}>
              <Passport w={104} h={128} src={photo} alt={who} />
              <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                <label className={`btn btn--primary btn--sm${photoBusy ? " is-disabled" : ""}`} style={{ cursor: "pointer" }}>
                  {photoBusy ? "Uploading…" : photo ? "Replace photograph" : "Upload photograph"}
                  <input type="file" accept="image/jpeg,image/png" hidden disabled={photoBusy} onChange={(e) => void onPhoto(e)} />
                </label>
                {photoMsg ? <span className="sub2">{photoMsg}</span> : <span className="sub2">A head-and-shoulders photograph on a plain background.</span>}
              </div>
            </div>
          </PBody>
        </Panel>

        <Panel title="Who you are" right={me?.staffNumber ? <span className="tnum">{me.staffNumber}</span> : "Signed in"}>
          <PBody>
            <div className="grid grid--2 rfgrid">
              {SCALARS.map(([k, label, hint]) => (
                <Field id={k} label={label} hint={hint} key={k}>
                  <input id={k} className="ctl" value={f[k]} autoComplete="off" onChange={(e) => set(k, e.target.value)} />
                </Field>
              ))}
            </div>
          </PBody>
        </Panel>
      </div>

      <Panel title="Research" right="Your scholarly identity and standing">
        <PBody>
          <div className="grid grid--2 rfgrid">
            <Field id="scholarUrl" label="Google Scholar profile" hint="The link to your Scholar page" full>
              <input id="scholarUrl" className="ctl" value={f.scholarUrl} placeholder="https://scholar.google.com/citations?user=…" autoComplete="off" onChange={(e) => set("scholarUrl", e.target.value)} />
            </Field>
            <Field id="researchInterests" label="Areas of research interest" hint="A sentence or two on the fields you work in" full>
              <textarea id="researchInterests" className="ctl" rows={3} value={f.researchInterests} onChange={(e) => set("researchInterests", e.target.value)} />
            </Field>
            <Field id="mastersGraduated" label="Master's candidates graduated" hint="How many you have supervised to completion">
              <input id="mastersGraduated" className="ctl tnum" inputMode="numeric" value={f.mastersGraduated} onChange={(e) => set("mastersGraduated", e.target.value.replace(/[^0-9]/g, ""))} />
            </Field>
            <Field id="phdGraduated" label="PhD candidates graduated" hint="How many you have supervised to completion">
              <input id="phdGraduated" className="ctl tnum" inputMode="numeric" value={f.phdGraduated} onChange={(e) => set("phdGraduated", e.target.value.replace(/[^0-9]/g, ""))} />
            </Field>
          </div>
        </PBody>
      </Panel>

      <Panel title="Research output" right="Publications, grants, patents and innovations — one entry per line">
        <PBody>
          <div className="grid grid--2 rfgrid">{OUTPUT.map(listField)}</div>
        </PBody>
      </Panel>

      <Panel title="Engagement and recognition" right="Collaborations, conferences, assignments and contributions — one entry per line">
        <PBody>
          <div className="grid grid--2 rfgrid">{ENGAGE.map(listField)}</div>
        </PBody>
      </Panel>

      <Panel title="" right={saved ? <span className="sub2" style={{ color: "var(--green-ink)" }}>Saved</span> : undefined}>
        <PBody>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save profile"}</Btn>
            <span className="sub2">Every field is optional. What you leave blank is saved as empty, not guessed.</span>
          </div>
          {saved ? <Note kind="ok" title="Your profile is saved">The record is updated against your account. You can come back and edit it any time.</Note> : null}
        </PBody>
      </Panel>
    </>
  );
}
