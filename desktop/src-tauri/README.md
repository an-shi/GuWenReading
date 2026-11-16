# Tauri Shell

古文阅读器 Windows 桌面外壳。

- `tauri.conf.json` — window, CSP, NSIS bundling, sidecar resources.
- `src/lib.rs` — starts `resources/backend/guwenreading-backend.exe` when present and stops it on window close.
- `capabilities/default.json` — core-only permissions.
- `icons/` — generated seal icon set.

The shell has not been compiled in this environment because Rust/Cargo is not installed. See `docs/BUILD.md`.
