#!/usr/bin/env node
// 生成一本"脏"样本网文 TXT，用于测试导入与修复：
// 章标题混用多种格式、含广告行、乱码字符与常见错字。
import { writeFileSync } from "node:fs";

const SENT = [
  "山风掠过檐角，铜铃轻响，惊起一树寒鸦。",
  "他握紧掌中残卷，指尖被纸页边缘割出一道细痕，血珠渗出来，他却浑然不觉。",
  "远处传来更夫的梆子声，三长两短，是青石镇遇袭的暗号。",
  "老者眯起眼睛，浑浊的瞳孔深处掠过一丝精光：「你可想好了，此路一去，再无回头。」",
  "少年沉默片刻，将斗笠压得更低，一步踏进了漫天风雪里。",
  "客栈的灯火在夜色中明明灭灭，像一头困兽的呼吸。",
  "她转身时裙裾扬起，腰间玉佩撞在桌角，发出一声几不可闻的脆响。",
  "雨下了整整七日，护城河的水涨过了警戒的红线，官府的告示被泡成一团墨渍。",
  "剑未出鞘，杀意已至。巷口的三个人影同时后退了半步。",
  "「这世上没有白喝的酒，」掌柜的擦着杯子头也不抬，「也没有白救的人。」",
];
const TITLES = [
  (n) => `第${n}章 夜行`,
  (n) => `CHAPTER ${n} The Night Road`,
  (n) => `${n}、旧约`,
  (n) => `第${n}回 风雪不归人`,
];
const ADS = ["本书来自www.biquge.example.com", "请记住本站最新章节地址 1234.example.com", "笔趣阁高速首发，去广告请支持正版。"];
const GARBAGE = ["ﬀвД", "φω✓", "ﬅ◆"];

let out = "《雪夜行》\n作者：演示脚本\n\n";
let seed = 42;
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
for (let ch = 1; ch <= 8; ch++) {
  out += `\n${TITLES[ch % TITLES.length](ch)}\n\n`;
  const paras = 6 + Math.floor(rand() * 5);
  for (let p = 0; p < paras; p++) {
    let para = Array.from({ length: 3 + Math.floor(rand() * 5) }, () => SENT[Math.floor(rand() * SENT.length)]).join("");
    if (rand() < 0.25) para += ADS[Math.floor(rand() * ADS.length)];
    if (rand() < 0.3) para = para.slice(0, Math.floor(para.length / 2)) + GARBAGE[Math.floor(rand() * GARBAGE.length)] + para.slice(Math.floor(para.length / 2));
    if (rand() < 0.2) para = para.replace("他们", "他门");
    out += para + "\n\n";
  }
}
writeFileSync(new URL("../samples/sample-novel.txt", import.meta.url), out);
console.log("已生成 samples/sample-novel.txt");
