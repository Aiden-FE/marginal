import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { store } from "./store";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

// 任何未捕获错误直接渲染到页面（可诊断性优先）
function showFatal(msg: string): void {
  store.initError = msg;
  store.ready = true;
  store.emit();
}
window.addEventListener("error", (e) => showFatal(`运行时错误: ${e.message}\n${e.error?.stack ?? ""}`));
window.addEventListener("unhandledrejection", (e) => showFatal(`未处理的 Promise 拒绝: ${e.reason instanceof Error ? `${e.reason.message}\n${e.reason.stack}` : String(e.reason)}`));

// 初始化失败时把错误直接渲染出来（可诊断性优先）
void store
  .init()
  .then(() => {
    store.ready = true;
    store.emit();
  })
  .catch((err) => {
    store.initError = err instanceof Error ? err.message : String(err);
    store.emit();
  });
