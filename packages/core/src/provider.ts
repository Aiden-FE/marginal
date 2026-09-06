// 供应商抽象（spec §4.5）：文本走 OpenAI-compatible；图像经 per-provider adapter。
// 能力位决定 UI；参考图路径无统一兼容形状（research/003）。

import type { ChatMessage, ImageCapability, ImageRequest, ImageResult, ProviderConfig } from "./types.js";

export interface ChatOptions {
  temperature?: number;
  /** 要求 JSON 输出的提示（各供应商支持度不一，用提示词 + 解析容错） */
  json?: boolean;
  maxTokens?: number;
}

/** 流水线依赖的最小客户端接口（ProviderClient 与 DemoProvider 均满足） */
export interface LLMClient {
  chatJson<T>(messages: ChatMessage[], model: string, opts?: ChatOptions): Promise<T>;
}

export interface ImageClient {
  generateImage(req: ImageRequest): Promise<ImageResult>;
}

export class ProviderClient {
  constructor(public config: ProviderConfig) {}

  get baseUrl(): string {
    return this.config.baseUrl.replace(/\/+$/, "");
  }

  /** OpenAI-compatible chat completions；SSE 流式由调用方需要时再启用 */
  async chat(messages: ChatMessage[], model: string, opts: ChatOptions = {}): Promise<string> {
    const res = await fetch(`${this.baseUrl}/chat/completions`, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify({
        model,
        messages,
        temperature: opts.temperature ?? 0.2,
        ...(opts.maxTokens ? { max_tokens: opts.maxTokens } : {}),
        ...(opts.json ? { response_format: { type: "json_object" } } : {}),
      }),
    });
    if (!res.ok) throw new Error(`chat ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const data = await res.json();
    return data.choices?.[0]?.message?.content ?? "";
  }

  async chatJson<T>(messages: ChatMessage[], model: string, opts: ChatOptions = {}): Promise<T> {
    const text = await this.chat(messages, model, { ...opts, json: true });
    return parseJsonLoose<T>(text);
  }

  private headers(): Record<string, string> {
    return {
      "Content-Type": "application/json",
      ...(this.config.apiKey ? { Authorization: `Bearer ${this.config.apiKey}` } : {}),
    };
  }

  /** 连通性诊断（spec §4.7）：预检探测，标注可直连/需代理 */
  async diagnose(): Promise<"direct" | "needs-proxy"> {
    try {
      const url = `${this.baseUrl}/chat/completions`;
      const res = await fetch(url, {
        method: "OPTIONS",
        headers: {
          Origin: location.origin,
          "Access-Control-Request-Method": "POST",
          "Access-Control-Request-Headers": "authorization,content-type",
        },
      }).catch(() => fetch(url, { method: "GET" }));
      // 能拿到响应（无论状态码）说明至少网络可达；CORS 错误会直接 throw
      void res;
      return "direct";
    } catch {
      return "needs-proxy";
    }
  }

  /** 图像生成（兜底：无参考图路径） */
  async generateImage(req: ImageRequest): Promise<ImageResult> {
    const adapter = pickImageAdapter(this.baseUrl);
    return adapter(req);
  }
}

export function imageCapability(): ImageCapability {
  return { supportsReference: true, maxReferences: 3 };
}

type ImageAdapter = (req: ImageRequest) => Promise<ImageResult>;

function pickImageAdapter(baseUrl: string): ImageAdapter {
  // 火山方舟形状：/api/v3/images/generations，image 参数为 URL/base64 数组 + 自有扩展参数
  if (/volces\.com|ark/i.test(baseUrl)) return arkImageAdapter(baseUrl);
  // 默认：OpenAI edits 形状（/v1/images/edits，multipart image[]）
  return openaiEditsAdapter(baseUrl);
}

function openaiEditsAdapter(baseUrl: string): ImageAdapter {
  return async (req) => {
    const form = new FormData();
    form.append("model", req.model);
    form.append("prompt", req.prompt);
    form.append("n", "1");
    for (const ref of req.references) {
      const bytes = Uint8Array.from(atob(ref.dataBase64), (c) => c.charCodeAt(0));
      form.append("image[]", new Blob([bytes], { type: ref.mime }), "reference.png");
    }
    const res = await fetch(`${baseUrl.replace(/\/+$/, "")}/images/edits`, {
      method: "POST",
      headers: { Authorization: `Bearer ${globalThis.__marginalApiKey ?? ""}` },
      body: form,
    });
    if (!res.ok) throw new Error(`images/edits ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const data = await res.json();
    const item = data.data?.[0];
    return item.b64_json
      ? { mime: "image/png", dataBase64: item.b64_json }
      : { mime: "image/png", dataBase64: await fetchAsBase64(item.url) };
  };
}

function arkImageAdapter(baseUrl: string): ImageAdapter {
  return async (req) => {
    const res = await fetch(`${baseUrl.replace(/\/+$/, "")}/images/generations`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${globalThis.__marginalApiKey ?? ""}`,
      },
      body: JSON.stringify({
        model: req.model,
        prompt: req.prompt,
        sequential_image_generation: "disabled",
        ...(req.references.length
          ? { image: req.references.map((r) => `data:${r.mime};base64,${r.dataBase64}`) }
          : {}),
        response_format: "b64_json",
      }),
    });
    if (!res.ok) throw new Error(`ark images ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const data = await res.json();
    const item = data.data?.[0];
    return item.b64_json
      ? { mime: "image/png", dataBase64: item.b64_json }
      : { mime: "image/png", dataBase64: await fetchAsBase64(item.url) };
  };
}

async function fetchAsBase64(url: string): Promise<string> {
  const res = await fetch(url);
  const buf = new Uint8Array(await res.arrayBuffer());
  let bin = "";
  for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(bin);
}

export function parseJsonLoose<T>(text: string): T {
  try {
    return JSON.parse(text) as T;
  } catch {
    const m = text.match(/\{[\s\S]*\}|\[[\s\S]*\]/);
    if (m) return JSON.parse(m[0]) as T;
    throw new Error(`无法解析 JSON: ${text.slice(0, 200)}`);
  }
}

declare global {
  // 图像 adapter 的请求级密钥由调用方注入（fetch headers 无法从 ImageRequest 透传 FormData 场景之外）
  interface GlobalThis {
    __marginalApiKey?: string;
  }
  // eslint-disable-next-line no-var
  var __marginalApiKey: string | undefined;
}
