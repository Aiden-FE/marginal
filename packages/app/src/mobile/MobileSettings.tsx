import { useCallback, useEffect, useState } from "react";
import { uuidv7 } from "@marginal/core";
import { diagnose as diagnoseAction, saveProvider, deleteProvider } from "../actions";
import { store, useStore, type ProviderEntry } from "../store";

const TASKS: { key: "repair" | "extract" | "illustration"; label: string; hint: string }[] = [
  { key: "repair", label: "修复", hint: "便宜模型够用（清洗/边界复核）" },
  { key: "extract", label: "实体提取", hint: "便宜模型够用（JSON 输出）" },
  { key: "illustration", label: "插图生成", hint: "需支持参考图输入" },
];

function taskKey(kind: string) { return `marginal.task.${kind}`; }

export function MobileSettings() {
  useStore();
  const [taskConfigs, setTaskConfigs] = useState<Record<string, { providerId: string; model: string }>>(() => (
    Object.fromEntries(TASKS.map((task) => [task.key, JSON.parse(localStorage.getItem(taskKey(task.key)) || '{"providerId":"demo","model":"demo"}')]))
  ));
  const [tick, setTick] = useState(0);
  const refresh = () => setTick((value) => value + 1);

  const updateConfig = (kind: string, patch: Partial<{ providerId: string; model: string }>) => {
    const next = { ...taskConfigs, [kind]: { ...taskConfigs[kind], ...patch } };
    localStorage.setItem(taskKey(kind), JSON.stringify(next[kind]));
    setTaskConfigs(next);
  };

  const update = (entry: ProviderEntry, patch: Partial<ProviderEntry>) => {
    saveProvider({ ...entry, ...patch });
    refresh();
  };

  const addProvider = () => {
    saveProvider({
      id: uuidv7(), kind: "openai", name: "新供应商",
      baseUrl: "https://api.example.com/v1", apiKey: "", diagnostic: "unknown",
    });
    refresh();
  };

  const [showDemo, setShowDemo] = useState(false);

  return (
    <section className="m-page m-settings">
      <div className="m-card">
        <div className="m-card-head"><h3>存储引擎</h3><span className="m-badge">{store.engine.startsWith("indexeddb") ? "indexeddb" : "sqlite"}</span></div>
        <p>{store.engine}</p>
        {store.engine.includes("降级") && <p className="m-hint">当前环境不支持 OPFS/SQLite WASM，自动降级为 IndexedDB，功能一致但性能稍弱。</p>}
      </div>

      <div className="m-card">
        <div className="m-card-head">
          <h3>AI 供应商</h3>
          <button className="m-text-btn" onClick={addProvider}>＋ 添加</button>
        </div>
        <p className="m-hint">协议层仅 OpenAI-compatible（base URL + key + model）。</p>
        <div className="m-provider-list">
          {store.providers.map((provider) => (
            <div className="m-provider-item" key={provider.id}>
              <div className="m-provider-head">
                <strong>{provider.name}</strong>
                {provider.kind === "demo" && <span className="m-badge canon">内置演示</span>}
              </div>
              {provider.kind === "demo" ? (
                <p className="m-hint">无需配置，Mock 数据，适合体验流程。</p>
              ) : (
                <div className="m-field">
                  <span>名称</span>
                  <input value={provider.name} onChange={(event) => update(provider, { name: event.target.value })} />
                  <span>Base URL</span>
                  <input value={provider.baseUrl} onChange={(event) => update(provider, { baseUrl: event.target.value })} />
                  <span>API Key</span>
                  <input type="password" value={provider.apiKey} onChange={(event) => update(provider, { apiKey: event.target.value })} />
                </div>
              )}
              <div className="m-provider-actions">
                <button onClick={() => void diagnoseAction(provider)}>
                  {provider.diagnostic === "checking" ? "检测中…" : "连通性诊断"}
                </button>
                {provider.diagnostic === "direct" && <span className="m-badge ok">可直连</span>}
                {provider.diagnostic === "needs-proxy" && <span className="m-badge failed">需代理</span>}
                {provider.kind === "openai" && (
                  <button className="m-danger" onClick={() => { deleteProvider(provider.id); refresh(); }}>删除</button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="m-card">
        <h3>任务类型默认配置</h3>
        <p className="m-hint">每类任务独立配置供应商与模型，每本书可覆盖。</p>
        {TASKS.map((task) => (
          <div className="m-task-config" key={task.key}>
            <div className="m-task-config-head"><strong>{task.label}</strong><span className="m-hint">{task.hint}</span></div>
            <div className="m-task-config-row">
              <label>
                <span>供应商</span>
                <select
                  value={taskConfigs[task.key].providerId}
                  onChange={(event) => updateConfig(task.key, { providerId: event.target.value })}
                >
                  {store.providers.map((provider) => <option key={provider.id} value={provider.id}>{provider.name}</option>)}
                </select>
              </label>
              <label>
                <span>模型</span>
                <input
                  value={taskConfigs[task.key].model}
                  onChange={(event) => updateConfig(task.key, { model: event.target.value })}
                />
              </label>
            </div>
          </div>
        ))}
      </div>

      <div className="m-card">
        <h3>关于演示模式</h3>
        <button className="m-text-btn" onClick={() => setShowDemo((value) => !value)}>
          {showDemo ? "收起" : "展开使用说明"}
        </button>
        {showDemo && (
          <p className="m-hint">
            演示模式用内置 Mock 数据模拟 AI 响应，不需要任何 API key。
            建议第一次使用时先在「书架」点「使用示例书」体验完整流程。
            浏览器直连外部供应商失败时，可运行 <code>pnpm proxy</code> 启动本地 CORS 代理。
          </p>
        )}
      </div>

      <p className="m-copyright">Marginal · v0.1 · 移动端 H5</p>
    </section>
  );
}
