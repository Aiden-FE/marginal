# v2 H5 迁移说明

Flutter Web 已替换旧 React H5。旧版本浏览器中的 IndexedDB/OPFS 数据不会自动迁移；请在旧版本逐本导出 `.mabk` 全书包，再在新 H5 中导入并选择“副本”或“覆盖”。

未来发布流程：在 `apps/marginal` 执行 `flutter build web --release --no-wasm-dry-run`，将 `build/web` 复制为 `web-dist` 后提交；Vercel 根目录直接托管 `apps/marginal/web-dist`。
