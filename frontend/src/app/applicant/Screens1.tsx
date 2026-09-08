"use client";

/**
 * The applicant's first three screens — proto/part13.html applicantDash,
 * applicantApply and applicantFee, as drawn — rendered from what the
 * database says the application is. Nothing invented: every date, number
 * and name is the record's, and where the record has none, the screen says so.
 */
import { useRef, useState } from "react";
import Link from "next/link";
import { at, confirmedReference, dob, openReference, BODY, DOCUMENT_KINDS, NEXT, STAGES, type Application } from "@/lib/applicant";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Gate, Gates, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Rail, TwoCol, useAct, when } from "./common";

/* ── 1. overview ── */

export function Dashboard({ a }: { a: Application }) {
  const nx = NEXT[Math.min(a.stage, 9)];
  const open = openReference(a, "APPLICATION");
  return (
    <>
      <Tiles items={[
        ["Application number", a.applicationNo.split("/").slice(-1)[0], null, a.applicationNo],
        ["Programme applied for", a.programme ?? "—", null, `${a.faculty ? `Faculty of ${a.faculty} · ` : ""}as JAMB recorded it`],
        [a.entryMode === "UTME" ? "UTME score" : "Entry", a.entryMode === "UTME" ? String(a.biodata.utme ?? "—") : "Direct Entry", null, `JAMB ${a.jambKey}`],
        ["Stage", `${a.stage + 1} of 10`, a.stage >= 9 ? "var(--green-ink)" : "var(--chrome)", STAGES[Math.min(a.stage, 9)][0]],
      ]} />
      <Note kind={a.stage >= 8 ? "ok" : a.stage === 5 ? "bad" : "info"} title={nx[0]}
        action={<Link href={nx[2]} className={`btn btn--${a.stage === 5 ? "urgent" : "primary"} btn--sm`}>{nx[3]}</Link>}>
        {nx[1]}
      </Note>
      <TwoCol>
        <Rail a={a} />
        <Panel title="Dates that matter" right={a.session}>
          <DTable cols={["When|mid", "What"]} rows={[
            [<span className="tnum sub2" key="d">{open ? when(open.expiresAt) : "—"}</span>, <Two key="w" a="Your payment reference expires" b={open ? "A new one is generated free of charge" : "No reference is open"} />],
            [<span className="tnum sub2" key="d">{a.screeningSlip ? when(a.screeningSlip.heldOn) : "—"}</span>, <Two key="w" a="Post-UTME screening" b={a.screeningSlip ? `Batch ${a.screeningSlip.batch} · ${a.screeningSlip.venue}` : "Published when the batches are made"} />],
            [<span className="tnum sub2" key="d">{a.decisionReleasedAt ? when(a.decisionReleasedAt) : "—"}</span>, <Two key="w" a="Admission decision" b={a.decisionReleasedAt ? "Released" : "When the Board has met"} />],
            [<span className="tnum sub2" key="d">{a.acceptedAt ? when(a.acceptedAt) : "—"}</span>, <Two key="w" a="Offer accepted" b={a.acceptedAt ? "Your place is held" : "After the offer"} />],
            [<span className="tnum sub2" key="d">{a.clearedAt ? when(a.clearedAt) : "—"}</span>, <Two key="w" a="Cleared at the Registry" b={a.clearedAt ? "Every document seen" : "Originals presented in person"} />],
          ]} />
        </Panel>
      </TwoCol>
    </>
  );
}

/* ── 2. the application form ── */

const DOC_LABEL = Object.fromEntries(DOCUMENT_KINDS.map(([k, l]) => [k, l]));

