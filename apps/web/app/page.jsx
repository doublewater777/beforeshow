import HomePage from "@/src/HomePage";

const structuredData = {
  "@context": "https://schema.org",
  "@type": "MobileApplication",
  name: "开场前 BeforeShow",
  alternateName: "BeforeShow",
  url: "https://beforeshow.doublewaterapps.com/",
  description:
    "灯亮之前，先进入状态。开场前为下一场演唱会、音乐节或 Livehouse 留一个安静的倒数：现场倒计时、按阵容提前听歌、桌面小组件，散场后收进足迹。",
  applicationCategory: "MusicApplication",
  operatingSystem: "iOS",
  author: { "@type": "Organization", name: "BeforeShow" },
  installUrl: "https://apps.apple.com/cn/app/id6780078298",
  offers: { "@type": "Offer", price: "0", priceCurrency: "CNY" },
};

export default function Page() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
      />
      <HomePage />
    </>
  );
}
