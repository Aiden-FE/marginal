import { store, useStore } from "../store";
import { queueProgress } from "./logic";

const STATE_LABEL: Record<string, string> = {
  pending: "排队",
  running: "执行中",
  done: "完成",
  failed: "失败",
  cancelled: "已取消",
};

export function MobileTasks() {
  useStore();
  const tasks = store.queue.tasksSnapshot;
  const progress = queueProgress(tasks);
  const paused = progress.active > 0 && !tasks.some((task) => task.state === "running");

  return (
    <section className="m-page m-tasks">
      <div className="m-card">
        <div className="m-card-head">
          <h3>队列概览</h3>
          <span className={`m-badge${paused ? " paused" : ""}`}>{paused ? "已暂停" : progress.active > 0 ? "运行中" : "空闲"}</span>
        </div>
        <div className="m-big-progress">
          <div className="m-progress-track big"><div style={{ width: `${Math.round(progress.ratio * 100)}%` }} /></div>
          <div className="m-stats-row">
            <div><strong>{progress.done}</strong><span>完成</span></div>
            <div><strong>{progress.active}</strong><span>进行中</span></div>
            <div><strong>{progress.failed}</strong><span>失败</span></div>
            <div><strong>{store.queue.budgetSpent}</strong><span>已花费</span></div>
          </div>
        </div>
        {tasks.length > 0 && (
          <div className="m-inline-actions">
            {paused
              ? <button className="m-primary" onClick={() => { store.queue.resume(); store.emit(); }}>▶ 恢复</button>
              : <button onClick={() => { store.queue.pause(); store.emit(); }}>⏸ 暂停</button>}
            <button className="m-danger" onClick={() => { store.queue.cancelAll(); store.emit(); }}>全部取消</button>
          </div>
        )}
      </div>

      <div className="m-card">
        <h3>任务列表</h3>
        {tasks.length === 0 ? (
          <p className="m-hint">队列目前是空的——去插图、修复或实体卡页生成点任务吧。</p>
        ) : (
          <ul className="m-task-list">
            {[...tasks].reverse().map((task) => (
              <li key={task.id} className={`m-task-${task.state}`}>
                <div>
                  <p className="m-task-label">{task.label}</p>
                  {task.error && <span className="m-error">{task.error}</span>}
                  <span className="m-hint">第 {task.attempts} 次尝试</span>
                </div>
                <span className={`m-badge ${task.state}`}>{STATE_LABEL[task.state]}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
