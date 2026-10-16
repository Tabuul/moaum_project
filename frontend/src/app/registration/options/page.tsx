import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RegistrationOptions, type FlexState } from "./RegistrationOptions";

export const dynamic = "force-dynamic";

/** t/regoptions — Course registration options (V504): whether students add courses beside their recommended list, how wide, and
 *  whether a course of a higher level than theirs may be added; the engine judges every course a student adds whatever is set */
export default async function RegistrationOptionsPage() {
  const [me, flex] = await Promise.all([api<Me>("/api/v1/iam/me"), api<FlexState>("/api/v1/registration/flex")]);
  return (
    <Shell route="t/regoptions" me={me.ok ? me.data : null}>
      {!flex.ok ? <ProblemNotice problem={flex.problem} />
        : <RegistrationOptions flex={flex.data} mayChange={me.ok && ["academic", "registrar", "dregistrar", "ict", "super"].includes(me.data.activeOffice ?? "")} />}
    </Shell>
  );
}
