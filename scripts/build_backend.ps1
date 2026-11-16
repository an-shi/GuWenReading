# 将古文阅读器后端构建为独立的 Windows 可执行文件，并放置到
# where Tauri's resource bundler expects it.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File scripts/build_backend.ps1
#
# Requires the project virtualenv at .venv (created with Python 3.12).

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$venvPython = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    throw "Python virtualenv not found at $venvPython. Create it with: py -3.12 -m venv .venv"
}

& $venvPython -m pip install --upgrade pyinstaller
if ($LASTEXITCODE -ne 0) { throw "Failed to install PyInstaller" }

$backend = Join-Path $root "backend"
$dist = Join-Path $root "desktop\src-tauri\resources\backend"
$work = Join-Path $root "build\pyinstaller"
$spec = Join-Path $root "build"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
New-Item -ItemType Directory -Force -Path $work | Out-Null

Push-Location $backend
try {
    & $venvPython -m PyInstaller `
        --noconfirm --clean --onedir `
        --name guwenreading-backend `
        --distpath $dist `
        --workpath $work `
        --specpath $spec `
        --add-data "app/resources;app/resources" `
        --collect-all uvicorn `
        --collect-all ebooklib `
        --collect-all charset_normalizer `
        --hidden-import "aiosqlite" `
        --hidden-import "lxml.etree" `
        run_backend.py
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller build failed" }
} finally {
    Pop-Location
}

Write-Host "Backend built at: $dist\guwenreading-backend\guwenreading-backend.exe"
