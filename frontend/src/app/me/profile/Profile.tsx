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
 *
 * V749: the photograph and the e-mail address are changed at My identity (/me/identity) — a new photograph is checked and
 * enhanced for the identity card and saved only once accepted, and a new address is verified by a code sent to it, the old one
 * kept until then — so neither is written from here. The address shown is the one the person's record holds (GET /staff/profile
 * answers it, and is read again after each save), and a save sends none: PUT /staff/profile saves the profile with the address on
 * record as it stands when it is saved (an e-mail in the body is not read), so a page opened before the address changed never holds
 * back the save or puts the old address back, and shows the record's address once saved. A profile that could not be read is not
 * saved: every field would go back blank.
 */
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { Btn, LinkBtn, Note, Panel, PBody } from "@/components/proto/ui";
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
    // the e-mail is not the form's: shown from the record (initial), never sent
    for (const [k] of SCALARS) if (k !== "email") o[k] = str(initial?.[k]);
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
    if (!initial) return;
    setBusy(true);
    setProblem(null);
    setSaved(false);
    try {
      // V749: no e-mail — the API saves the address on record with the profile, whatever this page was opened with
      const body: Raw = {
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
        setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      setSaved(true);
      notify("Profile updated");
      router.refresh();
    } finally {
      setBusy(false);
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
        It feeds the University&rsquo;s academic returns to the Faculty and the NUC.
      </Note>

      <div className="grid grid--2">
        <Panel title="Photograph" right="Your identity-card photograph">
          <PBody>
            <div className="row" style={{ gap: "var(--s-4)" }}>
              <Passport w={104} h={128} src={photo} alt={who} />
              <div className="stack">
                <LinkBtn kind="primary" href="/me/identity#photo">{photo ? "Replace photograph" : "Upload photograph"}</LinkBtn>
                <span className="sub2">
                  At My identity: the photograph is checked and enhanced for the identity card, shown beside the one you upload, and saved
                  only when you accept it.
                </span>
              </div>
            </div>
          </PBody>
        </Panel>

        <Panel title="Who you are" right={me?.staffNumber ? <span className="tnum">{me.staffNumber}</span> : "Signed in"}>
          <PBody>
            <div className="grid grid--2 rfgrid">
              {SCALARS.map(([k, label, hint]) => (
                <Field id={k} label={label} hint={hint} key={k}>
                  {/* V749: the address changes only once a code sent to the new one comes back (My identity). Shown from the
                      record as last read, not from the form: the save's router.refresh() reads it again, so after a save the
                      address on record shows, never the one this page was opened with */}
                  {k === "email"
                    ? <input id={k} className="ctl" value={str(initial?.email)} autoComplete="off" readOnly aria-describedby={`${k}-change`} />
                    : <input id={k} className="ctl" value={f[k]} autoComplete="off" onChange={(e) => set(k, e.target.value)} />}
                  {k === "email" ? <a id={`${k}-change`} className="lnk sub2" href="/me/identity#email">Change or verify at My identity</a> : null}
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

      <Panel title="" right={saved ? <span className="sub2 ink-green">Saved</span> : undefined}>
        <PBody>
          <div className="row" style={{ gap: "var(--s-3)" }}>
            <Btn kind="primary" disabled={busy || !initial} onClick={() => void save()}>{busy ? "Saving…" : "Save profile"}</Btn>
            <span className="sub2">
              {initial
                ? "Every field is optional. What you leave blank is saved as empty, not guessed."
                : "Your profile could not be read just now, so it cannot be saved from here: reload the page."}
            </span>
          </div>
          {saved ? <Note kind="ok" title="Your profile is saved">The record is updated against your account. You can come back and edit it any time.</Note> : null}
        </PBody>
      </Panel>
    </>
  );
}
