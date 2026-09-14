import sqlite3

import pytest

from backend import db


@pytest.fixture
def conn(tmp_path):
    connection = sqlite3.connect(str(tmp_path / "test.db"))
    connection.row_factory = sqlite3.Row
    db.init_db(connection)
    yield connection
    connection.close()


def test_seed_admin_creates_admin_role_user(conn):
    db.seed_admin(conn, "admin", "hashed-pw")
    conn.commit()

    user = db.get_user_by_username(conn, "admin")
    assert user is not None
    assert user["role"] == "admin"


def test_seed_admin_is_idempotent(conn):
    db.seed_admin(conn, "admin", "hashed-pw")
    db.seed_admin(conn, "admin", "hashed-pw")
    conn.commit()

    count = conn.execute("SELECT COUNT(*) AS c FROM users WHERE username = 'admin'").fetchone()["c"]
    assert count == 1


def test_create_user_returns_id_and_defaults_to_user_role(conn):
    user_id = db.create_user(conn, "alice", "hashed-pw")
    user = db.get_user_by_id(conn, user_id)
    assert user["username"] == "alice"
    assert user["role"] == "user"


def test_create_user_duplicate_username_raises(conn):
    db.create_user(conn, "alice", "hashed-pw")
    with pytest.raises(sqlite3.IntegrityError):
        db.create_user(conn, "alice", "other-hash")


def test_save_and_load_game_state_roundtrip(conn):
    user_id = db.create_user(conn, "alice", "hashed-pw")
    db.save_game_state(conn, user_id, '{"die_1": {"tray": "red"}}', "2026-09-14T00:00:00")

    loaded = db.load_game_state(conn, user_id)
    assert loaded == '{"die_1": {"tray": "red"}}'


def test_save_game_state_overwrites_previous_save(conn):
    user_id = db.create_user(conn, "alice", "hashed-pw")
    db.save_game_state(conn, user_id, '{"a": 1}', "2026-09-14T00:00:00")
    db.save_game_state(conn, user_id, '{"a": 2}', "2026-09-14T01:00:00")

    assert db.load_game_state(conn, user_id) == '{"a": 2}'


def test_load_game_state_returns_none_when_no_save(conn):
    user_id = db.create_user(conn, "alice", "hashed-pw")
    assert db.load_game_state(conn, user_id) is None
