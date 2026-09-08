import type { Metadata } from "next";
import { IBM_Plex_Sans, IBM_Plex_Serif } from "next/font/google";
import "./globals.css";

/* next/font downloads these at BUILD time and serves them from here, so the
   portal never calls Google Fonts from a browser in Makurdi. */
const plexSans = IBM_Plex_Sans({
  variable: "--font-plex-sans",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

const plexSerif = IBM_Plex_Serif({
  variable: "--font-plex-serif",
  subsets: ["latin"],
  weight: ["600", "700"],
});

export const metadata: Metadata = {
  title: "MOAUM Portal",
  description: "MOAUM Unified University Portal — Rev. Fr. Moses Orshio Adasu University, Makurdi",
};

/* The page is the prototype's page: #app holds the shell, and the shell is
   rendered by each screen with its own title (components/proto/Shell). */
export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${plexSans.variable} ${plexSerif.variable}`}>
      <body>
        <div id="app">{children}</div>
      </body>
    </html>
  );
}
