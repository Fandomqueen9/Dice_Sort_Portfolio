import os

from backend.app import create_app

app = create_app(
    db_path=os.environ.get("DICEGAME_DB_PATH", "/var/lib/dicegame/dicegame.db"),
)
