import type { Page } from "@playwright/test";

/** 以移动端 + IDB 引擎打开首页，绕过可能的 OPFS 首屏启动不稳定 */
export async function openApp(page: Page) {
  await page.goto("/?ui=mobile&engine=indexeddb");
  await page.waitForSelector("h1", { timeout: 15_000 });
}

export async function importSampleBook(page: Page) {
  await page.getByText("导入小说").first().click();
  await page.getByRole("button", { name: "使用示例书" }).click();
  await page.waitForSelector("input[aria-label='书稿名称']", { state: "visible", timeout: 10_000 });
  const title = await page.inputValue("input[aria-label='书稿名称']");
  return { title };
}

/** 阅读器工具栏若隐藏则点击中央唤起（沉浸模式下工具栏会自动收起，调用后短暂可见） */
export async function showReaderChrome(page: import("@playwright/test").Page) {
  const bottom = page.locator(".m-reader-bottom");
  const top = page.locator(".m-reader-top");
  if (!(await bottom.isVisible()) || !(await top.isVisible())) {
    await page.locator(".m-reader-tap-toggle").click();
  }
  await bottom.waitFor({ state: "visible", timeout: 5000 });
  await top.waitFor({ state: "visible", timeout: 5000 });
}

/** 刷新后从书架重新打开第一本书进入阅读器 */
export async function openReaderFromLibrary(page: import("@playwright/test").Page) {
  await page.waitForSelector(".m-book-card", { timeout: 15_000 });
  await page.locator(".m-book-card").first().click();
  await page.waitForSelector(".m-reader-title", { timeout: 15_000 });
}

export function waitForToast(page: Page, includes: string) {
  return page.getByRole("status").filter({ hasText: includes }).waitFor({ timeout: 15_000 });
}
