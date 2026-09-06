// Marginal 桌面壳：web 前端的薄壳（spec §2 平台壳层）。
// 桌面特有能力（Rust commands：文件读写、长任务守护、本地代理）在此挂载；
// 当前为未编译验证的脚手架（本机无 Rust 工具链）。

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
