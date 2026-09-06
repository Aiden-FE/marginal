// 任务队列面板（spec §4.6）：进度/暂停/恢复/取消/预算触顶提示。

import { store, useStore } from "../store";

export function QueuePanel() {
  useStore();
  if (store.queue.pendingCount === 0 && store.queue.tasksSnapshot.every((t) => t.state !== "failed")) return null;
  const paused = store.queue.pendingCount > 0 && store.queue.tasksSnapshot.every((t) => t.state !== "running");
  return (
    <div className="queue-panel">
      <div className="row" style={{ justifyContent: "space-between" }}>
        <b>任务队列</b>
        <span className="muted">
          {store.queue.pendingCount} 个待处理{paused ? " · 已暂停" : ""}
        </span>
      </div>
      <div style={{ maxHeight: 160, overflow: "auto" }}>
        {store.queue.tasksSnapshot.slice(-8).map((t) => (
          <div className="t" key={t.id}>
            <span>{t.label}</span>
            <span className={`badge ${t.state === "failed" ? "failed" : t.state === "done" ? "canon" : "draft"}`}>
              {t.state === "done" ? "完成" : t.state === "failed" ? "失败" : t.state === "running" ? "执行中" : t.state === "cancelled" ? "已取消" : "排队"}
            </span>
          </div>
        ))}
      </div>
      <div className="row" style={{ marginTop: 6 }}>
        {paused
          ? <button onClick={() => store.queue.resume()}>▶ 恢复</button>
          : <button onClick={() => store.queue.pause()}>⏸ 暂停</button>}
        <button className="danger" onClick={() => { store.queue.cancelAll(); store.emit(); }}>全部取消</button>
      </div>
    </div>
  );
}
