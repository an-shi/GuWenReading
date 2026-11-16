//! 古文阅读器 Tauri 外壳。
//!
//! In production the Python backend is packaged by PyInstaller and placed at
//! `resources/backend/guwenreading-backend.exe`. The shell starts it on 127.0.0.1
//! and terminates it when the main window closes. During development the
//! backend can be started separately, and the shell will simply connect to it.

use std::process::{Child, Command};
use std::sync::Mutex;

use tauri::{Manager, WindowEvent};

struct BackendProcess(Mutex<Option<Child>>);

fn backend_binary() -> &'static str {
    if cfg!(windows) {
        "guwenreading-backend.exe"
    } else {
        "guwenreading-backend"
    }
}

fn spawn_backend(app: &tauri::AppHandle) -> Option<Child> {
    let resource_dir = app.path().resource_dir().ok()?;
    let binary_name = backend_binary();
    let candidates = [
        resource_dir.join("backend").join("guwenreading-backend").join(binary_name),
        resource_dir.join("backend").join(binary_name),
        resource_dir.join("resources").join("backend").join("guwenreading-backend").join(binary_name),
        resource_dir.join("resources").join("backend").join(binary_name),
    ];
    let binary = candidates.iter().find(|path| path.exists())?;
    Command::new(binary)
        .env("GUWEN_MODE", "embedded")
        .env("GUWEN_HOST", "127.0.0.1")
        .env("GUWEN_PORT", "8765")
        .spawn()
        .ok()
}

pub fn run() {
    tauri::Builder::default()
        .manage(BackendProcess(Mutex::new(None)))
        .setup(|app| {
            let child = spawn_backend(app.handle());
            if let Some(state) = app.try_state::<BackendProcess>() {
                *state.0.lock().expect("backend mutex poisoned") = child;
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { .. } = event {
                if let Some(state) = window.try_state::<BackendProcess>() {
                    if let Some(mut child) = state.0.lock().expect("backend mutex poisoned").take() {
                        let _ = child.kill();
                        let _ = child.wait();
                    }
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("运行古文阅读器时出错");
}
