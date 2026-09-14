import os

from flask import Flask

from . import db
from .auth import auth_bp, hash_password

DEFAULT_ADMIN_USERNAME = "admin"
DEFAULT_ADMIN_PASSWORD = "password1"  # intentionally weak — see spec Auth Model


def create_app(db_path: str = "dicegame.db", secret_key: str | None = None) -> Flask:
    app = Flask(__name__)
    app.config["DB_PATH"] = db_path
    app.config["SECRET_KEY"] = secret_key or os.environ.get("SECRET_KEY", "dev-secret-change-me")
    app.config["TOKEN_MAX_AGE"] = 60 * 60 * 12  # 12 hours

    with app.app_context():
        conn = db.get_db()
        db.init_db(conn)
        db.seed_admin(conn, DEFAULT_ADMIN_USERNAME, hash_password(DEFAULT_ADMIN_PASSWORD))
        conn.commit()

    app.register_blueprint(auth_bp)
    app.teardown_appcontext(db.close_db)

    return app
