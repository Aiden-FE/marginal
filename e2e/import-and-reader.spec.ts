import { test, expect } from "@playwright/test";
import { openApp, importSampleBook, waitForToast, showReaderChrome, openReaderFromLibrary } from "./utils";

test.describe("移动端全流程（demo provider，IndexedDB）", () => {
  test("删除书稿后从最近书稿永久移除", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await waitForToast(page, "已导入");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });
    await showReaderChrome(page);
    await page.getByRole("button", { name: "返回书架" }).click();
    await expect(page.locator(".m-book-card")).toHaveCount(1);

    await page.getByRole("button", { name: /^管理《/ }).click();
    await page.getByRole("button", { name: "删除书稿" }).click();
    await page.getByRole("button", { name: "确认删除" }).click();
    await expect(page.locator(".m-book-card")).toHaveCount(0, { timeout: 10_000 });
    await expect(page.getByText("书架还是空的")).toBeVisible();

    // 重新加载后仍然不存在，防止仅从内存列表临时移除
    await page.reload();
    await page.waitForSelector("h1", { timeout: 15_000 });
    await expect(page.locator(".m-book-card")).toHaveCount(0);
  });

  test("导入 Loading 与移动布局：解析/入库有过渡且按钮不遮挡", async ({ page }) => {
    await openApp(page);
    const heroCopy = page.locator(".m-hero-card p");
    const heroButton = page.locator(".m-hero-action");
    const [copyBox, buttonBox] = await Promise.all([heroCopy.boundingBox(), heroButton.boundingBox()]);
    expect(copyBox && buttonBox && copyBox.y + copyBox.height <= buttonBox.y).toBe(true);

    await page.getByText("导入小说").first().click();
    await page.route("**/sample-novel.txt", async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 600));
      await route.continue();
    });
    await page.getByRole("button", { name: "使用示例书" }).click();
    await expect(page.getByRole("status")).toContainText("正在加载示例书");
    await page.waitForSelector("input[aria-label='书稿名称']", { state: "visible", timeout: 10_000 });

    const aiButton = page.getByRole("button", { name: "AI 智能切分" });
    const summary = page.locator(".m-preview-summary");
    const [aiBox, summaryBox] = await Promise.all([aiButton.boundingBox(), summary.boundingBox()]);
    expect(aiBox && summaryBox && aiBox.width >= summaryBox.width - 32).toBe(true);

    // 延迟底层写入，稳定验证确认导入过渡遮罩
    await page.evaluate(() => {
      const repo = window.__store!.repo;
      const original = repo.putWork.bind(repo);
      repo.putWork = async (...args: Parameters<typeof repo.putWork>) => {
        await new Promise((resolve) => setTimeout(resolve, 700));
        return original(...args);
      };
    });
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await expect(page.getByRole("status")).toContainText("正在写入章节与创建书籍");
    await waitForToast(page, "已导入");
  });

  test("示例书导入 → 章节并入/拆分 → 确认后章节数正确", async ({ page }) => {
    await openApp(page);
    const initialChapters = await (async () => {
      const { title } = await importSampleBook(page);
      // 初始章节数
      const initial = await page.locator(".m-chapter-card").count();
      // 并入第 2 章
      const buttons = page.getByRole("button", { name: "并入上一章" });
      const count = await buttons.count();
      expect(count).toBeGreaterThan(2);
      await buttons.nth(1).click(); // 第 2 章并入第 1 章
      // 拆分第 1 章
      const splitButtons = page.getByRole("button", { name: "拆分" });
      expect(await splitButtons.count()).toBeGreaterThan(1);
      await splitButtons.nth(0).click();
      // 确认拆分按钮
      await page.getByRole("button", { name: "确认拆分" }).click();
      // 章节数：initial - 1(并入) + 1(拆分) = initial
      const finalCount = await page.locator(".m-chapter-card").count();
      expect(finalCount).toBe(initial);
      // 确认导入
      await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
      await waitForToast(page, "已导入");
      return { initial, title };
    })();

    // 进入阅读器
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });

    // 验证阅读器章节数与预览一致（核心回归：切分结果正确回传）
    await showReaderChrome(page);
    await page.getByRole("button", { name: "章节目录" }).click();
    const chapters = page.locator(".m-chapter-row > button:first-child");
    const total = await chapters.count();
    expect(total).toBe(initialChapters.initial);
    await expect(page.locator(".m-reader-title")).toBeVisible();
    // 切到第 2 章
    await chapters.nth(1).click();
    await expect(page.locator(".m-reader-title")).toBeVisible();
    // 字号 / 主题循环：日间 → 护眼 → 夜间
    await showReaderChrome(page);
    await page.getByRole("button", { name: "增大字号" }).click();
    await page.getByRole("button", { name: "护眼" }).click();
    await expect(page.locator(".m-reader.theme-eyecare")).toBeVisible();
    await page.getByRole("button", { name: "夜间" }).click();
    await expect(page.locator(".m-reader.theme-dark")).toBeVisible();
  });

  test("修复建议生成 + 应用 + 实体提取 + 正典 + 定妆照 + 任务页", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await waitForToast(page, "已导入");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });

    // 更多 → 修复
    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: "修复与修订" }).click();
    await expect(page.getByText("章节清洗")).toBeVisible();

    // 生成清洗建议
    await page.getByRole("button", { name: "生成清洗建议" }).click();
    await waitForToast(page, "AI 给出");
    await expect(page.locator(".m-suggestion-card").first()).toBeVisible({ timeout: 15_000 });

    // 接受第一条
    const acceptButtons = page.getByRole("button", { name: "接受" });
    const acceptCount = await acceptButtons.count();
    expect(acceptCount).toBeGreaterThan(0);
    await acceptButtons.nth(0).click();

    // 应用
    await page.getByRole("button", { name: /应用已接受/ }).click();
    await waitForToast(page, "已应用");

    // 实体卡（修复页顶部返回书架，再从书卡菜单进入）
    await page.getByRole("button", { name: "返回书架" }).first().click();
    await page.getByRole("button", { name: /管理《/ }).first().click();
    await page.getByRole("button", { name: "实体卡" }).click();
    await expect(page.getByRole("heading", { name: "实体卡", exact: true })).toBeVisible();

    await page.getByRole("button", { name: "AI 全文提取设定" }).click();
    await waitForToast(page, "提取到");
    await expect(page.locator(".m-entity-card").first()).toBeVisible({ timeout: 15_000 });

    // 打开第一张卡并正典
    await page.locator(".m-entity-card").first().click();
    await expect(page.getByRole("button", { name: "确认正典" })).toBeVisible();
    await page.getByRole("button", { name: "确认正典" }).click();
    await waitForToast(page, "已正典");

    // 生成定妆照
    await page.getByRole("button", { name: "生成定妆照" }).click();
    await waitForToast(page, "定妆照已生成");

    // 底部 → 任务页
    await page.getByRole("button", { name: "关闭" }).click();
    await page.getByRole("button", { name: "返回书架" }).first().click();
    await page.getByRole("button", { name: "任务" }).click();
    await expect(page.getByText("队列概览")).toBeVisible();
    const completed = await page.locator(".m-stats-row strong").first().innerText();
    expect(Number(completed)).toBeGreaterThanOrEqual(1);
  });

  test("阅读位置恢复 + 段落配图锚点落地", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await waitForToast(page, "已导入");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });

    const reader = page.locator(".m-reader-scroll");
    // 首次载章会在 rAF 里把位置归零，等它落定再滚动
    await expect.poll(() => reader.evaluate((element) => element.scrollHeight - element.clientHeight)).toBeGreaterThan(500);
    await page.waitForTimeout(500);
    await reader.evaluate((element) => {
      element.scrollTop = (element.scrollHeight - element.clientHeight) * 0.45;
    });
    await page.waitForTimeout(700);
    const savedRatio = await reader.evaluate(
      (element) => element.scrollTop / Math.max(1, element.scrollHeight - element.clientHeight),
    );
    expect(savedRatio).toBeGreaterThan(0.3);

    await page.reload();
    await openReaderFromLibrary(page);
    await expect.poll(
      () => reader.evaluate(
        (element) => element.scrollTop / Math.max(1, element.scrollHeight - element.clientHeight),
      ),
      { timeout: 10_000 },
    ).toBeGreaterThan(savedRatio - 0.08);

    // 段落操作面板：收藏 → 精彩段落列表 → 再配图
    await page.locator(".m-reader-para").first().click({ position: { x: 10, y: 10 } });
    await page.getByRole("button", { name: /收藏段落/ }).click();
    await waitForToast(page, "已收藏");
    await expect(page.locator(".m-fav-mark").first()).toBeVisible();

    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: /精彩段落/ }).click();
    await expect(page.locator(".m-fav-item")).toHaveCount(1);
    await page.getByRole("button", { name: "关闭" }).click();

    // 章节书签：目录标星 → 书签页 → 跳转
    await showReaderChrome(page);
    await page.getByRole("button", { name: "章节目录" }).click();
    const tocRows = page.locator(".m-chapter-row");
    await tocRows.nth(1).getByRole("button", { name: /^添加书签/ }).click();
    await waitForToast(page, "已书签");
    const secondTitle = (await tocRows.nth(1).locator("button").first().innerText()).replace(/^\s*\d+\s*/, "").trim();
    await page.getByRole("button", { name: "关闭" }).click();

    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: "🔖 书签" }).click();
    await expect(page.locator(".m-fav-item")).toHaveCount(1);
    await page.getByRole("button", { name: "去阅读" }).click();
    await expect(page.locator(".m-reader-title")).toHaveText(secondTitle);

    // 全书搜索：跨章命中 → 点击跳转定位；无结果路径
    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: "全书搜索" }).click();
    await page.getByLabel("搜索关键词").fill("掌柜");
    const hits = page.locator(".m-search-hit");
    await expect(hits.first()).toBeVisible({ timeout: 10_000 });
    expect(await hits.count()).toBeGreaterThanOrEqual(2);
    const firstChapter = (await hits.first().locator(".m-search-chapter").innerText()).replace(/^\s*\d+\.\s*/, "").trim();
    await hits.first().click();
    await expect(page.locator(".m-reader-title")).toHaveText(firstChapter);

    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: "全书搜索" }).click();
    await page.getByLabel("搜索关键词").fill("绝不存在的关键词");
    await expect(page.getByText("未找到匹配内容")).toBeVisible({ timeout: 10_000 });
    await page.getByRole("button", { name: "关闭" }).click();

    await page.locator(".m-reader-para").first().click({ position: { x: 10, y: 10 } });
    await page.getByRole("button", { name: /为段落配图/ }).click();
    await expect(page.getByRole("dialog", { name: "为段落配图" })).toBeVisible();
    await page.getByRole("button", { name: "加入生成队列" }).click();
    await waitForToast(page, "插图已插入锚点");
    await expect(page.locator(".m-anchor-mark").first()).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(".m-reader .illus").first()).toBeVisible({ timeout: 15_000 });
  });

  test("插图页 + 预算编辑 + 设置诊断", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await waitForToast(page, "已导入");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });

    // 插图页（从阅读器菜单进入）
    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: "插图任务" }).click();
    await expect(page.getByText("段落插图")).toBeVisible();

    // 预算上限编辑
    await page.getByRole("button", { name: "增加预算" }).click();
    await page.getByRole("button", { name: "增加预算" }).click();
    await waitForToast(page, "预算上限已设为");

    // 预扫候选
    await page.getByRole("button", { name: "预扫候选段落" }).click();
    await waitForToast(page, "预扫到");
    await expect(page.locator(".m-candidate-item").first()).toBeVisible({ timeout: 10_000 });

    // 入队生成（demo，很快）
    await page.getByRole("button", { name: /入队生成/ }).click();
    await waitForToast(page, "已入队");

    // 设置页（从插图页返回书架再点我的）
    await page.getByRole("button", { name: "返回书架" }).first().click();
    await page.getByRole("button", { name: "我的" }).click();
    await expect(page.getByText("存储引擎")).toBeVisible();
    const engine = page.getByText("indexeddb");
    await expect(engine.first()).toBeVisible();
    await expect(page.getByLabel("章节切分执行模式")).toHaveValue("agent");

    // 诊断演示供应商
    await page.getByRole("button", { name: "连通性诊断" }).first().click();
    await waitForToast(page, "浏览器可直连");
  });

  test("AI 智能切分：导入预览经 Agent 网关重切（demo 供应商）", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    // 设置里存在「章节切分」任务行，且默认 Agent 模式
    // （设置检查放在导入前会离开流程，这里直接在预览页触发 AI 切分）
    await page.getByRole("button", { name: /AI 智能切分/ }).click();
    await waitForToast(page, "AI 切分完成：8 章");
    await expect(page.locator(".m-chapter-card")).toHaveCount(8, { timeout: 10_000 });
    // AI 结果仍需人工确认后入库
    await page.getByRole("button", { name: /确认导入 8 章/ }).click();
    await waitForToast(page, "已导入 8 章");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });

    // 修复页提供本地/AI 两种重切入口
    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: "修复与修订" }).click();
    await expect(page.getByRole("button", { name: "本地重新切分" })).toBeVisible();
    await expect(page.getByRole("button", { name: "AI 智能切分" })).toBeVisible();
  });

  test("沉浸阅读：默认沉浸、点按唤出、自动收起、主题色融合", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await waitForToast(page, "已导入");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });

    // 进入即沉浸：应用壳层导航不在，工具栏收起
    await expect(page.locator(".m-tabs")).toHaveCount(0);
    await expect(page.locator(".m-reader-bottom")).toBeHidden();

    // 点按中央唤出工具栏
    await page.locator(".m-reader-tap-toggle").click();
    await expect(page.locator(".m-reader-bottom")).toBeVisible();
    await expect(page.locator(".m-reader-top")).toBeVisible();

    // 护眼/夜间切换后浏览器主题色与阅读背景融合
    await page.getByRole("button", { name: "护眼" }).click();
    await expect(page.locator("meta[name='theme-color']")).toHaveAttribute("content", "#cfe3d2");
    await expect(page.locator(".m-reader.theme-eyecare")).toBeVisible();
    await page.getByRole("button", { name: "夜间" }).click();
    await expect(page.locator("meta[name='theme-color']")).toHaveAttribute("content", "#171816");
    await expect(page.locator(".m-reader.theme-dark")).toBeVisible();

    // 8 秒无操作自动收起
    await page.waitForTimeout(8800);
    await expect(page.locator(".m-reader-bottom")).toBeHidden();

    // 菜单里可关闭沉浸模式，工具栏恢复常显
    await page.locator(".m-reader-tap-toggle").click();
    await page.getByRole("button", { name: "更多操作" }).click();
    const immersiveToggle = page.getByRole("button", { name: "退出沉浸阅读" });
    await expect(immersiveToggle).toHaveAttribute("aria-pressed", "true");
    await immersiveToggle.click();
    await expect(page.locator(".m-reader-bottom")).toBeVisible();
    await page.waitForTimeout(4500);
    await expect(page.locator(".m-reader-bottom")).toBeVisible();
  });

  test("自动阅读：等速滚动、速度设置、章末停留后停止", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await waitForToast(page, "已导入");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });
    await expect.poll(async () => page.locator(".m-reader-scroll").evaluate((el) => el.scrollHeight)).toBeGreaterThan(500);

    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: /开始自动阅读/ }).click();
    const scroll = page.locator(".m-reader-scroll");
    const before = await scroll.evaluate((el) => el.scrollTop);
    await page.waitForTimeout(1800);
    const after = await scroll.evaluate((el) => el.scrollTop);
    expect(after).toBeGreaterThan(before);

    // 速度设置面板可调节并停止
    await showReaderChrome(page);
    await page.getByRole("button", { name: "更多操作" }).click();
    await page.getByRole("button", { name: /自动阅读速度/ }).click();
    await expect(page.getByText("像素/秒")).toBeVisible();
    await page.getByRole("button", { name: "提高自动阅读速度" }).click();
    await page.getByRole("button", { name: "停止自动阅读" }).click();
    const paused = await scroll.evaluate((el) => el.scrollTop);
    await page.waitForTimeout(1200);
    expect(await scroll.evaluate((el) => el.scrollTop)).toBe(paused);
  });

  test("段落海报：点按段落生成分享海报", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await waitForToast(page, "已导入");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });

    await page.locator(".m-reader-para").first().click({ position: { x: 10, y: 10 } });
    await page.getByRole("button", { name: "制作分享海报" }).click();
    const dialog = page.getByRole("dialog", { name: "分享海报" });
    await expect(dialog).toBeVisible();
    const canvas = dialog.locator("canvas.m-poster-canvas");
    await expect(canvas).toBeVisible();
    expect(await canvas.evaluate((el) => (el as HTMLCanvasElement).width)).toBeGreaterThan(0);
    await expect(page.getByRole("button", { name: "分享或保存图片" })).toBeVisible();
    await page.getByRole("button", { name: "关闭" }).click();
  });

  test("书架分组筛选与已读完标记", async ({ page }) => {
    await openApp(page);
    await importSampleBook(page);
    await page.getByRole("button", { name: /确认导入 .* 章/ }).click();
    await waitForToast(page, "已导入");
    await expect(page.locator(".m-reader-title")).toBeVisible({ timeout: 10_000 });

    // 跳到最后一章并滚到底部，制造"读完"状态
    await showReaderChrome(page);
    await page.getByRole("button", { name: "章节目录" }).click();
    await page.locator(".m-chapter-row > button:first-child").last().click();
    const scroll = page.locator(".m-reader-scroll");
    await expect(page.locator(".m-reader-loading")).toHaveCount(0);
    await expect.poll(async () => scroll.evaluate((el) => el.scrollHeight - el.clientHeight)).toBeGreaterThan(100);
    await page.waitForTimeout(500); // 等待切章恢复位置的双 rAF 完成
    await scroll.evaluate((el) => { el.scrollTop = el.scrollHeight; });
    await page.waitForTimeout(900);

    // 回书架：显示已读完徽章
    await showReaderChrome(page);
    await page.getByRole("button", { name: "返回书架" }).click();
    await expect(page.locator(".m-book-card .m-book-done")).toHaveText("已读完", { timeout: 10_000 });
    await expect(page.getByText("已读完").first()).toBeVisible();

    // 设置分组并筛选
    await page.getByRole("button", { name: /^管理《/ }).click();
    await page.getByRole("button", { name: "设置分组" }).click();
    await page.getByLabel("分组名称").fill("武侠");
    await page.getByRole("button", { name: "保存分组" }).click();
    await waitForToast(page, "加入「武侠」");
    await expect(page.getByRole("button", { name: /武侠 · 1/ })).toBeVisible();
    await page.getByRole("button", { name: /武侠 · 1/ }).click();
    await expect(page.locator(".m-book-card")).toHaveCount(1);
    await page.getByRole("button", { name: "全部", exact: true }).click();
    await expect(page.locator(".m-book-card")).toHaveCount(1);
  });
});
