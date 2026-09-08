// 移动端路由（局部状态，不加路由库；与桌面 store.view 解耦）

export type MobileWorkTab = "reader" | "repair" | "entities" | "illustrations";

export type MobileRoute =
  | { name: "library" }
  | { name: "tasks" }
  | { name: "settings" }
  | { name: "import" }
  | { name: "work"; workId: string; tab: MobileWorkTab };

export type MobileNavigate = (route: MobileRoute) => void;
