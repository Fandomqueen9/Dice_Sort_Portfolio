# Dice Sorting Game Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the 3D dice-sorting game described in `docs/superpowers/specs/2026-09-14-dice-sorting-game-design.md` — a Flask+SQLite backend (accounts, save/load, admin command channel) and a Godot 4 first-person client that talks to it over HTTP.

**Architecture:** Two independently-runnable pieces. `backend/` is a Flask REST API (auth, save/load, admin dispatch) backed by SQLite, fully TDD'd with pytest since its correctness is what the later security challenge depends on. `client/` is a Godot 4 project (GDScript) — a first-person scene where gameplay logic runs entirely client-side, and the client calls the backend only for login, save/load, and admin commands. The backend must exist and be runnable before any client task, since the client is built and manually verified against a live backend instance throughout.

**Tech Stack:** Python 3 / Flask / SQLite3 / bcrypt / itsdangerous / pytest / gunicorn (backend). Godot 4.3, GDScript, Compatibility renderer (client).

## Global Constraints

- Single-player only — no shared/multiplayer state (spec: Non-Goals).
- No timer or score — win condition is "all sets sorted" only (spec: Non-Goals).
- No feedback/punishment for a die dropped in the wrong tray — silent non-event (spec: Non-Goals, confirmed in design review).
- All logins (any role) return the same generic "invalid credentials" message on failure — no signal distinguishing which role/field was wrong (spec: Auth Model).
- Guests never get server-side persistence — `/game/save` and `/game/load` must reject guest tokens even if the client were bypassed (spec: Data Flow, Error Handling).
- Admin account is seeded with a deliberately weak password (`admin` / `password1`) — this is intentional, not a bug to fix (spec: Auth Model).
- Admin commands are implemented as a dispatch table (`command name → handler`) so more can be added later without restructuring (spec: Data Flow).
- Backend URL is a single config value in the client, not hardcoded in multiple places (spec: Architecture).
- Rendering must target Godot's Compatibility renderer and stay low-poly — player VMs likely lack GPU passthrough (spec: Architecture).
- Dice hover uses a highlight (outline/glow), not a repeated text prompt; a one-time tooltip appears only on the player's very first pickup (design review).

---

## Backend

### Task 1: SQLite data layer

