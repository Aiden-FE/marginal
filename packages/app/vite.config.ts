import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: { target: "es2022" },
  optimizeDeps: {
    // sqlite-wasm 自带 wasm 加载逻辑，不能被预打包
    exclude: ["@sqlite.org/sqlite-wasm"],
  },
  worker: { format: "es" },
  server: { port: 5199 },
});
