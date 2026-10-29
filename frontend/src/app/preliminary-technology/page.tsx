import type { Metadata } from "next";
import { PrelimProgrammePage } from "@/components/preliminary/PrelimProgrammePage";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Preliminary Technology & Industrial Studies",
  description: "The University's Preliminary Technology & Industrial Studies programme: purpose, entry requirements, areas and specialisations, application fee and how to apply.",
};

/** /preliminary-technology — public, no sign-in (V701): the programme as the University's configuration states it, on the shared page */
export default async function PreliminaryTechnologyPage() {
  return <PrelimProgrammePage slug="preliminary-technology" />;
}
