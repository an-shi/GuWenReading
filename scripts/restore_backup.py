"""在服务停止时恢复古文阅读器备份。

Usage:
    python scripts/restore_backup.py path/to/古文阅读器备份-....zip

The current data directory is first copied to data/backups/pre-restore-*/ so the
operation is reversible. Do not run this while the backend is running.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from app.core.config import Settings  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="恢复古文阅读器备份")
    parser.add_argument("backup", type=Path)
    parser.add_argument("--data-dir", type=Path, default=None)
    args = parser.parse_args()

    settings = Settings(data_dir=args.data_dir) if args.data_dir else Settings()
    settings.ensure_directories()
    backup = args.backup.expanduser().resolve()
    if not backup.exists():
        print(f"Backup not found: {backup}")
        return 1

    with zipfile.ZipFile(backup) as archive:
        if "database/guwen.db" not in archive.namelist():
            print("Invalid backup: database/guwen.db is missing")
            return 1
        metadata = json.loads(archive.read("backup.json")) if "backup.json" in archive.namelist() else {}
        if metadata.get("format") not in (None, "guwenreading.backup.v1"):
            print("Invalid backup format")
            return 1
        with tempfile.TemporaryDirectory(prefix="guwenreading-restore-") as temp:
            staging = Path(temp)
            archive.extractall(staging)

            stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
            pre = settings.backups_dir / f"pre-restore-{stamp}"
            pre.mkdir(parents=True, exist_ok=True)
            if (settings.data_dir / "guwen.db").exists():
                shutil.copy2(settings.data_dir / "guwen.db", pre / "guwen.db")
            for directory in (settings.books_dir, settings.covers_dir):
                if directory.exists():
                    shutil.copytree(directory, pre / directory.name, dirs_exist_ok=True)

            # Replace the database file and managed assets.
            shutil.copy2(staging / "database" / "guwen.db", settings.data_dir / "guwen.db")
            for name in ("books", "covers"):
                target = settings.data_dir / name
                source = staging / name
                if source.exists():
                    if target.exists():
                        shutil.rmtree(target)
                    shutil.copytree(source, target)

    print(f"Restored {backup.name}")
    print(f"Pre-restore data copied to: {pre}")
    print("Start the backend again to use the restored data.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
