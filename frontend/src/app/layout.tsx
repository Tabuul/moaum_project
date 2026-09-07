import type { Metadata } from "next";
import Link from "next/link";
import { IBM_Plex_Sans, IBM_Plex_Serif } from "next/font/google";
import "./globals.css";

/* next/font downloads these at BUILD time and serves them from here, so the
   portal never calls Google Fonts from a browser in Makurdi — the concern the
   prototype's README raised, closed by the framework. */
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
  description:
    "MOAUM Unified University Portal — Rev. Fr. Moses Orshio Adasu University, Makurdi",
};

const NAV = [
  { href: "/", label: "Status" },
  { href: "/admissions/caps", label: "Admission list" },
];

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${plexSans.variable} ${plexSerif.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">
        <header className="bg-chrome text-white">
          <div className="mx-auto flex max-w-6xl items-center gap-6 px-5 py-3">
            <Link href="/" className="flex items-center gap-3">
              <span
                aria-hidden
                className="grid h-8 w-8 place-items-center rounded-full border border-chrome-ink/50 font-serif text-xs font-bold"
              >
                M
              </span>
              <span className="leading-tight">
                <span className="block font-serif text-sm font-bold">MOAUM Portal</span>
                <span className="block text-[11px] text-chrome-ink">
                  Rev. Fr. Moses Orshio Adasu University, Makurdi
                </span>
              </span>
            </Link>
            <nav className="ml-auto flex gap-1 text-sm">
              {NAV.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className="rounded px-3 py-1.5 text-chrome-ink hover:bg-chrome-2 hover:text-white"
                >
                  {item.label}
                </Link>
              ))}
            </nav>
          </div>
        </header>
        <main className="mx-auto w-full max-w-6xl flex-1 px-5 py-8">{children}</main>
        <footer className="border-t border-line bg-surface">
          <div className="mx-auto max-w-6xl px-5 py-4 text-xs text-faint">
            Directorate of ICT · the portal is built on Spring Boot, Next.js and PostgreSQL
          </div>
        </footer>
      </body>
    </html>
  );
}
