import { useEffect, useMemo, useState } from "react";
import { store, useStore } from "../store";
import { MobileLibrary } from "./MobileLibrary";
import { MobileImport } from "./MobileImport";
import { MobileReader } from "./MobileReader";
import { MobileRepair } from "./MobileRepair";
import { MobileEntities } from "./MobileEntities";
import { MobileIllustrations } from "./MobileIllustrations";
import { MobileTasks } from "./MobileTasks";
import { MobileSettings } from "./MobileSettings";
import { MiniQueueProgress } from "./shared";
import type { MobileRoute, MobileWorkTab } from "./types";
import "./mobile.css";

const TAB_LABEL: Record<MobileWorkTab, string> = {
  reader: "阅读",
  repair: "修复",
  entities: "实体卡",
  illustrations: "插图",
};

export function MobileApp() {
  useStore();
  const [route, setRoute] = useState<MobileRoute>({ name: "library" });
  const work = route.name === "work" ? store.works.find((item) => item.id === route.workId) : undefined;

  useEffect(() => {
    if (route.name === "work" && !work) setRoute({ name: "library" });
  }, [route, work]);

  const rootTitle = useMemo(() => {
    if (route.name === "library") return "我的书架";
    if (route.name === "tasks") return "任务队列";
    if (route.name === "settings") return "我的";
    if (route.name === "work" && work) return `${TAB_LABEL[route.tab]} · ${work.title}`;
    return "";
  }, [route, work]);

  const showRootHeader = route.name !== "import" && !(route.name === "work" && route.tab === "reader");
  const showTabs = route.name === "library" || route.name === "tasks" || route.name === "settings";

  function openWork(workId: string, tab: MobileWorkTab) {
    setRoute({ name: "work", workId, tab });
  }

  return (
    <div className="mobile-app">
      {showRootHeader && (
        <header className="m-topbar">
          {route.name === "work" ? (
            <button className="m-icon-btn" aria-label="返回书架" onClick={() => setRoute({ name: "library" })}>‹</button>
          ) : <div className="m-brand-mark">M</div>}
          <h1>{rootTitle}</h1>
          {route.name === "library" ? (
            <button className="m-top-action" onClick={() => setRoute({ name: "import" })}>＋ 导入</button>
          ) : <span className="m-top-spacer" />}
          {(route.name === "library" || route.name === "work") && <MiniQueueProgress />}
        </header>
      )}

      <main className={`m-content${showTabs ? " with-tabs" : ""}${!showRootHeader ? " fullscreen" : ""}`}>
        {route.name === "library" && <MobileLibrary onImport={() => setRoute({ name: "import" })} onOpenWork={openWork} />}
        {route.name === "import" && <MobileImport onBack={() => setRoute({ name: "library" })} onImported={(workId) => openWork(workId, "reader")} />}
        {route.name === "tasks" && <MobileTasks />}
        {route.name === "settings" && <MobileSettings />}
        {route.name === "work" && work && route.tab === "reader" && (
          <MobileReader work={work} onBack={() => setRoute({ name: "library" })} onOpenWorkTab={(tab) => openWork(work.id, tab)} />
        )}
        {route.name === "work" && work && route.tab === "repair" && <MobileRepair work={work} />}
        {route.name === "work" && work && route.tab === "entities" && <MobileEntities work={work} />}
        {route.name === "work" && work && route.tab === "illustrations" && <MobileIllustrations work={work} />}
      </main>

      {showTabs && (
        <nav className="m-tabs" aria-label="主导航">
          <button className={route.name === "library" ? "active" : ""} onClick={() => setRoute({ name: "library" })}>
            <span>📚</span><small>书架</small>
          </button>
          <button className={route.name === "tasks" ? "active" : ""} onClick={() => setRoute({ name: "tasks" })}>
            <span className="m-tab-icon-wrap">⏳{store.queue.pendingCount > 0 && <i>{store.queue.pendingCount}</i>}</span><small>任务</small>
          </button>
          <button className={route.name === "settings" ? "active" : ""} onClick={() => setRoute({ name: "settings" })}>
            <span>⚙️</span><small>我的</small>
          </button>
        </nav>
      )}
      {store.toast && <div className="m-toast" role="status">{store.toast}</div>}
    </div>
  );
}
