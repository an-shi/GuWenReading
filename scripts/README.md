# 古文阅读器开发辅助脚本（PowerShell）

Run from repository root. Requires Python 3.12 virtualenv at .venv and Node.js.

## Backend

```powershell
$env:GUWEN_DATA_DIR = "$env:APPDATA\古文阅读器-dev"
.\.venv\Scripts\python.exe -m app
```

API: http://127.0.0.1:8765/docs

## Desktop frontend

```powershell
cd desktop\frontend
npm install
npm run dev
```

Open http://127.0.0.1:1420

## Tests

```powershell
cd backend
..\.venv\Scripts\python.exe -m pytest -q
```

## Backup / restore

Create a backup from the desktop Settings page or `POST /api/v1/system/backup`.

```powershell
.\.venv\Scripts\python.exe scripts/restore_backup.py C:\backups\古文阅读器备份-....zip
```

Stop the backend before restoring. The script archives current data under `data/backups/pre-restore-*` first.

## Build backend sidecar

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_backend.ps1
```

## Tauri

Rust/Cargo is required. The native shell was authored but is not built in the
development environment used to create this snapshot (Cargo was unavailable).

```powershell
cd desktop\src-tauri
npm --prefix ..\frontend run build
cargo tauri build
```
