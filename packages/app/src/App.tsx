import { useEffect } from "react";
import { store, useStore } from "./store";
import { LibraryView } from "./components/LibraryView";
import { ReaderView } from "./components/ReaderView";
import { RepairView } from "./components/RepairView";
import { EntitiesView } from "./components/EntitiesView";
import { IllustrationsView } from "./components/IllustrationsView";
import { SettingsView } from "./components/SettingsView";
import { QueuePanel } from "./components/QueuePanel";
import { MobileApp } from "./mobile/MobileApp";
import { currentUiMode } from "./mobile/logic";

const uiMode = currentUiMode();

export function App() {
  useStore();
  useEffect(() => {
    if (store.view.name === "work") {
      const { workId } = store.view;
      if (!store.works.some((w) => w.id === workId)) store.navigate({ name: "library" });
    }
  });
  if (store.initError) {
    return <div style={{ padding: 40 }}>
      <h2 style={{ color: "var(--danger)" }}>初始化失败</h2>
      <pre style={{ whiteSpace: "pre-wrap", color: "var(--muted)" }}>{store.initError}</pre>
      <p className="muted">可尝试更换存储引擎：在地址栏加 ?engine=indexeddb</p>
    </div>;
  }
  if (!store.ready) return <div style={{ padding: 40 }} className="muted">初始化存储引擎中…</div>;
  if (uiMode === "mobile") return <MobileApp />;
  const view = store.view;
  const current = view.name === "work" ? store.works.find((w) => w.id === view.workId) : undefined;

  return (
    <div className="layout">
      <nav className="sidebar">
        <div className="logo">📚 Marginal</div>
        <button className={view.name === "library" ? "active" : ""} onClick={() => store.navigate({ name: "library" })}>书架</button>
        {view.name === "work" && current && (
          <>
            <div className="muted" style={{ padding: "8px 10px 0" }}>《{current.title}》</div>
            {(["reader", "repair", "entities", "illustrations"] as const).map((tab) => (
              <button
                key={tab}
                className={view.tab === tab ? "active" : ""}
                onClick={() => store.navigate({ name: "work", workId: view.workId, tab })}
              >
                {tab === "reader" ? "📖 阅读" : tab === "repair" ? "🔧 修复与修订" : tab === "entities" ? "👤 实体卡" : "🖼 插图"}
              </button>
            ))}
          </>
        )}
        <div style={{ flex: 1 }} />
        <button className={view.name === "settings" ? "active" : ""} onClick={() => store.navigate({ name: "settings" })}>⚙️ 设置</button>
        <div className="muted" style={{ padding: "0 10px" }}>引擎：{store.engine}</div>
      </nav>
      <main className="main">
        {view.name === "library" && <LibraryView />}
        {view.name === "settings" && <SettingsView />}
        {view.name === "work" && current && view.tab === "reader" && <ReaderView work={current} />}
        {view.name === "work" && current && view.tab === "repair" && <RepairView work={current} />}
        {view.name === "work" && current && view.tab === "entities" && <EntitiesView work={current} />}
        {view.name === "work" && current && view.tab === "illustrations" && <IllustrationsView work={current} />}
      </main>
      <QueuePanel />
      {store.toast && <div className="toast">{store.toast}</div>}
    </div>
  );
}
