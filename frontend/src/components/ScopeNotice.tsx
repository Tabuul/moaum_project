/** V325 — a desk bound to a department or a faculty says exactly why it is not tied to one: what the grant holds,
 *  what is wrong with it, and what the Registry does about it. When the desk did resolve, but through a fallback
 *  (the lecturer grant, the staff record) because the office's own grant did not answer, a quieter note says so,
 *  so the Registry hears of the grant before anything depends on it. Renders nothing when there is nothing to say. */
import { Note } from "@/components/proto/ui";
import { officeLabel } from "@/lib/offices";
import { scopeReasonWord, scopeRemedyWord, scopeSourceWord, type OfficeScopeState } from "@/lib/office-scope";

export function ScopeNotice({ scope, what = "dashboard" }: { scope: OfficeScopeState | null; what?: string }) {
  if (!scope || !scope.bounded) return null;
  const label = officeLabel(scope.office);
  const kind = scope.kind ?? "department";
  if (!scope.resolved) {
    const why = scopeReasonWord(scope, label);
    return (
      <Note kind="bad" title={`Your ${label} office is not tied to a ${kind} yet`}>
        The {what} is scoped to your {kind}, and the portal cannot tell which one this office holds.{" "}
        {why ? <b>{why}</b> : null} {scopeRemedyWord(scope)}
      </Note>
    );
  }
  const via = scopeSourceWord(scope);
  const why = scopeReasonWord(scope, label);
  if (via && why) {
    return (
      <Note kind="info" title={`Read as ${scope.name ?? scope.code} through ${via}`}>
        {why} Until the Registry amends it, the {what} reads the {kind} from {via} instead.
      </Note>
    );
  }
  return null;
}
