# v2 H5 迁移说明

Flutter Web 已替换旧 React H5。旧版本浏览器中的 IndexedDB/OPFS 数据不会自动迁移；请在旧版本逐本导出 `.mabk` 全书包，再在新 H5 中导入并选择“副本”或“覆盖”。

未来发布流程：在 `apps/marginal` 执行 `flutter build web --release --no-wasm-dry-run`，将 `build/web` 复制为 `web-dist` 后提交；Vercel 根目录直接托管 `apps/marginal/web-dist`。

## 生产 URL 与访问保护（2026-09-12 核验）

- 生产项目：Vercel scope `aiden-fes-projects` 下的 `marginal-app`；生产别名 `https://marginal-app-aiden-fes-projects.vercel.app`。
- **不要使用 `marginal-app.vercel.app`**：`*.vercel.app` 是全局命名空间，该名字已被一个无关的肯尼亚 NGO 网站占用。
- 该项目开启了 Vercel Deployment Protection（SSO）：未登录访问任何部署 URL 都会跳到 `vercel.com/login`。在浏览器登录 Vercel 后即可正常打开；或在 Project → Settings → Deployment Protection 关闭保护。
- commit 绑定证据：GitHub commit status `Vercel: success — Deployment has completed`，Production deployment sha `ce57500a`（API：repos/Aiden-FE/marginal/deployments）。
