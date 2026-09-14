import sqlite3

from flask import current_app, g


def get_connection(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def get_db() -> sqlite3.Connection:
    if "db_conn" not in g:
        g.db_conn = get_connection(current_app.config["DB_PATH"])
    return g.db_conn


def close_db(exception=None) -> None:
    conn = g.pop("db_conn", None)
    if conn is not None:
        conn.close()


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN ('user', 'admin'))
        );

        CREATE TABLE IF NOT EXISTS saves (
            user_id INTEGER PRIMARY KEY REFERENCES users(id),
            dice_state TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
    )
    conn.commit()


def seed_admin(conn: sqlite3.Connection, username: str, password_hash: str) -> None:
    if get_user_by_username(conn, username) is None:
        conn.execute(
            "INSERT INTO users (username, password_hash, role) VALUES (?, ?, 'admin')",
            (username, password_hash),
        )


def create_user(conn: sqlite3.Connection, username: str, password_hash: str, role: str = "user") -> int:
    cursor = conn.execute(
        "INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)",
        (username, password_hash, role),
    )
    conn.commit()
    return cursor.lastrowid


def get_user_by_username(conn: sqlite3.Connection, username: str):
    return conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()


def get_user_by_id(conn: sqlite3.Connection, user_id: int):
    return conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()


def save_game_state(conn: sqlite3.Connection, user_id: int, dice_state_json: str, updated_at: str) -> None:
    conn.execute(
        """
        INSERT INTO saves (user_id, dice_state, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET dice_state = excluded.dice_state, updated_at = excluded.updated_at
        """,
        (user_id, dice_state_json, updated_at),
    )
    conn.commit()


def load_game_state(conn: sqlite3.Connection, user_id: int):
    row = conn.execute("SELECT dice_state FROM saves WHERE user_id = ?", (user_id,)).fetchone()
    return row["dice_state"] if row else None
