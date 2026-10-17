import OrangeCat from "./OrangeCat.jsx";

const plays = [
  {
    title: "点一点",
    text: "它会跳起来，连着摸会发出呼噜。太久没人理，它就自己睡着。",
  },
  {
    title: "丢毛线球",
    text: "它把球扔出来，你点一下球再丢回去。接得越多，它越开心。",
  },
  {
    title: "拖去别处",
    text: "抓住它换个角落。松开后如果还在半空，它会自己落下来。",
  },
];

const cares = [
  {
    title: "该休息眼睛了",
    text: "白天用电脑满一个小时，它会提醒你出去活动 5 分钟。还在用的话，半小时后再说一次。",
  },
  {
    title: "开饭啦",
    text: "中午 12 点和晚上 6 点，它会吃不同的东西，叫你也去吃饭。每天的午饭和晚饭都不一样。",
  },
];

function App() {
  return (
    <>
      <div className="sky" aria-hidden="true">
        <span className="blob one" />
        <span className="blob two" />
        <span className="paw p1">🐾</span>
        <span className="paw p2">🐾</span>
      </div>
      <header className="top">
        <a className="brand" href="#top">
          <span className="brand-mark" aria-hidden="true">🐱</span>
          橘猫
        </a>
        <a className="top-download" href="/OrangeCat.dmg" download>
          下载
        </a>
      </header>
      <main id="top">
        <section className="hero">
          <div className="hero-copy">
            <p className="eyebrow">macOS 桌面宠物</p>
            <h1>一只住在桌面上的橘猫</h1>
            <p className="lead">
              它趴在屏幕角落，不占 Dock，也不抢走你正在用的软件。点点它，或者陪它把毛线球丢来丢去。
            </p>
            <div className="actions">
              <a className="download" href="/OrangeCat.dmg" download>
                下载橘猫
                <small>macOS 13 或更高 · 832 KB</small>
              </a>
            </div>
            <p className="note">Apple 芯片和 Intel 都能用。菜单栏的 🐱 可以让它睡觉，或者退出。</p>
          </div>
          <div className="stage">
            <p className="bubble">喵~ 点我一起玩！</p>
            <OrangeCat />
          </div>
        </section>

        <section className="panel" aria-labelledby="play-title">
          <h2 id="play-title">怎么跟它玩</h2>
          <div className="cards">
            {plays.map((item) => (
              <article className="card" key={item.title}>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="panel warm" aria-labelledby="care-title">
          <h2 id="care-title">它也会照顾你</h2>
          <div className="cards two">
            {cares.map((item) => (
              <article className="card" key={item.title}>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="install" aria-labelledby="install-title">
          <h2 id="install-title">第一次打开</h2>
          <ol>
            <li>把「橘猫」拖进「应用程序」。</li>
            <li>如果系统说无法验证开发者，打开「系统设置 → 隐私与安全性」，点「仍要打开」。</li>
            <li>再打开一次，点「打开」。之后就不用再确认了。</li>
          </ol>
          <a className="download second" href="/OrangeCat.dmg" download>
            下载 OrangeCat.dmg
          </a>
        </section>
      </main>
      <footer>
        <p>橘猫住在你的 Mac 上，不需要账号。</p>
      </footer>
    </>
  );
}

export default App;
