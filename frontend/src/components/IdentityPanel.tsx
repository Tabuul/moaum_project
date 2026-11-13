/**
 * V749: the staff identity panel — at the top of a member of staff's dashboard while the identity information the card needs is not
 * complete: the passport photograph enhanced and accepted, the e-mail address verified, the blood group confirmed. It cannot be
 * dismissed; it goes when the last of them is done, and opens the update page.
 */
import Link from "next/link";
import type { Missing } from "@/lib/identity";
import { Ico } from "@/components/proto/ui";

export function IdentityPanel({ missing }: { missing: Missing[] }) {
  if (!missing.length) return null;
  return (
    <div className="notice notice--warn" role="region" aria-label="Update your staff identity information"
      style={{ background: "var(--amber-bg)", border: "1px solid var(--amber-line)", borderLeft: "4px solid var(--amber)" }}>
      <Ico name="user" size={18} stroke="var(--amber-ink)" w={2} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="notice__t">Your staff identity information is not complete</div>
        <div className="notice__p">
          The University needs it for your staff identity card and to reach you. Still to do:
          <ul style={{ margin: "6px 0 0", paddingLeft: "1.2em", listStyle: "disc" }}>
            {missing.map((m) => <li key={m.key}><b>{m.title}</b> <span className="sub2">— {m.detail}</span></li>)}
          </ul>
        </div>
        <div className="notice__a">
          <Link className="btn btn--primary btn--sm" href="/me/identity">UPDATE STAFF IDENTITY INFORMATION</Link>
        </div>
      </div>
    </div>
  );
}
