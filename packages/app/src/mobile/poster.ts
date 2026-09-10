export interface ParagraphPosterInput {
  title: string;
  chapterTitle: string;
  text: string;
}

/** 海报正文按阅读节奏断行；中文按字宽、ASCII 按半字宽估算。 */
export function wrapPosterText(text: string, maxUnits = 20, maxLines = 18): string[] {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (!normalized) return [];
  const lines: string[] = [];
  let truncated = false;
  let line = "";
  let units = 0;
  for (const character of normalized) {
    const width = /[\u0000-\u00ff]/.test(character) ? 0.55 : 1;
    if (line && units + width > maxUnits) {
      lines.push(line.trimEnd());
      line = "";
      units = 0;
      if (lines.length === maxLines) { truncated = true; break; }
    }
    line += character;
    units += width;
  }
  if (line && lines.length < maxLines) lines.push(line.trimEnd());
  if (truncated) {
    lines[maxLines - 1] = `${lines[maxLines - 1].replace(/[，。！？；：,.!?;:]?$/, "")}…`;
  }
  return lines;
}

export function renderParagraphPoster(canvas: HTMLCanvasElement, input: ParagraphPosterInput): void {
  const width = 900;
  const lines = wrapPosterText(input.text);
  const height = Math.max(1200, 500 + lines.length * 62);
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("当前浏览器不支持海报绘制");

  const background = context.createLinearGradient(0, 0, width, height);
  background.addColorStop(0, "#f7f0df");
  background.addColorStop(1, "#e9dcc2");
  context.fillStyle = background;
  context.fillRect(0, 0, width, height);

  context.strokeStyle = "rgba(158,108,48,.28)";
  context.lineWidth = 2;
  context.beginPath();
  context.arc(790, 105, 155, 0, Math.PI * 2);
  context.stroke();
  context.beginPath();
  context.arc(790, 105, 110, 0, Math.PI * 2);
  context.stroke();

  context.fillStyle = "#9d6b2f";
  context.font = "700 24px system-ui, sans-serif";
  context.letterSpacing = "3px";
  context.fillText("MARGINAL READING", 78, 92);

  context.fillStyle = "#342e27";
  context.font = '700 54px "Songti SC", "STSong", serif';
  context.fillText(`《${input.title.slice(0, 18)}》`, 78, 185);
  context.fillStyle = "#8b765c";
  context.font = '28px "Songti SC", "STSong", serif';
  context.fillText(input.chapterTitle.slice(0, 26), 82, 238);

  context.fillStyle = "#b07a37";
  context.fillRect(80, 295, 54, 5);
  context.fillStyle = "#3e3830";
  context.font = '36px "Songti SC", "STSong", serif';
  let y = 380;
  for (const line of lines) {
    context.fillText(line, 80, y);
    y += 62;
  }

  const footerY = height - 120;
  context.strokeStyle = "rgba(95,76,50,.22)";
  context.beginPath();
  context.moveTo(80, footerY - 45);
  context.lineTo(width - 80, footerY - 45);
  context.stroke();
  context.fillStyle = "#8a7a64";
  context.font = "22px system-ui, sans-serif";
  context.fillText("Marginal · 让每一段值得被记住", 80, footerY);
}
