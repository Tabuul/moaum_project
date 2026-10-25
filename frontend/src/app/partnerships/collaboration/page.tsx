import Link from "next/link";
import { api } from "@/lib/api";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CollaborationForm, type Options } from "./CollaborationForm";
import "../partnerships.css";
import { LinkRequest } from "./LinkRequest";

export const dynamic = "force-dynamic";
export const metadata = { title: "Initiate a collaboration or partnership" };

/** /partnerships/collaboration — the public collaboration enquiry (V658): no session; what the form is for, then the form */
export default async function CollaborationPage() {
  const o = await api<Options>("/api/v1/public/partnerships/options");
  if (!o.ok) {
    return <AuthLayout eyebrow="Partnerships" wide><div className="card"><div className="card__body"><ProblemNotice problem={o.problem} /></div></div></AuthLayout>;
  }
  const s = o.data.settings;
  const groups = o.data.groups.map((g) => ({ ...g, items: o.data.categories.filter((c) => c.grp === g.code) })).filter((g) => g.items.length);
  return (
    <AuthLayout eyebrow="Partnerships" wide legal>
      <div className="card"><div className="card__body ptn-public">
        <h1 className="ptn-h1">Initiate a collaboration or partnership</h1>
        <p>The University welcomes collaboration and partnership proposals from local and international organisations.</p>

        <h2 className="ptn-h2">Who may propose</h2>
        <p>Universities and other higher education institutions, research institutions, companies, government agencies, NGOs, foundations and donors,
          international organisations, industry, community organisations and other organisations.</p>

        <h2 className="ptn-h2">What can be proposed</h2>
        <ul className="ptn-cats">
          {groups.map((g) => <li key={g.code}><strong>{g.label}</strong>: {g.items.map((c) => c.label).join(", ")}</li>)}
        </ul>

        <h2 className="ptn-h2">What happens next</h2>
        <ol className="ptn-next">
          <li>Submission</li><li>Automatic acknowledgement by email</li><li>Initial screening</li><li>Routing to the office or academic unit concerned</li>
          <li>Review</li><li>A request for more information, where needed</li><li>Due diligence, where applicable</li><li>A decision, and development where approved</li>
        </ol>
        <p>We aim to acknowledge complete enquiries within {s.acknowledge_days} working days. Review takes longer, depending on the proposal.</p>
        <Note kind="info" title="Submission of this form does not constitute acceptance of a partnership proposal or create a binding commitment with the University." />

        <h2 className="ptn-h2">This form is not for</h2>
        <ul className="ptn-not">
          <li>Admissions enquiries: <Link href="/apply">apply for admission</Link></li>
          <li>ICT support or signing in: <Link href="/login">help from the sign-in page</Link>, or <Link href="/track">track an ICT support ticket</Link></li>
          <li>Student support, payment enquiries, job applications, media enquiries, complaints and general customer service: contact the University&rsquo;s offices concerned{s.contact_email ? <> or write to <a href={`mailto:${s.contact_email}`}>{s.contact_email}</a></> : null}.</li>
        </ul>
        <p className="sub2">How your information is used: <Link href="/privacy-policy">the University&rsquo;s privacy policy</Link>.</p>

        {s.public_open ? <CollaborationForm options={o.data} /> : (
          <Note kind="info" title="The collaboration enquiry form is closed for now.">{s.contact_email ? <>Write to <a href={`mailto:${s.contact_email}`}>{s.contact_email}</a>.</> : null}</Note>
        )}

        <h2 className="ptn-h2">Already submitted?</h2>
        <p>Follow your enquiry from the private link in its acknowledgement email. Lost it? Ask for a new one.</p>
        <LinkRequest />
      </div></div>
    </AuthLayout>
  );
}
