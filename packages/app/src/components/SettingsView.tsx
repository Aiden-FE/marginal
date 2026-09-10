// 设置（spec §4.5/4.7）：供应商 CRUD + 连通性诊断；每任务类型默认配置；代理指引。

import { useState } from "react";
import { uuidv7 } from "@marginal/core";
import { store, useStore, type ProviderEntry } from "../store";
import { diagnose as diagnoseAction, saveProvider, deleteProvider } from "../actions";

const TASKS: { key: "repair" | "restructure" | "extract" | "illustration"; label: string; hint: string }[] = [
  { key: "restructure", label: "章节切分", hint: "AI 识别章节边界（导入预览可调用）" },
  { key: "repair", label: "修复", hint: "便宜模型够用（清洗/边界复核）" },
  { key: "extract", label: "实体提取", hint: "便宜模型够用（JSON 输出）" },
  { key: "illustration", label: "插图生成", hint: "必须支持参考图输入（OpenAI edits 形状或火山方舟形状）" },
];

export function SettingsView() {
  useStore();
  const [, setTick] = useState(0);
  const refresh = () => setTick((t) => t + 1);

  function addProvider() {
    store.providers.push({
      id: uuidv7(), kind: "openai", name: "新供应商",
      baseUrl: "https://api.example.com/v1", apiKey: "", diagnostic: "unknown",
    });
    store.saveProviders();
    refresh();
  }

  function update(p: ProviderEntry, patch: Partial<ProviderEntry>) {
    saveProvider({ ...p, ...patch });
    refresh();
  }

  async function diagnose(p: ProviderEntry) {
    await diagnoseAction(p);
    refresh();
  }

  function taskConfigKey(kind: string): string {
    return `marginal.task.${kind}`;
  }

  return (
    <div>
      <div className="card">
        <div className="row">
          <b>AI 供应商</b>
          <button className="primary" onClick={addProvider}>＋ 添加供应商</button>
          <span className="muted">协议层仅 OpenAI-compatible（base URL + key + model）；插图任务经 per-provider adapter（OpenAI edits 形状 / 火山方舟形状）</span>
        </div>
        <table className="list">
          <thead><tr><th>名称</th><th>Base URL</th><th>API Key</th><th>诊断</th></tr></thead>
          <tbody>
            {store.providers.map((p) => (
              <tr key={p.id}>
                <td>
                  {p.kind === "demo" ? <b>{p.name}</b> : <input value={p.name} onChange={(e) => update(p, { name: e.target.value })} style={{ width: 120 }} />}
                  {p.kind === "demo" && <span className="badge" style={{ marginLeft: 6 }}>内置演示</span>}
                </td>
                <td>
                  {p.kind === "demo" ? <span className="muted">demo://local</span> :
                    <input value={p.baseUrl} onChange={(e) => update(p, { baseUrl: e.target.value })} style={{ width: 280 }} />}
                </td>
                <td>
                  {p.kind === "demo" ? <span className="muted">无需密钥</span> :
                    <input type="password" value={p.apiKey} onChange={(e) => update(p, { apiKey: e.target.value })} style={{ width: 160 }} />}
                </td>
                <td>
                  <button onClick={() => diagnose(p)}>{p.diagnostic === "checking" ? "检测中…" : "连通性诊断"}</button>{" "}
                  {p.diagnostic === "direct" && <span className="badge" style={{ color: "var(--ok)", borderColor: "var(--ok)" }}>可直连</span>}
                  {p.diagnostic === "needs-proxy" && <span className="badge failed">需代理</span>}
                  {p.kind === "openai" && <button className="danger" onClick={() => { deleteProvider(p.id); refresh(); }}>删除</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <b>任务类型默认配置</b>
        <p className="muted">每类任务独立配置供应商与模型（spec §4.5）；书内可覆盖。</p>
        <table className="list">
          <thead><tr><th>任务</th><th>供应商</th><th>执行模式</th><th>模型</th><th className="muted">建议</th></tr></thead>
          <tbody>
            {TASKS.map((t) => {
              const saved = localStorage.getItem(taskConfigKey(t.key));
              const cfg = saved ? JSON.parse(saved) : { providerId: "demo", model: "demo", mode: "agent" };
              return (
                <tr key={t.key}>
                  <td>{t.label}</td>
                  <td>
                    <select value={cfg.providerId} onChange={(e) => localStorage.setItem(taskConfigKey(t.key), JSON.stringify({ ...cfg, providerId: e.target.value }))}>
                      {store.providers.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                    </select>
                  </td>
                  <td>
                    <select aria-label={`${t.label}执行模式`} value={cfg.mode ?? "agent"} onChange={(e) => localStorage.setItem(taskConfigKey(t.key), JSON.stringify({ ...cfg, mode: e.target.value }))}>
                      <option value="agent">Agent</option>
                      <option value="direct">直连</option>
                    </select>
                  </td>
                  <td>
                    <input defaultValue={cfg.model} onChange={(e) => localStorage.setItem(taskConfigKey(t.key), JSON.stringify({ ...cfg, model: e.target.value }))} style={{ width: 160 }} />
                  </td>
                  <td className="muted">{t.hint}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="card">
        <b>浏览器直连与本地代理（spec §4.7）</b>
        <p className="muted">
          诊断显示"需代理"时，运行 <code>npm run proxy -- &lt;上游 base URL&gt;</code> 启动本地 CORS 代理（默认 127.0.0.1:8787），
          然后把供应商的 Base URL 改为 <code>http://127.0.0.1:8787/v1</code>。
        </p>
        <p className="muted">存储引擎：{store.engine}（SQLite WASM/OPFS 优先，IndexedDB 降级）。</p>
      </div>
    </div>
  );
}
