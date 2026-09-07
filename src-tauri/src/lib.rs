// Marginal 桌面壳：web 前端的薄壳（spec §2 平台壳层）。
// 桌面原生 SQLite 经 tauri-plugin-sql 提供（spec §2/research/001：
// 桌面 WKWebView 无 OPFS，结构化存储走 Rust 侧 rusqlite）。

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(
            tauri_plugin_sql::Builder::new()
                .add_migrations("sqlite:marginal.db", vec![])
                .build(),
        )
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
