// UUIDv7：时间有序、无自增身份依赖（spec §3 同步留路）
export function uuidv7(): string {
  const ts = Date.now();
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  const t = BigInt(ts);
  b[0] = Number((t >> 56n) & 0xffn);
  b[1] = Number((t >> 48n) & 0xffn);
  b[2] = Number((t >> 40n) & 0xffn);
  b[3] = Number((t >> 32n) & 0xffn);
  b[4] = Number((t >> 24n) & 0xffn);
  b[5] = Number((t >> 16n) & 0xffn);
  b[6] = (b[6] & 0x0f) | 0x70;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export async function sha256Hex(data: ArrayBuffer | Uint8Array): Promise<string> {
  const buf = data instanceof Uint8Array ? data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) : data;
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
