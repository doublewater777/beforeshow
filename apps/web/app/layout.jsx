import "@/src/globals.css";

const siteUrl = "https://beforeshow.doublewaterapps.com";

export const metadata = {
  metadataBase: new URL(siteUrl),
  title: "开场前 BeforeShow — 演唱会、音乐节与 Livehouse 倒计时",
  description:
    "灯亮之前，先进入状态。开场前为下一场演唱会、音乐节或 Livehouse 留一个安静的倒数：现场倒计时、按阵容提前听歌、桌面小组件，散场后收进足迹。",
  alternates: { canonical: "/" },
  robots: { index: true, follow: true },
  openGraph: {
    type: "website",
    siteName: "开场前 BeforeShow",
    title: "开场前 BeforeShow — 演唱会、音乐节与 Livehouse 倒计时",
    description: "灯亮之前，先进入状态。开场前为下一场演唱会、音乐节或 Livehouse 留一个安静的倒数：现场倒计时、按阵容提前听歌、桌面小组件，散场后收进足迹。",
    url: "/",
    images: [{ url: "/app-icon.png", width: 1024, height: 1024 }],
    locale: "zh_CN",
  },
  twitter: {
    card: "summary",
    title: "开场前 BeforeShow — 演唱会、音乐节与 Livehouse 倒计时",
    description: "灯亮之前，先进入状态。开场前为下一场演唱会、音乐节或 Livehouse 留一个安静的倒数：现场倒计时、按阵容提前听歌、桌面小组件，散场后收进足迹。",
    images: ["/app-icon.png"],
  },
  itunes: { appId: "6780078298" },
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
  },
};

export const viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#05070D",
};

export default function RootLayout({ children }) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
