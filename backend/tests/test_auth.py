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
