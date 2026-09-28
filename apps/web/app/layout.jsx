import "@/src/globals.css";

const siteUrl = "https://beforeshow.doublewaterapps.com";

export const metadata = {
  metadataBase: new URL(siteUrl),
  title: "开场前 BeforeShow — 现场准备与本地记录工具",
  description:
    "开场前 BeforeShow 是用于现场准备与本地记录的工具，提供现场倒计时、记录票根、记录时刻表、现场记录等功能。",
  alternates: { canonical: "/" },
  robots: { index: true, follow: true },
  openGraph: {
    type: "website",
    siteName: "开场前 BeforeShow",
    title: "开场前 BeforeShow — 现场准备与本地记录工具",
    description: "用于现场准备与本地记录：现场倒计时、记录票根、记录时刻表、现场记录。",
    url: "/",
    images: [{ url: "/app-icon.png", width: 1024, height: 1024 }],
    locale: "zh_CN",
  },
  twitter: {
    card: "summary",
    title: "开场前 BeforeShow — 现场准备与本地记录工具",
    description: "用于现场准备与本地记录，提供现场倒计时、记录票根、记录时刻表、现场记录等功能。",
    images: ["/app-icon.png"],
  },
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
  },
};

export const viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#0a0a0f",
};

export default function RootLayout({ children }) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
