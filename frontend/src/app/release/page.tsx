import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Note, Panel, PBody } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

/** t/release — the release pipeline (framework; the portal does not surface its own live deploy state). */
export default async function ReleasePage() {
  const me = await api<Me>("/api/v1/iam/me");
  const step = (n: number, title: string, body: string) => (
    <div className="row row--top" style={{ gap: "var(--s-3)", padding: "var(--s-3) 0", borderTop: n > 1 ? "1px solid var(--line-2)" : undefined }}>
      <div className="b700" style={{ flex: "0 0 26px", height: 26, borderRadius: "var(--r-pill)", background: "var(--sky-bg)", color: "var(--ink)", display: "flex", alignItems: "center", justifyContent: "center" }}>{n}</div>
      <div><b>{title}</b><div className="sub2">{body}</div></div>
    </div>
  );
  return (
    <Shell route="t/release" me={me.ok ? me.data : null}>
      <Note kind="info" title="Nothing reaches production that has not passed the gate">
        Every change goes through the same pipeline, and a deployment happens only after the checks are green. This page describes that pipeline; the portal does not surface its own live build or deploy status, so no run is shown here that it cannot observe from inside itself.
      </Note>
      <Panel title="The pipeline" right="Build · test · approve · deploy · roll back">
        <PBody>
          {step(1, "Build", "The API, the portal, the prototype and the container images are built from the committed source — reproducibly, so the same commit yields the same artefact.")}
          {step(2, "Test", "The database migrations apply and the property suite holds; the API compiles and its module boundaries hold; the frontend type-checks, lints and builds; the containers migrate, serve and answer. A red check stops the change.")}
          {step(3, "Approve", "The change is on a branch and reviewed before it merges; the audit trail is in the commit history, not a side channel.")}
          {step(4, "Deploy", "A merge to the main branch, once green, is what the hosting picks up. Nothing is deployed by hand around the checks.")}
          {step(5, "Roll back", "A deployment is a forward change to a known-good artefact; recovery is redeploying the previous commit, and the database migrations are additive so a roll-back does not strand data.")}
        </PBody>
      </Panel>
      <Note kind="ok" title="The check is the contract">
        The same suite that must pass before a change merges is the suite that gates deployment. That is why a feature is not &lsquo;done&rsquo; here until it is green — the pipeline, not a person&rsquo;s assurance, is what admits it.
      </Note>
    </Shell>
  );
}
