import type { Metadata } from "next";
import "./globals.css";
import { ToastHost } from "@/components/proto/Toast";

/* IBM Plex is shipped with the portal (app/fonts.css → public/fonts), so neither the build nor a browser in
   Makurdi ever calls Google Fonts — a build once failed on the CI runner for want of that fetch. */
export const metadata: Metadata = {
  title: "MOAUM Portal",
  description: "MOAUM Unified University Portal — Rev. Fr. Moses Orshio Adasu University, Makurdi",
};

/* The page is the prototype's page: #app holds the shell, and the shell is
   rendered by each screen with its own title (components/proto/Shell). */
export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en">
      <body>
        <div id="app">{children}</div>
        {/* the one notification host, for every page — the shell's screens and the standalone ones alike */}
        <ToastHost />
      </body>
    </html>
  );
}
