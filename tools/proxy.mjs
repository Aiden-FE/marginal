#!/usr/bin/env node
// 本地一键 CORS 代理（spec §4.7，research/002 缓解方案）。
// 用法：node tools/proxy.mjs <上游 base URL> [端口]
// 例： node tools/proxy.mjs https://api.anthropic.com/v1 8787
// 然后把供应商 Base URL 配为 http://127.0.0.1:<端口>

import http from "node:http";

const upstream = process.argv[2];
const port = parseInt(process.argv[3] ?? "8787", 10);
if (!upstream) {
  console.error("用法：node tools/proxy.mjs <上游 base URL> [端口]");
  process.exit(1);
}
const upstreamBase = upstream.replace(/\/+$/, "");

const server = http.createServer(async (req, res) => {
  // CORS 预检一律放行
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": req.headers.origin ?? "*",
      "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
      "Access-Control-Allow-Headers": req.headers["access-control-request-headers"] ?? "*",
      "Access-Control-Max-Age": "86400",
    });
    return res.end();
  }
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = Buffer.concat(chunks);
  const target = `${upstreamBase}${req.url ?? ""}`;
  try {
    const headers = { ...req.headers };
    delete headers.host;
    delete headers.origin;
    delete headers.referer;
    const upstreamRes = await fetch(target, { method: req.method, headers, body: body.length ? body : undefined });
    const resHeaders = Object.fromEntries(upstreamRes.headers.entries());
    resHeaders["access-control-allow-origin"] = req.headers.origin ?? "*";
    res.writeHead(upstreamRes.status, resHeaders);
    const buf = Buffer.from(await upstreamRes.arrayBuffer());
    res.end(buf);
  } catch (err) {
    res.writeHead(502, {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": req.headers.origin ?? "*",
    });
    res.end(JSON.stringify({ error: { message: `代理请求失败: ${err instanceof Error ? err.message : err}` } }));
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Marginal 本地代理已启动: http://127.0.0.1:${port}  →  ${upstreamBase}`);
  console.log(`把应用内该供应商的 Base URL 设为 http://127.0.0.1:${port}（会自动拼接上游路径）`);
});
