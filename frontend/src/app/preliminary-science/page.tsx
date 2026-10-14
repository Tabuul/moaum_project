import type { Metadata } from "next";
import { api } from "@/lib/api";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, PageHead } from "@/components/proto/ui";
import { TARGET_NOTE, longDay, naira, type PrelimPublic } from "@/lib/preliminary";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Preliminary Science Programme",
  description: "The University's Preliminary Science Programme: entry requirements, target programmes, application fee and how to apply.",
};

/**
 * /preliminary-science — public, no sign-in (V446): the Preliminary Science Programme as the University's configuration states
 * it — the description, the session, the opening date (the Director of ICT's window), the target programmes (existing
 * programmes of the register), the entry requirement and the remediation rule, the fee the Bursary stated, the procedure and
 * the documents; Apply while the window is open, the closure message otherwise. Nothing here is typed into the page: every
 * figure is read from the API.
 */
export default async function PreliminarySciencePage() {
  const r = await api<PrelimPublic>("/api/v1/public/preliminary-science", { anonymous: true });
  if (!r.ok) return <div style={{ padding: "var(--s-5)" }}><ProblemNotice problem={r.problem} /></div>;
  const p = r.data;
  const open = p.window.state === "OPEN";
  const groups = [...new Set(p.targets.map((t) => t.group))];
  const rules = p.rules;
  return (
    <AuthLayout wide eyebrow={`Preliminary / Remedial · ${p.session}`}
      lead={<>The Preliminary Science Programme prepares candidates for subsequent admission into approved science-based programmes. It is not an undergraduate degree.</>}
      stats={[[String(rules.minCredits), "O'Level credits to apply"], [String(rules.maxSittings), "sittings at most"], [String(p.targets.length), "target programmes"]]}>
      <div className="login-card" style={{ maxWidth: 860 }}>
        <PageHead title={`${p.name} Programme`} description={`${p.session} academic session`} />
        {open ? (
          <Note kind="ok" title={`Applications are open${p.window.closesAt ? ` until ${longDay(p.window.closesAt)}` : ""}`}
            action={<LinkBtn kind="primary" href="/preliminary-science/apply">Apply now</LinkBtn>}>
            Applications opened on {longDay(p.window.opensAt)}. Already started? <a className="lnk" href="/login">Sign in to continue your application</a>.
          </Note>
        ) : p.window.state === "SCHEDULED" ? (
          <Note kind="info" title={`Applications open on ${longDay(p.window.opensAt)}`}>The Apply button appears here when the application opens.</Note>
        ) : (
          <Note kind="bad" title="Application closed">{p.window.message ?? "Preliminary Science applications are not open at present."} <a className="lnk" href="/login">Sign in</a> to an application you already started.</Note>
        )}

        <h2 className="h3 mt-3">Programme overview</h2>
        <p>{p.description}</p>
        <dl className="kv grid grid--3">
          <div><dt>Programme</dt><dd>{p.name}</dd></div>
          <div><dt>Programme type</dt><dd>{p.programmeType ?? "Preliminary"} / Remedial</dd></div>
          <div><dt>Academic session</dt><dd>{p.session}</dd></div>
          <div><dt>Study mode</dt><dd>{p.studyMode === "FULL_TIME" ? "Full-time" : p.studyMode}</dd></div>
          <div><dt>Application opening</dt><dd>{longDay(p.window.opensAt)}</dd></div>
          <div><dt>Application fee</dt><dd>{p.fee.stated && p.fee.applicationFee != null ? naira(p.fee.applicationFee) : "To be announced by the Bursary"}</dd></div>
        </dl>

        <h2 className="h3 mt-3">Entry requirements</h2>
        <ul>
          <li>At least <b>{rules.minCredits} credit passes</b> ({rules.creditGrade} or better) in NECO, WAEC, GCE Ordinary Level or an approved equivalent.</li>
          <li>At most <b>{rules.maxSittings} sitting{rules.maxSittings === 1 ? "" : "s"}</b>.</li>
          <li>At least <b>{rules.minCoreCredits}</b> of the credits in the core science subjects: {rules.coreSubjects.join(", ")}.</li>
          <li><b>No awaiting result.</b> Admission is strictly on results already released; an awaiting result does not count.</li>
        </ul>

        <h2 className="h3 mt-3">Remediation requirement</h2>
        <p>{p.completionNote}</p>
        {rules.remediationTerms ? <p>{rules.remediationTerms}</p> : null}

        <h2 className="h3 mt-3">Target programmes</h2>
        <p className="sub2">{TARGET_NOTE}</p>
        <div className="grid grid--2">
          {groups.map((g) => (
            <div key={g}>
              <h3 className="h4">{g}</h3>
              <ul>{p.targets.filter((t) => t.group === g).map((t) => <li key={t.programmeCode}>{t.name}</li>)}</ul>
            </div>
          ))}
        </div>

        <h2 className="h3 mt-3">Method of application</h2>
        <ol>{p.procedure.map((s, i) => <li key={i}>{s}</li>)}</ol>

        <h2 className="h3 mt-3">Required documents</h2>
        <ul>
          {p.documents.filter((d) => d.required).map((d) => <li key={d.kind}>{d.label}{d.secondSittingOnly ? " (only with a second sitting)" : ""}</li>)}
          <li>The payment receipt: issued by the portal when your payment is verified.</li>
        </ul>
        {p.officeNote ? <p className="sub2">{p.officeNote}</p> : null}

        <div className="row row--inline mt-3">
          {open ? <LinkBtn kind="primary" href="/preliminary-science/apply">Apply now</LinkBtn> : null}
          <LinkBtn kind="ghost" href="/login">Sign in</LinkBtn>
        </div>
      </div>
    </AuthLayout>
  );
}