**Files:**
- Create: `backend/__init__.py` (empty)
- Create: `backend/db.py`
- Create: `backend/tests/__init__.py` (empty — needed so pytest's import-mode rootdir walk reaches the project root and `backend` resolves as a package)
- Test: `backend/tests/test_db.py`

**Interfaces:**
- Produces: `db.get_connection(db_path: str) -> sqlite3.Connection`, `db.init_db(conn)`, `db.seed_admin(conn, username, password_hash)`, `db.create_user(conn, username, password_hash, role="user") -> int`, `db.get_user_by_username(conn, username) -> sqlite3.Row | None`, `db.get_user_by_id(conn, user_id) -> sqlite3.Row | None`, `db.save_game_state(conn, user_id, dice_state_json, updated_at)`, `db.load_game_state(conn, user_id) -> str | None`, `db.get_db() -> sqlite3.Connection` (Flask `g`-bound, used by later tasks), `db.close_db(exception=None)`.

- [ ] **Step 1: Write the failing tests**

```python
# backend/tests/test_db.py
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "Portfolio Game" && python -m pytest backend/tests/test_db.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'backend.db'` (or similar, since `backend/db.py` doesn't exist yet).

- [ ] **Step 3: Write the implementation**

```python
# backend/db.py
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "Portfolio Game" && python -m pytest backend/tests/test_db.py -v`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/__init__.py backend/db.py backend/tests/__init__.py backend/tests/test_db.py
git commit -m "feat(backend): add SQLite data layer for users and saves"
```

---

### Task 2: App factory + auth (hashing, tokens, register/login/guest)

**Files:**
- Create: `backend/auth.py`
- Create: `backend/app.py`
- Create: `backend/tests/conftest.py`
- Test: `backend/tests/test_auth.py`

**Interfaces:**
- Consumes: `db.get_db()`, `db.init_db()`, `db.seed_admin()`, `db.create_user()`, `db.get_user_by_username()`, `db.close_db()` (Task 1).
- Produces: `auth.hash_password(password: str) -> str`, `auth.verify_password(password, password_hash) -> bool`, `auth.issue_token(role: str, user_id: int | None) -> str`, `auth.verify_token(token: str) -> dict | None`, `auth.require_auth` (decorator — sets `flask.g.auth = {"role": ..., "user_id": ...}` or 401s), `auth.auth_bp` (Flask blueprint, mounted at `/auth`), `app.create_app(db_path: str = "dicegame.db", secret_key: str | None = None) -> Flask`. `create_app` is what every later backend task's tests import.

- [ ] **Step 1: Write the failing tests**

```python
# backend/tests/conftest.py
import pytest

from backend.app import create_app


@pytest.fixture
def app(tmp_path):
    db_path = str(tmp_path / "test.db")
    return create_app(db_path=db_path, secret_key="test-secret")


@pytest.fixture
def client(app):
    return app.test_client()
```

```python
# backend/tests/test_auth.py
from backend import auth


def test_hash_password_round_trips():
    hashed = auth.hash_password("correcthorsebattery")
    assert auth.verify_password("correcthorsebattery", hashed)
    assert not auth.verify_password("wrong", hashed)


def test_issue_and_verify_token(app):
    with app.app_context():
        token = auth.issue_token("user", 7)
        payload = auth.verify_token(token)
    assert payload == {"role": "user", "user_id": 7}


def test_verify_token_rejects_garbage(app):
    with app.app_context():
        assert auth.verify_token("not-a-real-token") is None


def test_register_creates_user_and_returns_token(client):
    resp = client.post("/auth/register", json={"username": "alice", "password": "correcthorsebattery"})
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["role"] == "user"
    assert body["token"]


def test_register_rejects_duplicate_username(client):
    client.post("/auth/register", json={"username": "alice", "password": "pw123456"})
    resp = client.post("/auth/register", json={"username": "alice", "password": "pw2222222"})
    assert resp.status_code == 400


def test_register_requires_username_and_password(client):
    resp = client.post("/auth/register", json={"username": "", "password": ""})
    assert resp.status_code == 400


def test_login_succeeds_with_correct_password(client):
    client.post("/auth/register", json={"username": "bob", "password": "pw123456"})
    resp = client.post("/auth/login", json={"username": "bob", "password": "pw123456"})
    assert resp.status_code == 200
    assert resp.get_json()["role"] == "user"


def test_login_fails_with_generic_message(client):
    resp = client.post("/auth/login", json={"username": "nobody", "password": "wrong"})
    assert resp.status_code == 401
    assert resp.get_json()["error"] == "invalid credentials"


def test_login_wrong_password_same_generic_message(client):
    client.post("/auth/register", json={"username": "bob", "password": "pw123456"})
    resp = client.post("/auth/login", json={"username": "bob", "password": "wrong"})
    assert resp.status_code == 401
    assert resp.get_json()["error"] == "invalid credentials"


def test_admin_seed_account_can_log_in(client):
    resp = client.post("/auth/login", json={"username": "admin", "password": "password1"})
    assert resp.status_code == 200
    assert resp.get_json()["role"] == "admin"


def test_guest_returns_token_without_creating_a_user_row(client, app):
    resp = client.post("/auth/guest")
    assert resp.status_code == 200
    assert resp.get_json()["role"] == "guest"

    with app.app_context():
        from backend import db
        conn = db.get_db()
        count = conn.execute("SELECT COUNT(*) AS c FROM users").fetchone()["c"]
        assert count == 1  # only the seeded admin — guest never gets a row
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "Portfolio Game" && python -m pytest backend/tests/test_auth.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'backend.auth'`

- [ ] **Step 3: Write the implementation**

```python
# backend/auth.py
import functools

import bcrypt
from flask import Blueprint, current_app, g, jsonify, request
from itsdangerous import BadSignature, URLSafeTimedSerializer

from . import db

auth_bp = Blueprint("auth", __name__, url_prefix="/auth")


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def _serializer() -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(current_app.config["SECRET_KEY"])


def issue_token(role: str, user_id: int | None) -> str:
    return _serializer().dumps({"role": role, "user_id": user_id})


def verify_token(token: str) -> dict | None:
    try:
        return _serializer().loads(token, max_age=current_app.config["TOKEN_MAX_AGE"])
    except BadSignature:
        return None


def require_auth(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        token = header[len("Bearer "):].strip() if header.startswith("Bearer ") else ""
        payload = verify_token(token) if token else None
        if payload is None:
            return jsonify(error="unauthorized"), 401
        g.auth = payload
        return f(*args, **kwargs)

    return wrapper


@auth_bp.post("/register")
def register():
    data = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")
    if not username or not password:
        return jsonify(error="username and password required"), 400

    conn = db.get_db()
    if db.get_user_by_username(conn, username) is not None:
        return jsonify(error="username already taken"), 400

    try:
        user_id = db.create_user(conn, username, hash_password(password), role="user")
    except Exception:
        return jsonify(error="username already taken"), 400

    return jsonify(token=issue_token("user", user_id), role="user")


@auth_bp.post("/login")
def login():
    data = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")

    conn = db.get_db()
    user = db.get_user_by_username(conn, username)
    if user is None or not verify_password(password, user["password_hash"]):
        return jsonify(error="invalid credentials"), 401

    return jsonify(token=issue_token(user["role"], user["id"]), role=user["role"])


@auth_bp.post("/guest")
def guest():
    return jsonify(token=issue_token("guest", None), role="guest")
```

```python
# backend/app.py
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "Portfolio Game" && python -m pytest backend/tests/test_auth.py -v`
Expected: PASS (11 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/auth.py backend/app.py backend/tests/conftest.py backend/tests/test_auth.py
git commit -m "feat(backend): add app factory, password hashing, tokens, and auth endpoints"
```

---

### Task 3: Game save/load endpoints

**Files:**
- Create: `backend/game.py`
- Modify: `backend/app.py` (register `game_bp`)
- Test: `backend/tests/test_game.py`

**Interfaces:**
- Consumes: `auth.require_auth` (Task 2), `db.get_db()`, `db.save_game_state()`, `db.load_game_state()` (Task 1).
- Produces: `game.game_bp` (Flask blueprint, mounted at `/game`), routes `POST /game/save` and `GET /game/load`.

- [ ] **Step 1: Write the failing tests**

```python
# backend/tests/test_game.py
def _register(client, username="alice", password="correcthorsebattery"):
    resp = client.post("/auth/register", json={"username": username, "password": password})
    return resp.get_json()["token"]


def _auth_header(token):
    return {"Authorization": f"Bearer {token}"}


def test_save_then_load_roundtrip(client):
    token = _register(client)
    dice_state = [{"type": "d20", "color": [0.8, 0.1, 0.1], "position": [1, 2, 3], "sorted": True}]

    save_resp = client.post("/game/save", json={"dice_state": dice_state}, headers=_auth_header(token))
    assert save_resp.status_code == 200

    load_resp = client.get("/game/load", headers=_auth_header(token))
    assert load_resp.status_code == 200
    assert load_resp.get_json()["dice_state"] == dice_state


def test_save_overwrites_previous_save(client):
    token = _register(client)
    client.post("/game/save", json={"dice_state": [{"a": 1}]}, headers=_auth_header(token))
    client.post("/game/save", json={"dice_state": [{"a": 2}]}, headers=_auth_header(token))

    resp = client.get("/game/load", headers=_auth_header(token))
    assert resp.get_json()["dice_state"] == [{"a": 2}]


def test_load_with_no_save_returns_null(client):
    token = _register(client, username="freshuser")
    resp = client.get("/game/load", headers=_auth_header(token))
    assert resp.status_code == 200
    assert resp.get_json()["dice_state"] is None


def test_guest_cannot_save(client):
    guest_token = client.post("/auth/guest").get_json()["token"]
    resp = client.post("/game/save", json={"dice_state": []}, headers=_auth_header(guest_token))
    assert resp.status_code == 403


def test_guest_cannot_load(client):
    guest_token = client.post("/auth/guest").get_json()["token"]
    resp = client.get("/game/load", headers=_auth_header(guest_token))
    assert resp.status_code == 403


def test_save_requires_auth(client):
    resp = client.post("/game/save", json={"dice_state": []})
    assert resp.status_code == 401


def test_save_requires_dice_state_field(client):
    token = _register(client)
    resp = client.post("/game/save", json={}, headers=_auth_header(token))
    assert resp.status_code == 400
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "Portfolio Game" && python -m pytest backend/tests/test_game.py -v`
Expected: FAIL — `404 NOT FOUND` on `/game/save` (route doesn't exist yet) causing assertion failures, or `ModuleNotFoundError` if imported directly.

- [ ] **Step 3: Write the implementation**

```python
# backend/game.py
import datetime
import json

from flask import Blueprint, g, jsonify, request

from . import db
from .auth import require_auth

game_bp = Blueprint("game", __name__, url_prefix="/game")


@game_bp.post("/save")
@require_auth
def save():
    if g.auth["role"] == "guest":
        return jsonify(error="guests cannot save"), 403

    data = request.get_json(silent=True) or {}
    if "dice_state" not in data:
        return jsonify(error="dice_state required"), 400

    conn = db.get_db()
    db.save_game_state(
        conn,
        g.auth["user_id"],
        json.dumps(data["dice_state"]),
        datetime.datetime.utcnow().isoformat(),
    )
    return jsonify(status="saved")


@game_bp.get("/load")
@require_auth
def load():
    if g.auth["role"] == "guest":
        return jsonify(error="guests have no saved state"), 403

    conn = db.get_db()
    raw = db.load_game_state(conn, g.auth["user_id"])
    return jsonify(dice_state=json.loads(raw) if raw else None)
```

```python
# backend/app.py
# ... existing imports ...
from .game import game_bp

def create_app(db_path: str = "dicegame.db", secret_key: str | None = None) -> Flask:
    # ... existing body unchanged up to blueprint registration ...
    app.register_blueprint(auth_bp)
    app.register_blueprint(game_bp)
    app.teardown_appcontext(db.close_db)

    return app
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "Portfolio Game" && python -m pytest backend/tests/test_game.py -v`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/game.py backend/app.py backend/tests/test_game.py
git commit -m "feat(backend): add game save/load endpoints, reject guest persistence"
```

---

### Task 4: Admin command endpoint + dispatch table

**Files:**
- Create: `backend/admin.py`
- Modify: `backend/app.py` (register `admin_bp`)
- Test: `backend/tests/test_admin.py`

**Interfaces:**
- Consumes: `auth.require_auth` (Task 2).
- Produces: `admin.admin_bp` (Flask blueprint, mounted at `/admin`), `admin.COMMANDS: dict[str, Callable]` (the extension point for later challenge commands), route `POST /admin/command`.

- [ ] **Step 1: Write the failing tests**

```python
# backend/tests/test_admin.py
def _login(client, username, password):
    return client.post("/auth/login", json={"username": username, "password": password}).get_json()["token"]


def _auth_header(token):
    return {"Authorization": f"Bearer {token}"}


def test_admin_can_run_sort_all(client):
    token = _login(client, "admin", "password1")
    resp = client.post("/admin/command", json={"command": "sort_all"}, headers=_auth_header(token))
    assert resp.status_code == 200
    assert resp.get_json()["effect"] == "sort_all"


def test_regular_user_forbidden_from_admin_command(client):
    client.post("/auth/register", json={"username": "alice", "password": "correcthorsebattery"})
    token = _login(client, "alice", "correcthorsebattery")
    resp = client.post("/admin/command", json={"command": "sort_all"}, headers=_auth_header(token))
    assert resp.status_code == 403


def test_guest_forbidden_from_admin_command(client):
    token = client.post("/auth/guest").get_json()["token"]
    resp = client.post("/admin/command", json={"command": "sort_all"}, headers=_auth_header(token))
    assert resp.status_code == 403


def test_admin_command_requires_auth(client):
    resp = client.post("/admin/command", json={"command": "sort_all"})
    assert resp.status_code == 401


def test_unknown_command_returns_400(client):
    token = _login(client, "admin", "password1")
    resp = client.post("/admin/command", json={"command": "nonexistent"}, headers=_auth_header(token))
    assert resp.status_code == 400
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "Portfolio Game" && python -m pytest backend/tests/test_admin.py -v`
Expected: FAIL — `404 NOT FOUND` on `/admin/command`.

- [ ] **Step 3: Write the implementation**

```python
# backend/admin.py
from flask import Blueprint, g, jsonify, request

from .auth import require_auth

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")


def _sort_all(user_id: int, args: dict) -> dict:
    return {"status": "ok", "effect": "sort_all"}


COMMANDS = {
    "sort_all": _sort_all,
}


@admin_bp.post("/command")
@require_auth
def command():
    if g.auth["role"] != "admin":
        return jsonify(error="forbidden"), 403

    data = request.get_json(silent=True) or {}
    name = data.get("command", "")
    handler = COMMANDS.get(name)
    if handler is None:
        return jsonify(error=f"unknown command: {name}"), 400

    result = handler(g.auth["user_id"], data.get("args", {}))
    return jsonify(result)
```

```python
# backend/app.py
# ... existing imports ...
from .admin import admin_bp

def create_app(db_path: str = "dicegame.db", secret_key: str | None = None) -> Flask:
    # ... existing body unchanged up to blueprint registration ...
    app.register_blueprint(auth_bp)
    app.register_blueprint(game_bp)
    app.register_blueprint(admin_bp)
    app.teardown_appcontext(db.close_db)

    return app
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "Portfolio Game" && python -m pytest backend/tests/test_admin.py -v`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/admin.py backend/app.py backend/tests/test_admin.py
git commit -m "feat(backend): add admin command endpoint with sort_all dispatch table"
```

---

### Task 5: Deployment packaging

**Files:**
- Create: `backend/requirements.txt`
- Create: `backend/wsgi.py`
- Create: `backend/.gitignore`
- Create: `deploy/dicegame-backend.service`

**Interfaces:**
- Consumes: `app.create_app()` (Task 2).
- Produces: a runnable gunicorn entry point (`wsgi:app`) and a systemd unit referencing it. Nothing later depends on new interfaces here — this task packages what already exists.

- [ ] **Step 1: Write the requirements file**

```
# backend/requirements.txt
Flask==3.0.3
bcrypt==4.2.0
itsdangerous==2.2.0
gunicorn==22.0.0
pytest==8.3.2
```

- [ ] **Step 2: Write the WSGI entry point**

```python
# backend/wsgi.py
import os

from backend.app import create_app

app = create_app(
    db_path=os.environ.get("DICEGAME_DB_PATH", "/var/lib/dicegame/dicegame.db"),
)
```

- [ ] **Step 3: Write the gitignore**

```
# backend/.gitignore
__pycache__/
*.pyc
*.db
.pytest_cache/
```

- [ ] **Step 4: Write the systemd unit**

```ini
# deploy/dicegame-backend.service
[Unit]
Description=Dice Sorting Game Backend
After=network.target

[Service]
WorkingDirectory=/opt/dicegame
Environment=SECRET_KEY=change-me-to-a-real-secret
Environment=DICEGAME_DB_PATH=/var/lib/dicegame/dicegame.db
ExecStart=/opt/dicegame/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:8000 backend.wsgi:app
Restart=on-failure
User=dicegame

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 5: Manually verify the server runs and responds**

Run:
```bash
cd "Portfolio Game"
python -m venv .venv && source .venv/bin/activate
pip install -r backend/requirements.txt
DICEGAME_DB_PATH=/tmp/dicegame-smoke.db gunicorn --workers 1 --bind 127.0.0.1:8000 backend.wsgi:app &
sleep 1
curl -s -X POST http://127.0.0.1:8000/auth/login -H "Content-Type: application/json" -d '{"username":"admin","password":"password1"}'
kill %1
```
Expected: JSON response containing `"role":"admin"` and a `"token"` field.

- [ ] **Step 6: Commit**

```bash
git add backend/requirements.txt backend/wsgi.py backend/.gitignore deploy/dicegame-backend.service
git commit -m "chore(backend): add deployment packaging (gunicorn, systemd, requirements)"
```

---

## Client

> All client tasks are verified manually in the Godot editor (Debug → run scene) against a backend started per Task 5 Step 5, run locally at `http://127.0.0.1:8000` — per spec, 3D interaction feel is not automated.

### Task 6: Project scaffold, autoloads, login screen

**Files:**
- Create: `client/project.godot`
- Create: `client/.gitignore`
- Create: `client/autoloads/Config.gd`
- Create: `client/autoloads/GameState.gd`
- Create: `client/autoloads/ApiClient.gd`
- Create: `client/scenes/Login.tscn`
- Create: `client/scenes/Login.gd`

**Interfaces:**
- Produces: autoload singletons `Config` (`backend_url: String`), `GameState` (`token: String`, `role: String`, `has_seen_pickup_tooltip: bool`, `DIE_TYPES: Array`, `SET_COLORS: Array[Color]`, `set_session(token, role)`, `log_out()`), `ApiClient` (`register(username, password)`, `login(username, password)`, `guest()`, `save_game(dice_state)`, `load_game()`, `admin_command(command_name)` — all `await`-able, returning `{"ok": bool, "status": int, "data": Dictionary}`). Every later client task calls into these.

- [ ] **Step 1: Write the project file**

```ini
; client/project.godot
config_version=5

[application]

config/name="Dice Sorting Game"
run/main_scene="res://scenes/Login.tscn"
config/features=PackedStringArray("4.3", "Forward Plus")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"

[autoload]

Config="*res://autoloads/Config.gd"
GameState="*res://autoloads/GameState.gd"
ApiClient="*res://autoloads/ApiClient.gd"
```

- [ ] **Step 2: Write the gitignore**

```
# client/.gitignore
.godot/
*.translation
export/
```

- [ ] **Step 3: Write the autoloads**

```gdscript
# client/autoloads/Config.gd
extends Node

var backend_url: String = "http://127.0.0.1:8000"
```

```gdscript
# client/autoloads/GameState.gd
extends Node

var token: String = ""
var role: String = ""
var has_seen_pickup_tooltip: bool = false

const DIE_TYPES: Array[String] = ["d4", "d6", "d8", "d10", "d12", "d20", "d100"]
const SET_COLORS: Array[Color] = [
	Color(0.8, 0.1, 0.1), Color(0.1, 0.4, 0.8), Color(0.1, 0.7, 0.2),
	Color(0.8, 0.7, 0.1), Color(0.6, 0.1, 0.7), Color(0.9, 0.5, 0.1),
	Color(0.1, 0.7, 0.7), Color(0.9, 0.9, 0.9), Color(0.2, 0.2, 0.2),
	Color(0.9, 0.4, 0.6),
]


func set_session(new_token: String, new_role: String) -> void:
	token = new_token
	role = new_role


func log_out() -> void:
	token = ""
	role = ""
	has_seen_pickup_tooltip = false
```

```gdscript
# client/autoloads/ApiClient.gd
extends Node


func _request(method: HTTPClient.Method, path: String, body: Dictionary = {}, auth: bool = true) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := ["Content-Type: application/json"]
	if auth and GameState.token != "":
		headers.append("Authorization: Bearer %s" % GameState.token)

	var body_string := ""
	if not body.is_empty():
		body_string = JSON.stringify(body)

	var err := http.request(Config.backend_url + path, headers, method, body_string)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "data": {}}

	var result: Array = await http.request_completed
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	http.queue_free()

	var parsed: Variant = {}
	if response_body.size() > 0:
		var text := response_body.get_string_from_utf8()
		var maybe = JSON.parse_string(text)
		if maybe != null:
			parsed = maybe

	return {"ok": response_code >= 200 and response_code < 300, "status": response_code, "data": parsed}


func register(username: String, password: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/auth/register", {"username": username, "password": password}, false)


func login(username: String, password: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/auth/login", {"username": username, "password": password}, false)


func guest() -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/auth/guest", {}, false)


func save_game(dice_state: Array) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/game/save", {"dice_state": dice_state})


func load_game() -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/game/load")


func admin_command(command_name: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/admin/command", {"command": command_name})
```

- [ ] **Step 4: Write the login scene**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/Login.gd" id="1"]

[node name="Login" type="Control"]
layout_mode = 3
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
```

```gdscript
# client/scenes/Login.gd
extends Control

var username_field: LineEdit
var password_field: LineEdit
var status_label: Label


func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.position = Vector2(40, 40)
	add_child(layout)

	var title := Label.new()
	title.text = "Dice Sorting Game"
	layout.add_child(title)

	username_field = LineEdit.new()
	username_field.placeholder_text = "username"
	layout.add_child(username_field)

	password_field = LineEdit.new()
	password_field.placeholder_text = "password"
	password_field.secret = true
	layout.add_child(password_field)

	var register_button := Button.new()
	register_button.text = "Create Account"
	register_button.pressed.connect(_on_register_pressed)
	layout.add_child(register_button)

	var login_button := Button.new()
	login_button.text = "Log In"
	login_button.pressed.connect(_on_login_pressed)
	layout.add_child(login_button)

	var guest_button := Button.new()
	guest_button.text = "Play as Guest"
	guest_button.pressed.connect(_on_guest_pressed)
	layout.add_child(guest_button)

	status_label = Label.new()
	layout.add_child(status_label)


func _on_register_pressed() -> void:
	status_label.text = "Creating account..."
	var result := await ApiClient.register(username_field.text, password_field.text)
	if not result.ok:
		status_label.text = "Registration failed: %s" % str(result.data.get("error", "unknown error"))
		return
	_enter_game(result.data)


func _on_login_pressed() -> void:
	status_label.text = "Logging in..."
	var result := await ApiClient.login(username_field.text, password_field.text)
	if not result.ok:
		status_label.text = "Login failed: invalid credentials"
		return
	_enter_game(result.data)


func _on_guest_pressed() -> void:
	status_label.text = "Connecting..."
	var result := await ApiClient.guest()
	if not result.ok:
		status_label.text = "Could not reach server"
		return
	_enter_game(result.data)


func _enter_game(data: Dictionary) -> void:
	GameState.set_session(data.get("token", ""), data.get("role", ""))
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
```

- [ ] **Step 5: Manually verify**

With the backend running locally (Task 5, Step 5), open `client/` in the Godot 4.3 editor and run the project (F5).
Expected: a login screen appears with username/password fields and three buttons. Clicking **Play as Guest** shows "Connecting..." then errors with "Can't open file 'res://scenes/Main.tscn'" — expected at this point, since Main.tscn doesn't exist until Task 7. This confirms the guest request round-trip to the backend succeeded (no "Could not reach server" message).

- [ ] **Step 6: Commit**

```bash
git add client/project.godot client/.gitignore client/autoloads client/scenes/Login.tscn client/scenes/Login.gd
git commit -m "feat(client): scaffold Godot project, autoloads, and login screen"
```

---

### Task 7: Main scene environment and first-person player

**Files:**
- Create: `client/scenes/Main.tscn`
- Create: `client/scenes/Main.gd`
- Create: `client/scripts/Player.gd`

**Interfaces:**
- Consumes: nothing new from prior tasks (Main.gd will grow in later tasks).
- Produces: `Player` (CharacterBody3D subclass with a `Camera3D` child, WASD + mouse-look movement, an `interact_ray: RayCast3D` and public `hovered_die`/`held_die` fields that Task 9 wires up). `Main.gd` top-level structure (`_build_environment()`, `_build_player()`) that later tasks (8, 9, 10, 11, 12) extend by adding more `_build_*` calls in `_ready()`.

- [ ] **Step 1: Write the player controller**

```gdscript
# client/scripts/Player.gd
extends CharacterBody3D

const SPEED := 4.5
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_DISTANCE := 2.5

var camera: Camera3D
var interact_ray: RayCast3D
var held_die: Node3D = null
var hovered_die: Node3D = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	collision.shape = capsule
	add_child(collision)

	camera = Camera3D.new()
	camera.position = Vector3(0, 0.7, 0)
	add_child(camera)

	interact_ray = RayCast3D.new()
	interact_ray.target_position = Vector3(0, 0, -INTERACT_DISTANCE)
	interact_ray.collide_with_areas = false
	interact_ray.collide_with_bodies = true
	camera.add_child(interact_ray)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -1.3, 1.3)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_interact_pressed()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()
	_update_hover()

	if held_die:
		held_die.global_position = camera.global_position + camera.global_transform.basis.z * -1.2


func _update_hover() -> void:
	if held_die:
		return

	interact_ray.force_raycast_update()
	var collider := interact_ray.get_collider()

	if collider == hovered_die:
		return

	if hovered_die and hovered_die.has_method("set_highlighted"):
		hovered_die.set_highlighted(false)

	hovered_die = null
	if collider and collider.has_method("set_highlighted"):
		hovered_die = collider
		hovered_die.set_highlighted(true)


func _on_interact_pressed() -> void:
	if held_die:
		_release_die()
	elif hovered_die:
		_pick_up_die(hovered_die)


func _pick_up_die(die: Node3D) -> void:
	die.set_highlighted(false)
	die.pick_up()
	held_die = die
	hovered_die = null

	if not GameState.has_seen_pickup_tooltip:
		GameState.has_seen_pickup_tooltip = true
		get_tree().current_scene.show_pickup_tooltip()


func _release_die() -> void:
	held_die.release()
	held_die = null
```

- [ ] **Step 2: Write the main scene**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/Main.gd" id="1"]

[node name="Main" type="Node3D"]
script = ExtResource("1")
```

```gdscript
# client/scenes/Main.gd
extends Node3D

const ROOM_SIZE := 10.0

var player: CharacterBody3D


func _ready() -> void:
	_build_environment()
	_build_player()


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	add_child(light)

	var floor_body := StaticBody3D.new()

	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ROOM_SIZE, 0.2, ROOM_SIZE)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)

	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	floor_mesh.mesh = mesh
	floor_body.add_child(floor_mesh)

	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)


func _build_player() -> void:
	player = preload("res://scripts/Player.gd").new()
	player.position = Vector3(0, 1, 3)
	add_child(player)


func show_pickup_tooltip() -> void:
	pass  # implemented in Task 9
```

- [ ] **Step 3: Manually verify**

Run the project (F5) from `Login.tscn`, log in as guest.
Expected: scene changes to a lit floor. Mouse-look works (move mouse to turn), WASD moves the player, Space jumps, and the player doesn't fall through the floor. Esc releases the mouse cursor.

- [ ] **Step 4: Commit**

```bash
git add client/scenes/Main.tscn client/scenes/Main.gd client/scripts/Player.gd
git commit -m "feat(client): add main scene environment and first-person player controller"
```

---

### Task 8: Die class and pile spawner

**Files:**
- Create: `client/scripts/Die.gd`
- Modify: `client/scenes/Main.gd` (add `_spawn_fresh_pile()`, called from `_ready()`)

**Interfaces:**
- Consumes: `GameState.DIE_TYPES`, `GameState.SET_COLORS` (Task 6).
- Produces: `Die` (RigidBody3D subclass, `class_name Die`) with `die_type: String`, `set_color: Color`, `sorted: bool`, `setup(type: String, color: Color)`, `set_highlighted(on: bool)`, `pick_up()`, `release()`, `mark_sorted()`, `serialize_state() -> Dictionary`. `Main.gd` field `dice: Array[Die]` that Tasks 10, 11, 12 read/extend.

Die geometry uses scaled, labeled cubes as a stand-in for true polyhedral meshes (hand-authoring seven accurate convex dice shapes is an art pass outside this spec, which only requires distinguishable type/color, not geometric fidelity). `Die.setup()` is the single place mesh creation happens, so swapping in real models later doesn't touch any other file.

- [ ] **Step 1: Write the die class**

```gdscript
# client/scripts/Die.gd
extends RigidBody3D
class_name Die

var die_type: String = ""
var set_color: Color = Color.WHITE
var sorted: bool = false

var _material: StandardMaterial3D

const SIZE_BY_TYPE := {
	"d4": 0.18, "d6": 0.2, "d8": 0.22, "d10": 0.24,
	"d12": 0.26, "d20": 0.28, "d100": 0.3,
}


func setup(type: String, color: Color) -> void:
	die_type = type
	set_color = color

	var size := Vector3.ONE * SIZE_BY_TYPE.get(type, 0.2)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material
	add_child(mesh_instance)

	var label := Label3D.new()
	label.text = type
	label.position = Vector3(0, size.y / 2.0 + 0.05, 0)
	label.font_size = 32
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func set_highlighted(on: bool) -> void:
	_material.emission_enabled = on
	_material.emission = Color(1, 1, 1)
	_material.emission_energy_multiplier = 0.6 if on else 0.0


func pick_up() -> void:
	freeze = true
	collision_layer = 0


func release() -> void:
	freeze = false
	collision_layer = 1


func mark_sorted() -> void:
	sorted = true
	freeze = true
	collision_layer = 0


func serialize_state() -> Dictionary:
	return {
		"type": die_type,
		"color": [set_color.r, set_color.g, set_color.b],
		"position": [global_position.x, global_position.y, global_position.z],
		"sorted": sorted,
	}
```

- [ ] **Step 2: Wire pile spawning into Main.gd**

```gdscript
# client/scenes/Main.gd — add near the top of the class
const SET_COUNT_MIN := 5
const SET_COUNT_MAX := 10

var dice: Array[Die] = []
```

```gdscript
# client/scenes/Main.gd — replace _ready() with:
func _ready() -> void:
	_build_environment()
	_build_player()
	_spawn_fresh_pile()
```

```gdscript
# client/scenes/Main.gd — add new method
func _spawn_fresh_pile() -> void:
	var set_count := randi_range(SET_COUNT_MIN, SET_COUNT_MAX)
	var colors := GameState.SET_COLORS.duplicate()
	colors.shuffle()

	for s in range(set_count):
		var color: Color = colors[s % colors.size()]
		for die_type in GameState.DIE_TYPES:
			var die := Die.new()
			die.setup(die_type, color)
			die.position = Vector3(randf_range(-1.5, 1.5), randf_range(1.0, 3.0), randf_range(-1.5, 1.5))
			add_child(die)
			dice.append(die)
```

- [ ] **Step 3: Manually verify**

Run the project, log in as guest.
Expected: 35–70 small labeled cubes (7 per set, one set per random color) drop from above the floor and settle into a pile via physics. Labels ("d4", "d6", ... "d100") are readable when close. Colors are distinct per set.

- [ ] **Step 4: Commit**

```bash
git add client/scripts/Die.gd client/scenes/Main.gd
git commit -m "feat(client): add Die class and randomized pile spawner"
```

---

### Task 9: Pickup/carry/release interaction and first-pickup tooltip

**Files:**
- Modify: `client/scenes/Main.gd` (implement `show_pickup_tooltip()`, add UI layer)

**Interfaces:**
- Consumes: `Player._pick_up_die()` calling `get_tree().current_scene.show_pickup_tooltip()` (already written in Task 7), `GameState.has_seen_pickup_tooltip` (Task 6), `Die.set_highlighted/pick_up/release` (Task 8).
- Produces: `Main.show_pickup_tooltip()` (real implementation), `Main.tooltip_label: Label`, `Main.win_label: Label` (built now, used by Task 10).

Task 7 already wired the *caller* of hover-highlight and pick-up/release into `Player.gd`; this task builds the UI that reacts to it, since it can't be manually verified until there's a visible tooltip and dice actually exist (Task 8).

- [ ] **Step 1: Add the UI layer and tooltip to Main.gd**

```gdscript
# client/scenes/Main.gd — add near the top of the class
var win_label: Label
var tooltip_label: Label
```

```gdscript
# client/scenes/Main.gd — call from _ready(), after _spawn_fresh_pile()
func _ready() -> void:
	_build_environment()
	_build_player()
	_build_ui()
	_spawn_fresh_pile()
```

```gdscript
# client/scenes/Main.gd — add new methods
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	win_label = Label.new()
	win_label.text = "All sets sorted!"
	win_label.visible = false
	win_label.position = Vector2(400, 50)
	canvas.add_child(win_label)

	tooltip_label = Label.new()
	tooltip_label.text = "Click to pick up. Click again to place it in a matching tray."
	tooltip_label.visible = false
	tooltip_label.position = Vector2(20, 20)
	canvas.add_child(tooltip_label)


func show_pickup_tooltip() -> void:
	tooltip_label.visible = true
	await get_tree().create_timer(4.0).timeout
	tooltip_label.visible = false
```

- [ ] **Step 2: Manually verify**

Run the project, log in as guest. Look at a die (crosshair over it) — it should glow. Look away — glow stops. Click a highlighted die: it snaps to hover in front of the camera and follows the camera as you move/look. This is the *first* pickup in the session, so the tooltip text should appear at top-left and disappear after ~4 seconds. Click again to release — the die drops with physics at the release point. Pick up a second die: the tooltip should NOT reappear (per `has_seen_pickup_tooltip`).

- [ ] **Step 3: Commit**

```bash
git add client/scenes/Main.gd
git commit -m "feat(client): wire pickup/carry/release feedback and one-time tooltip"
```

---

### Task 10: Trays, sorting, and win condition

**Files:**
- Create: `client/scripts/Tray.gd`
- Modify: `client/scenes/Main.gd` (add `_build_trays()`, `_on_die_sorted()`, `trays: Array[Tray]`)

**Interfaces:**
- Consumes: `Die.sorted`, `Die.set_color`, `Die.mark_sorted()` (Task 8), `Main.dice`, `Main.win_label` (Tasks 8, 9).
- Produces: `Tray` (Area3D subclass, `class_name Tray`) with `tray_color: Color`, `setup(color: Color)`, signal `die_sorted(die: Die)`. `Main.trays: Array[Tray]` and `Main._on_die_sorted()`/`Main.apply_sort_all()` (the latter is a stub here, implemented fully in Task 12) that later tasks call.

- [ ] **Step 1: Write the tray class**

```gdscript
# client/scripts/Tray.gd
extends Area3D
class_name Tray

signal die_sorted(die: Die)

var tray_color: Color = Color.WHITE


func setup(color: Color) -> void:
	tray_color = color

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.4, 0.8)
	shape.shape = box
	add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	add_child(mesh_instance)

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Die and not body.sorted and body.set_color.is_equal_approx(tray_color):
		body.global_position = global_position + Vector3(0, 0.3, 0)
		body.mark_sorted()
		die_sorted.emit(body)
	# wrong color, or already sorted: no-op — die just rests here physically, no punishment
```

- [ ] **Step 2: Wire trays into Main.gd**

```gdscript
# client/scenes/Main.gd — add near the top of the class
var trays: Array[Tray] = []
```

```gdscript
# client/scenes/Main.gd — call from _ready(), before _spawn_fresh_pile()
func _ready() -> void:
	_build_environment()
	_build_player()
	_build_ui()
	_build_trays()
	_spawn_fresh_pile()
```

```gdscript
# client/scenes/Main.gd — add new methods
func _build_trays() -> void:
	var colors := GameState.SET_COLORS
	for i in range(colors.size()):
		var tray := Tray.new()
		tray.setup(colors[i])
		var angle := (float(i) / colors.size()) * TAU
		var radius := ROOM_SIZE / 2.0 - 1.0
		tray.position = Vector3(cos(angle) * radius, 0.2, sin(angle) * radius)
		tray.die_sorted.connect(_on_die_sorted)
		add_child(tray)
		trays.append(tray)


func _on_die_sorted(_die: Die) -> void:
	if dice.all(func(d): return d.sorted):
		win_label.visible = true


func apply_sort_all() -> void:
	pass  # implemented in Task 12
```

Note: trays are pre-built for every color in `GameState.SET_COLORS`, not just the colors used in the current session's pile — this is intentional so trays don't need to be regenerated to match whatever random subset of colors `_spawn_fresh_pile()` picked.

- [ ] **Step 3: Manually verify**

Run the project, log in as guest. Walk to one of the colored translucent trays around the room's edge. Carry a die matching that tray's color into it and release — it should snap neatly into the tray and stay there (frozen). Carry a die of a *different* color into the same tray — it should just fall through/rest on top with no snap, no message. Repeat sorting until every die is in its matching tray — the "All sets sorted!" label should appear top-of-screen.

- [ ] **Step 4: Commit**

```bash
git add client/scripts/Tray.gd client/scenes/Main.gd
git commit -m "feat(client): add trays, color-matched sorting, and win condition"
```

---

### Task 11: Save/load integration

**Files:**
- Modify: `client/scenes/Main.gd` (add `_try_load_saved_state()`, `save_current_state()`, autosave timer, quit-save hook)

**Interfaces:**
- Consumes: `ApiClient.save_game()`, `ApiClient.load_game()` (Task 6), `GameState.role` (Task 6), `Die.setup/mark_sorted/serialize_state` (Task 8).
- Produces: `Main.save_current_state()` (called by Task 12's admin console is not required, but kept public for consistency); behavior change: `_ready()` now loads a saved session instead of always spawning fresh, for non-guest roles with an existing save.

- [ ] **Step 1: Make pile creation conditional on a loaded save**

```gdscript
# client/scenes/Main.gd — replace _ready() with:
func _ready() -> void:
	_build_environment()
	_build_player()
	_build_ui()
	_build_trays()

	var loaded := await _try_load_saved_state()
	if not loaded:
		_spawn_fresh_pile()

	_start_autosave_timer()
```

- [ ] **Step 2: Add load/save/autosave methods**

```gdscript
# client/scenes/Main.gd — add new methods
func _try_load_saved_state() -> bool:
	if GameState.role == "guest":
		return false

	var result := await ApiClient.load_game()
	if not result.ok or result.data.get("dice_state") == null:
		return false

	for entry in result.data["dice_state"]:
		var die := Die.new()
		var color := Color(entry["color"][0], entry["color"][1], entry["color"][2])
		die.setup(entry["type"], color)
		die.position = Vector3(entry["position"][0], entry["position"][1], entry["position"][2])
		add_child(die)
		if entry["sorted"]:
			die.mark_sorted()
		dice.append(die)

	return true


func save_current_state() -> void:
	if GameState.role == "guest":
		return

	var state: Array = []
	for die in dice:
		state.append(die.serialize_state())
	await ApiClient.save_game(state)


func _start_autosave_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(func(): save_current_state())
	add_child(timer)
	timer.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		await save_current_state()
		get_tree().quit()
```

- [ ] **Step 3: Manually verify**

Run the project, register a new account (not guest), sort 2–3 dice into their correct trays, then close the game window (triggers save-on-quit). Relaunch, log in with the same account: the scene should reconstruct with those same dice already sorted into their trays instead of a fresh pile. Then log in as **guest** in a separate run: confirm the pile is freshly randomized every time (no load attempted) and that quitting doesn't error even though nothing was saved.

- [ ] **Step 4: Commit**

```bash
git add client/scenes/Main.gd
git commit -m "feat(client): save/load exact dice state for registered users, autosave every 30s"
```

---

### Task 12: Admin console and sort_all

**Files:**
- Modify: `client/scenes/Main.gd` (add `_build_admin_console()`, `toggle_admin_console()`, real `apply_sort_all()`, `_unhandled_input()`)

**Interfaces:**
- Consumes: `ApiClient.admin_command()` (Task 6), `GameState.role` (Task 6), `Main.dice`/`Main.trays`/`Main._on_die_sorted()` (Tasks 8, 10).
- Produces: nothing new consumed elsewhere — this is the last task in the plan.

- [ ] **Step 1: Build the console and hook it up**

```gdscript
# client/scenes/Main.gd — add near the top of the class
var admin_console: Control
```

```gdscript
# client/scenes/Main.gd — call from _ready(), after _start_autosave_timer()
func _ready() -> void:
	_build_environment()
	_build_player()
	_build_ui()
	_build_trays()

	var loaded := await _try_load_saved_state()
	if not loaded:
		_spawn_fresh_pile()

	_start_autosave_timer()

	if GameState.role == "admin":
		_build_admin_console()
```

```gdscript
# client/scenes/Main.gd — add new methods
func _build_admin_console() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	admin_console = Control.new()
	admin_console.visible = false
	canvas.add_child(admin_console)

	var box := VBoxContainer.new()
	box.position = Vector2(20, 400)
	admin_console.add_child(box)

	var input := LineEdit.new()
	input.placeholder_text = "admin command (e.g. sort_all)"
	box.add_child(input)

	var output := Label.new()
	box.add_child(output)

	input.text_submitted.connect(func(command_text: String):
		var result := await ApiClient.admin_command(command_text)
		if result.ok and command_text == "sort_all":
			apply_sort_all()
		output.text = str(result.data)
		input.text = ""
	)


func toggle_admin_console() -> void:
	if admin_console:
		admin_console.visible = not admin_console.visible


func apply_sort_all() -> void:
	for die in dice:
		if not die.sorted:
			for tray in trays:
				if tray.tray_color.is_equal_approx(die.set_color):
					die.global_position = tray.global_position + Vector3(0, 0.3, 0)
					die.mark_sorted()
					break
	_on_die_sorted(null)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.role == "admin" and event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		toggle_admin_console()
```

- [ ] **Step 2: Manually verify**

Start the backend (Task 5) and run the client, logging in with `admin` / `password1`. Press `` ` `` (backtick) — the console should appear with a text field. Type `sort_all` and press Enter: every unsorted die should snap into its matching tray, the win label should appear if everything is now sorted, and the output label should show the backend's JSON response (`{status: ok, effect: sort_all}`). Press `` ` `` again to hide the console. Then log in as a regular user or guest in a separate run and confirm the console never appears, even if `` ` `` is pressed.

- [ ] **Step 3: Commit**

```bash
git add client/scenes/Main.gd
git commit -m "feat(client): add admin console overlay wired to backend sort_all command"
```