export function Apply({ a }: { a: Application }) {
  const { act, busy, problem } = useAct();
  const [nok, setNok] = useState(a.biodata.nextOfKin ?? "");
  const [declared, setDeclared] = useState(false);
  const [picking, setPicking] = useState<string | null>(null);
  const file = useRef<HTMLInputElement | null>(null);

  if (at(a, 2)) {
    const sittings = a.olevel;
    return (
      <>
        <Note kind="ok" title={`Your application was submitted on ${when(a.submittedAt)}`}>
          It can no longer be edited. If something on it is wrong, write to the Registry quoting your application number &mdash; do not create a second account, which will invalidate both.
        </Note>
        <Panel title="What you submitted" right={a.applicationNo}>
          <DTable cols={["Section", "Detail"]} rows={[
            [<Two key="s" a="Biodata" b="From your JAMB record" />, `${a.name} · ${a.biodata.sex === "F" ? "Female" : a.biodata.sex === "M" ? "Male" : "—"} · ${a.biodata.lga ?? "—"} LGA, ${a.biodata.stateOfOrigin ?? "—"} State`],
            [<Two key="s" a="O’Level" b={sittings.length === 1 ? "One sitting" : `${sittings.length} sittings`} />, sittings.length ? sittings.map((s) => `${BODY[s.body] ?? s.body} ${s.year ?? ""} · ${s.subjects.map((g) => `${g.subject} ${g.grade}`).join(", ")}`).join(" | ") : "No result has reached the University from JAMB yet"],
            [<Two key="s" a="Programme" b="As JAMB recorded it" />, `${a.programme ?? "—"}${a.faculty ? ` · Faculty of ${a.faculty}` : ""}`],
            [<Two key="s" a="Documents" b={`${a.documents.filter((d) => d.status === "ACCEPTED").length} of ${a.documents.length} accepted`} />, a.documents.map((d) => DOC_LABEL[d.kind] ?? d.kind).join(", ")],
            [<Two key="s" a="Next of kin" b="Given by you" />, a.biodata.nextOfKin ?? "—"],
            [<Two key="s" a="Declaration" b="Signed electronically" />, `Accepted ${when(a.submittedAt)}`],
          ]} />
        </Panel>
        {(() => {
          const p = a.documents.find((d) => d.kind === "PASSPORT");
          return (
            <Panel title="Your passport photograph" right="Can be uploaded or replaced at any time">
              <input ref={file} type="file" accept="image/jpeg,image/png,application/pdf" style={{ display: "none" }}
                onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload("PASSPORT", f); e.target.value = ""; }} />
              <PBody>
                <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
                  {p ? <span className="sub2 tnum">{p.filename} · {Math.round(p.bytes / 1024)} KB</span> : <span className="sub2">Not uploaded yet. It goes on your screening slip and, later, your identity card.</span>}
                  {p ? p.status === "ACCEPTED" ? <Pil kind="ok">Accepted</Pil> : p.status === "REJECTED" ? <Pil kind="bad">Rejected &mdash; reupload</Pil> : <Pil kind="info">Uploaded</Pil> : null}
                  <Btn kind={p && p.status !== "REJECTED" ? "ghost" : "primary"} disabled={busy !== null} onClick={() => file.current?.click()}>{busy === "doc-PASSPORT" ? "Uploading…" : p ? "Replace" : "Upload"}</Btn>
                </div>
                {p?.status === "REJECTED" && p.reviewNote ? <div className="sub2" style={{ marginTop: 6, color: "var(--red-ink)" }}>{p.reviewNote}</div> : null}
                {problem ? <ProblemNotice problem={problem} /> : null}
              </PBody>
            </Panel>
          );
        })()}
      </>
    );
  }

  if (!at(a, 1)) {
    return (
      <>
        <Note kind="bad" title="The form opens when your application fee is confirmed" action={<Link href="/applicant/fee" className="btn btn--primary btn--sm">Pay the application fee</Link>}>
          This is not a delay you can avoid by paying at a bank counter into a personal account. The portal releases the form the moment the Bursary confirms your payment against the reference it generated for you.
        </Note>
        <Rail a={a} />
      </>
    );
  }

  /* the passport photograph comes whenever the applicant has one (V022): shown, never a gate */
  const missing = DOCUMENT_KINDS.filter(([k]) => k !== "PASSPORT" && !a.documents.some((d) => d.kind === k));
  const rejected = a.documents.filter((d) => d.status === "REJECTED" && d.kind !== "PASSPORT");
  const gates: [string, string][] = [];
  if (!nok.trim()) gates.push(["Next of kin is missing", "Name and phone number, under Biodata."]);
  for (const [, label] of missing) gates.push([`${label} not uploaded`, "PDF or JPEG, 2 MB at most."]);
  for (const d of rejected) gates.push([`${DOC_LABEL[d.kind]} rejected`, d.reviewNote ?? "Upload a replacement that meets the stated requirements."]);
  const ready = gates.length === 0 && declared;

  async function upload(kind: string, f: File) {
    if (f.size > 2 * 1024 * 1024) return;
    const buf = await f.arrayBuffer();
    let bin = "";
    const bytes = new Uint8Array(buf);
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    await act(`doc-${kind}`, "POST", "/me/documents", { kind, filename: f.name, contentType: f.type || "application/pdf", contentBase64: btoa(bin) }, `${DOC_LABEL[kind]} uploaded by the applicant`);
  }

  return (
    <>
      <div className="card">
        <PBody>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            <Pil kind="ok">1 Biodata</Pil>
            <Pil kind={a.olevel.length ? "ok" : "info"}>2 O&rsquo;Level</Pil>
            <Pil kind={missing.length || rejected.length ? "info" : "ok"}>3 Documents</Pil>
            <span className="pill" style={{ background: "var(--bg)", border: "1px solid var(--line)", color: "var(--muted)" }}>4 Review</span>
          </div>
          <div style={{ marginTop: 6 }}>
            <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: "-.3px" }}>{a.programme ?? "Programme as JAMB recorded it"}</div>
            <div className="sub2">{a.faculty ? `Faculty of ${a.faculty} · ` : ""}{a.session} session. Your programme choice comes from JAMB and cannot be changed here.</div>
          </div>
        </PBody>
      </div>

      <Panel title={<>1 &nbsp;Biodata</>} right="Read from your JAMB record">
        <PBody>
          <KvGrid cls="grid--3" pairs={[
            ["Surname and other names", a.name],
            ["Date of birth", dob(a.biodata.dateOfBirth)],
            ["Sex", a.biodata.sex === "F" ? "Female" : a.biodata.sex === "M" ? "Male" : "—"],
            ["State and LGA of origin", `${a.biodata.stateOfOrigin ?? "—"} · ${a.biodata.lga ?? "—"}`],
            ["JAMB registration number", <span className="tnum" key="j">{a.jambKey}</span>],
            [a.entryMode === "UTME" ? "UTME score" : "Entry mode", <span className="tnum" key="u">{a.entryMode === "UTME" ? a.biodata.utme ?? "—" : "Direct Entry"}</span>],
          ]} />
          <div className="field" style={{ marginTop: 4 }}>
            <label htmlFor="nok">Next of kin &mdash; name and phone</label>
            <input id="nok" value={nok} onChange={(e) => setNok(e.target.value)} autoComplete="off" placeholder="SURNAME, Other names · 0806 552 1180"
              onBlur={() => { if (nok.trim() && nok.trim() !== (a.biodata.nextOfKin ?? "")) void act("nok", "PUT", "/me/next-of-kin", { nextOfKin: nok.trim() }, "Next of kin given by the applicant"); }} />
            <div className="hint">{busy === "nok" ? "Saving…" : "Saved when you leave the box. The person the University may call."}</div>
          </div>
        </PBody>
      </Panel>

      <Panel title={<>2 &nbsp;O&rsquo;Level results</>} right="As JAMB sent them · up to two sittings">
        <PBody>
          <div className="sub2">These are the results JAMB uploaded for you, shown exactly as they arrived. They are not edited here. The Registry verifies every result directly with WAEC, NECO or NABTEB before clearance; a result that does not verify voids the admission at any point, including after matriculation.</div>
          {a.olevel.length ? a.olevel.map((s, i) => (
            <div key={i}>
              <div style={{ display: "flex", alignItems: "center", gap: 8, margin: "8px 0 6px" }}>
                <Pil kind="grey">{BODY[s.body] ?? s.body}</Pil>
                <b>Sitting {i + 1}{s.type ? ` — ${s.type}` : ""}{s.year ? ` ${s.year}` : ""}</b>
                {s.examNumber ? <span className="sub2 tnum">exam no. {s.examNumber}</span> : null}
              </div>
              <DTable cols={["Subject", "Grade|mid"]} rows={s.subjects.map((g) => [<span key="s">{g.subject}</span>, <b className="tnum" key="g">{g.grade}</b>])} />
            </div>
          )) : (
            <Note kind="info" title="No O’Level result has reached the University from JAMB yet">
              JAMB sends the results in its own download; when the Academic Office records it, your sittings appear here. Nothing is typed by you.
            </Note>
          )}
        </PBody>
      </Panel>

      <Panel title={<>3 &nbsp;Documents</>} right="5 files · 2 MB each, PDF or JPEG">
        <input ref={file} type="file" accept="application/pdf,image/jpeg,image/png" style={{ display: "none" }}
          onChange={(e) => { const f = e.target.files?.[0]; if (f && picking) void upload(picking, f); e.target.value = ""; }} />
        <DTable cols={["Document", "File", "Status|num"]} rows={DOCUMENT_KINDS.map(([k, label, sub]) => {
          const d = a.documents.find((x) => x.kind === k);
          return [
            <Two key="d" a={label} b={sub} />,
            <span className="sub2 tnum" key="f">{d ? `${d.filename} · ${Math.round(d.bytes / 1024)} KB` : "—"}</span>,
            <span key="s" style={{ display: "inline-flex", gap: 6, alignItems: "center" }}>
              {d ? d.status === "ACCEPTED" ? <Pil kind="ok">Accepted</Pil> : d.status === "REJECTED" ? <Pil kind="bad">Rejected &mdash; reupload</Pil> : <Pil kind="info">Uploaded</Pil> : <Pil kind="grey">Not uploaded</Pil>}
              <Btn kind={d ? "ghost" : "primary"} disabled={busy !== null} onClick={() => { setPicking(k); file.current?.click(); }}>{busy === `doc-${k}` ? "Uploading…" : d ? "Replace" : "Upload"}</Btn>
            </span>,
          ];
        })} />
      </Panel>
      {rejected.map((d) => (
        <Note kind="bad" key={d.id} title={`Your ${DOC_LABEL[d.kind].toLowerCase()} was rejected`}>
          {d.reviewNote ?? "It did not meet the stated requirements."} This document becomes part of your record, so it is checked before it is accepted.
        </Note>
      ))}

      <Panel title={<>4 &nbsp;Review and submit</>}>
        <PBody>
          {gates.length ? (
            <>
              <Note kind="bad" title={`${gates.length} thing${gates.length === 1 ? "" : "s"} must be settled before you can submit`}>
                Nothing is lost &mdash; everything you have entered is saved. Fix {gates.length === 1 ? "this" : "these"} and the submit button opens.
              </Note>
              <Gates>{gates.map((g, i) => <Gate key={g[0]} state="todo" title={g[0]} sub={g[1]} last={i === gates.length - 1} />)}</Gates>
            </>
          ) : (
            <Note kind="ok" title="Everything is in">Read the declaration, tick it, and submit. Submitted once, the application is not edited.</Note>
          )}
          {problem ? <ProblemNotice problem={problem} /> : null}
          <label style={{ display: "flex", gap: 9, alignItems: "flex-start", fontSize: 13.5, color: "var(--muted)", marginTop: 4 }}>
            <input type="checkbox" className="chk" checked={declared} onChange={(e) => setDeclared(e.target.checked)} />
            <span>I declare that the particulars I have given are true. I understand that a false declaration voids my admission at any point, including after graduation.</span>
          </label>
          <div style={{ display: "flex", gap: 9, flexWrap: "wrap", marginTop: 4 }}>
            <Link href="/applicant" className="btn btn--ghost">Save and come back later</Link>
            <Btn kind="primary" disabled={!ready || busy !== null} onClick={() => void act("submit", "POST", "/me/submit", { declaration: true }, "Application submitted by the applicant")}>{busy === "submit" ? "Submitting…" : "Submit application"}</Btn>
          </div>
        </PBody>
      </Panel>
    </>
  );
}

