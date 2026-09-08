import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.spec.ts",
  fullyParallel: true,
  retries: 1,
  reporter: "list",
  timeout: 45_000,
  use: {
    channel: "chrome",
    headless: true,
    baseURL: "http://127.0.0.1:5199",
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    hasTouch: true,
    isMobile: true,
    locale: "zh-CN",
  },
  webServer: {
    command: "pnpm --filter @marginal/app dev",
    url: "http://127.0.0.1:5199/sample-novel.txt",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
  projects: [
    {
      name: "mobile-h5-idb",
      use: {
        ...devices["Pixel 7"],
        viewport: { width: 390, height: 844 },
      },
    },
  ],
});
