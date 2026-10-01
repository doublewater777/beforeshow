const APP_STORE_URL = "https://apps.apple.com/cn/app/id6780078298";

const features = [
  {
    id: "listen",
    kicker: "听",
    title: "开场前，先把歌听熟",
    desc: "按这一场的阵容整理热门合辑，放进拟物 CD 机里。走进现场时，每一首都已经熟悉。",
    screen: "/screens/listen.jpg",
    alt: "开场前「听」页：CD 机与按阵容整理的热门合辑",
  },
  {
    id: "widgets",
    kicker: "桌面小组件",
    title: "不用打开，也在靠近",
    desc: "倒计时和正在听的歌放在主屏上。解锁手机的每一次，都离开场更近一点。",
    screen: "/screens/home.jpg",
    alt: "主屏上的开场前倒计时与播放器小组件",
  },
  {
    id: "footprints",
    kicker: "足迹",
    title: "散场后，收进足迹",
    desc: "去过的场次、城市、场馆和艺人会慢慢累积，回头看看，就是你的现场生活。",
    screen: "/screens/footprints.jpg",
    alt: "开场前「足迹」页：现场场次、轨迹与艺人统计",
  },
];

const reminders = ["开场前 14 天", "7 天", "3 天", "1 天", "当天上午", "开场前 3 小时", "散场次日"];

function AppStoreButton({ className = "" }) {
  return (
    <a className={`store-btn ${className}`} href={APP_STORE_URL} target="_blank" rel="noopener noreferrer">
      <svg className="store-btn-mark" viewBox="0 0 384 512" aria-hidden="true">
        <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
      </svg>
      <span className="store-btn-text">
        <small>在 App Store</small>
        免费下载
      </span>
    </a>
  );
}

function Phone({ src, alt, eager = false }) {
  return (
    <div className="phone">
      <img src={src} alt={alt} width="720" height="1565" loading={eager ? "eager" : "lazy"} />
    </div>
  );
}

export default function HomePage() {
  return (
    <>
      <a href="#main-content" className="skip-link">跳到主要内容</a>
      <header className="site-nav">
        <a className="nav-logo" href="/">
          <img src="/app-icon.png" alt="" width="32" height="32" />
          <span>开场前</span>
        </a>
        <a className="nav-cta" href={APP_STORE_URL} target="_blank" rel="noopener noreferrer">下载</a>
      </header>

      <main id="main-content">
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-seam" aria-hidden="true" />
          <div className="hero-copy">
            <p className="eyebrow"><span className="eyebrow-dot" />演唱会 · 音乐节 · Livehouse 倒计时</p>
            <h1 id="hero-title" className="hero-title">灯亮之前，<br />先进入状态。</h1>
            <p className="hero-sub">首页只围着下一场：海报、开场时间和倒计时都在一屏里，陪你慢慢靠近这一场。</p>
            <div className="hero-actions">
              <AppStoreButton />
              <span className="hero-note">iOS · 前 5 场免费保存</span>
            </div>
          </div>
          <div className="hero-visual">
            <Phone src="/screens/current.jpg" alt="开场前「当前」页：现场海报与开场倒计时" eager />
          </div>
        </section>

        {features.map((feature, index) => (
          <section
            className={`feature ${index % 2 ? "feature-flip" : ""}`}
            id={feature.id}
            key={feature.id}
            aria-labelledby={`${feature.id}-title`}
          >
            <div className="feature-copy">
              <p className="feature-kicker">{String(index + 1).padStart(2, "0")} · {feature.kicker}</p>
              <h2 className="feature-title" id={`${feature.id}-title`}>{feature.title}</h2>
              <p className="feature-desc">{feature.desc}</p>
            </div>
            <div className="feature-visual">
              <Phone src={feature.screen} alt={feature.alt} />
            </div>
          </section>
        ))}

        <section className="reminders" aria-labelledby="reminders-title">
          <p className="feature-kicker">轻轻提醒</p>
          <h2 className="feature-title" id="reminders-title">只在该出现的时候出现</h2>
          <p className="feature-desc">提醒用你已经记下的现场信息说话，不刷屏，也不打扰。</p>
          <ol className="reminder-track">
            {reminders.map((label) => (
              <li key={label}><span className="reminder-dot" />{label}</li>
            ))}
          </ol>
        </section>

        <section className="closing" aria-labelledby="closing-title">
          <img className="closing-icon" src="/app-icon.png" alt="" width="96" height="96" loading="lazy" />
          <h2 className="closing-title" id="closing-title">下一场，从开场前开始。</h2>
          <AppStoreButton />
        </section>
      </main>

      <footer className="footer">
        <span>开场前 · BeforeShow</span>
        <nav className="footer-links" aria-label="页脚链接">
          <a href="/privacy/">隐私政策</a>
          <a href="/terms/">用户协议</a>
          <a href="/link-guide/">如何获取票务链接</a>
          <a href="https://beian.miit.gov.cn/" target="_blank" rel="noopener noreferrer">浙ICP备2026041359号-2</a>
        </nav>
      </footer>
    </>
  );
}
