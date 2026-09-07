// 生成 1024x1024 应用图标 PNG（无第三方依赖：手写 PNG 编码）。
// 输出 src-tauri/icon-source.png，随后用 `tauri icon` 派生各尺寸。
import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";

const S = 1024;
const rows = [];
for (let y = 0; y < S; y++) {
  const row = Buffer.alloc(1 + S * 4);
  row[0] = 0; // filter none
  for (let x = 0; x < S; x++) {
    // 圆角深色底 + 金色"书页"形
    const cx = x - S / 2, cy = y - S / 2;
    const r = Math.hypot(cx, cy);
    let rr = 255, g = 255, b = 255, a = 0;
    if (r < S * 0.47) {
      a = 255;
      if (r > S * 0.44) { rr = 30; g = 32; b = 38; }              // 边缘
      else if (Math.abs(cx) < S * 0.035 && cy < S * 0.28 && cy > -S * 0.3) { rr = 30; g = 32; b = 38; } // 书脊
      else if (cy < S * 0.3 && cy > -S * 0.34 && Math.abs(cx) < S * 0.3) {
        const page = 1 - Math.abs(cx) / (S * 0.3);
        rr = Math.round(217 - 30 * page); g = Math.round(164 - 40 * page); b = 65; // 金色书页
      } else { rr = 30; g = 32; b = 38; }
    }
    const o = 1 + x * 4;
    row[o] = rr; row[o + 1] = g; row[o + 2] = b; row[o + 3] = a;
  }
  rows.push(row);
}
const raw = Buffer.concat(rows);

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crcTable = [];
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcTable[n] = c >>> 0; }
  let crc = 0xffffffff;
  for (const byte of td) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  const crcBuf = Buffer.alloc(4); crcBuf.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([len, td, crcBuf]);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(S, 0); ihdr.writeUInt32BE(S, 4);
ihdr[8] = 8; ihdr[9] = 6; // 8-bit RGBA
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", deflateSync(raw)),
  chunk("IEND", Buffer.alloc(0)),
]);
writeFileSync(new URL("../src-tauri/icon-source.png", import.meta.url), png);
console.log("icon-source.png 已生成");
