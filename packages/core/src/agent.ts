// AI Agent 网关：业务流水线只依赖此接口，不直接依赖具体供应商传输。
// 浏览器环境默认使用本地 adapter；未来可将同一接口替换为 Pi/MCP 远端 agent。

import type { ChatMessage, ImageRequest, ImageResult } from "./types.js";
import type { ChatOptions, LLMClient } from "./provider.js";

export interface AgentSkill {
  id: string;
  description: string;
  systemPrompt: string;
}

export interface AgentTool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  execute: (input: unknown) => Promise<unknown>;
}

export interface AgentGateway extends LLMClient {
  readonly kind: "direct" | "agent";
  readonly skills: readonly AgentSkill[];
  readonly tools: readonly AgentTool[];
  chat(messages: ChatMessage[], model: string, opts?: ChatOptions): Promise<string>;
  generateImage?(request: ImageRequest): Promise<ImageResult>;
  /** 为未来 Pi/MCP transport 保留的显式扩展点；当前工具由宿主注册后可直接执行。 */
  invokeTool(name: string, input: unknown): Promise<unknown>;
}

export interface AgentGatewayOptions {
  skills?: AgentSkill[];
  tools?: AgentTool[];
}

type ChatTransport = LLMClient & {
  chat: (messages: ChatMessage[], model: string, opts?: ChatOptions) => Promise<string>;
  generateImage?: (request: ImageRequest) => Promise<ImageResult>;
};

function withSkills(messages: ChatMessage[], skills: readonly AgentSkill[]): ChatMessage[] {
  if (!skills.length) return messages;
  const skillContext = skills.map((skill) => `【Skill: ${skill.id}】\n${skill.systemPrompt}`).join("\n\n");
  const system = messages.find((message) => message.role === "system");
  if (!system) return [{ role: "system", content: skillContext }, ...messages];
  return messages.map((message) => message === system
    ? { ...message, content: `${skillContext}\n\n${message.content}` }
    : message);
}

class Gateway implements AgentGateway {
  readonly kind: "direct" | "agent";
  readonly skills: readonly AgentSkill[];
  readonly tools: readonly AgentTool[];

  constructor(private readonly transport: ChatTransport, kind: "direct" | "agent", options: AgentGatewayOptions = {}) {
    this.kind = kind;
    this.skills = options.skills ?? [];
    this.tools = options.tools ?? [];
  }

  chat(messages: ChatMessage[], model: string, opts: ChatOptions = {}): Promise<string> {
    return this.transport.chat(withSkills(messages, this.skills), model, opts);
  }

  chatJson<T>(messages: ChatMessage[], model: string, opts: ChatOptions = {}): Promise<T> {
    return this.transport.chatJson<T>(withSkills(messages, this.skills), model, opts);
  }

  generateImage(request: ImageRequest): Promise<ImageResult> {
    if (typeof this.transport.generateImage !== "function") throw new Error("当前 Agent 不支持图像生成");
    return this.transport.generateImage(request);
  }

  async invokeTool(name: string, input: unknown): Promise<unknown> {
    const tool = this.tools.find((candidate) => candidate.name === name);
    if (!tool) throw new Error(`Agent 工具不存在：${name}`);
    return tool.execute(input);
  }
}

/** 兼容 adapter：保留供应商 transport，但所有调用经过统一 skill/tool 网关。 */
export function createDirectAgentGateway(transport: ChatTransport, options?: AgentGatewayOptions): AgentGateway {
  return new Gateway(transport, "direct", options);
}

/** Agent adapter：为远端 Pi/MCP 替换预留；当前以同一 transport 执行并暴露工具注册表。 */
export function createToolAgentGateway(transport: ChatTransport, options?: AgentGatewayOptions): AgentGateway {
  return new Gateway(transport, "agent", options);
}
