import HomePage from "@/src/HomePage";

const structuredData = {
  "@context": "https://schema.org",
  "@type": "WebApplication",
  name: "开场前 BeforeShow",
  alternateName: "BeforeShow",
  url: "https://beforeshow.doublewaterapps.com/",
  description:
    "开场前 BeforeShow 是用于现场准备与本地记录的工具，提供现场倒计时、记录票根、记录时刻表、现场记录等功能。",
  applicationCategory: "LifestyleApplication",
  operatingSystem: "iOS",
  author: { "@type": "Organization", name: "BeforeShow" },
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
