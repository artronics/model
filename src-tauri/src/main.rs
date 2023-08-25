// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;

#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! value is {}", name, my_add(10, 12))
}

#[link(name = "backend", kind = "static")]
extern "C" {
    fn add(a: usize, b: usize) -> usize;
}

fn my_add(a: usize, b: usize) -> usize {
    unsafe {
        return add(a, b);
    }
}

#[derive(Clone, serde::Serialize)]
struct Payload {
    message: String,
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let window = app.get_window("main").unwrap();
            #[cfg(debug_assertions)] // only include this code on debug builds
            {
                window.open_devtools();
                window.close_devtools();
            }
            // listen to the `event-name` (emitted on the `main` window)
            let id = window.listen("click", |event| {
                println!("got window event-name with payload {:?}", event.payload());
            });
            // unlisten to the event using the `id` returned on the `listen` function
            // an `once` API is also exposed on the `Window` struct

            // emit the `event-name` event to the `main` window
            window.emit("click", Payload { message: "Tauri is awesome!".into() }).unwrap();
            // window.unlisten(id);

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![greet])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
