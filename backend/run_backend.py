"""古文阅读器 Python 后端的 PyInstaller 冻结入口。"""

from __future__ import annotations

import os

import uvicorn

from app.core.config import Settings
from app.main import create_app


def main() -> None:
    settings = Settings()
    application = create_app(settings)
    host = os.environ.get("GUWEN_HOST", settings.host)
    port = int(os.environ.get("GUWEN_PORT", str(settings.port)))
    uvicorn.run(application, host=host, port=port, log_level=settings.log_level.lower())


if __name__ == "__main__":
    main()
