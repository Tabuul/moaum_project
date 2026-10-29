import type { Metadata } from "next";
import { PrelimProgrammePage } from "@/components/preliminary/PrelimProgrammePage";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Preliminary Science Programme",
  description: "The University's Preliminary Science Programme: entry requirements, target programmes, application fee and how to apply.",
};

/**
 * /preliminary-science — public, no sign-in (V446): the Preliminary Science Programme as the University's configuration states
 * it, on the page every preliminary and proficiency programme shares (V701). Nothing here is typed into the page: every figure is
 * read from the API.
 */
export default async function PreliminarySciencePage() {
  return <PrelimProgrammePage slug="preliminary-science" />;
}