/* ── 3. application fee ── */

export function Fee({ a }: { a: Application }) {
  const { act, busy, problem } = useAct();
  const total = Number(a.fees.applicationFee) + Number(a.fees.portalCharge);
  const paid = confirmedReference(a, "APPLICATION");
  const open = openReference(a, "APPLICATION");

  if (at(a, 1) && paid) {
    return (
      <>
        <Note kind="ok" title={`Payment confirmed — ${money(Number(paid.amount))} received`} action={<Link href="/applicant/apply" className="btn btn--primary btn--sm">Open the application form</Link>}>
          The Bursary confirmed this payment against the bank&rsquo;s record. Your application form is now open.
        </Note>
        <Panel title="Receipt" right={paid.reference}>
          <DTable cols={["Field", "Value"]} rows={[
            ["Reference", <span className="tnum" key="r">{paid.reference}</span>],
            ["Confirmed", <span className="tnum" key="p">{when(paid.confirmedAt)}</span>],
            ["Channel", paid.channel ?? "—"],
            ["Amount", <strong className="tnum" key="a">{money(Number(paid.amount))}</strong>],
            ["Confirmed by", "The Bursary, against the bank’s record, not by this page"],
            ["Status", <Pil kind="ok" key="s">Settled</Pil>],
          ]} />
        </Panel>
      </>
    );
  }

  return (
    <>
      <Panel title="Application and screening fee" right={a.applicationNo}>
        <DTable cols={["Item", "Amount|num"]} rows={[
          [<Two key="i" a="Post-UTME screening fee" b={a.fees.stated ? `As stated for the ${a.session} session` : `The standing amount for ${a.session}`} />, <span className="tnum" key="a">{money(Number(a.fees.applicationFee))}</span>],
          [<Two key="i" a="Portal and payment charge" b="Charged by the payment provider, not the University" />, <span className="tnum" key="a">{money(Number(a.fees.portalCharge))}</span>],
          [<strong key="i">Total payable</strong>, <strong className="tnum" style={{ fontSize: 16 }} key="a">{money(total)}</strong>],
        ]} />
      </Panel>
      <Panel title="Your payment reference" right="Generated for you alone">
        <PBody>
          {open ? (
            <div style={{ display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
              <div style={{ minWidth: 200 }}>
                <div className="eyebrow">Reference</div>
                <div className="tnum" style={{ fontSize: 22, fontWeight: 700, letterSpacing: ".5px" }}>{open.reference}</div>
                <div className="sub2" style={{ marginTop: 6 }}>Quote this reference and nothing else. It is tied to your application number and expires {when(open.expiresAt)}; a new one is generated free of charge.</div>
              </div>
            </div>
          ) : (
            <div className="sub2">No reference is open. Generate one below; it is yours alone, and the Bursary confirms the payment against it.</div>
          )}
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div style={{ display: "flex", gap: 9, flexWrap: "wrap", marginTop: 8 }}>
            <Btn kind="primary" disabled={busy !== null} onClick={() => void act("ref", "POST", "/me/fee-references", { kind: "APPLICATION" }, "Application fee reference generated for the applicant")}>{busy === "ref" ? "Generating…" : open ? "Generate a new reference" : `Generate a reference for ${money(total)}`}</Btn>
          </div>
        </PBody>
      </Panel>
      <Panel title="How you can pay" right="Any of these">
        <DTable cols={["Channel", "What to do", "Confirmed in|num"]} rows={[
          [<Two key="c" a="Bank transfer" b="From any Nigerian bank" />, "Transfer to the University’s account, quoting the reference", <span className="sub2" key="t">When the Bursary sees it</span>],
          [<Two key="c" a="Bank branch" b="Over the counter" />, "Present the reference at any approved bank", <span className="sub2" key="t">Same day</span>],
          [<Two key="c" a="Card and USSD" b="On the portal" />, "Arrive with the payment gateway", <span className="sub2" key="t">Not yet on the portal</span>],
        ]} />
      </Panel>
      <Note kind="info" title="A payment is confirmed by the Bursary against the bank’s record, never by this page">
        If your network drops after you pay, do not pay again. Every payment carries the reference this portal generated, and the Bursary confirms it against that reference, so a successful payment always reaches your account.
      </Note>
      <Note kind="bad" title="Pay only against a reference this portal generated">
        Money sent to a personal account, an agent or a &ldquo;consultant&rdquo; does not reach the University and cannot be recovered by it. There is no fee that is paid anywhere but here.
      </Note>
    </>
  );
}
