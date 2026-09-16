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
    assert resp.get_json()["error"] == "only admins can run commands"


def test_guest_forbidden_from_admin_command(client):
    token = client.post("/auth/guest").get_json()["token"]
    resp = client.post("/admin/command", json={"command": "sort_all"}, headers=_auth_header(token))
    assert resp.status_code == 403
    assert resp.get_json()["error"] == "only admins can run commands"


def test_admin_command_requires_auth(client):
    resp = client.post("/admin/command", json={"command": "sort_all"})
    assert resp.status_code == 401


def test_unknown_command_returns_400(client):
    token = _login(client, "admin", "password1")
    resp = client.post("/admin/command", json={"command": "nonexistent"}, headers=_auth_header(token))
    assert resp.status_code == 400


def test_admin_can_run_help_and_sees_all_commands(client):
    token = _login(client, "admin", "password1")
    resp = client.post("/admin/command", json={"command": "help"}, headers=_auth_header(token))
    assert resp.status_code == 200
    assert resp.get_json()["commands"] == ["help", "sort_all"]


def test_regular_user_forbidden_from_help(client):
    client.post("/auth/register", json={"username": "bob", "password": "correcthorsebattery"})
    token = _login(client, "bob", "correcthorsebattery")
    resp = client.post("/admin/command", json={"command": "help"}, headers=_auth_header(token))
    assert resp.status_code == 403
    assert resp.get_json()["error"] == "only admins can run commands"


def test_guest_forbidden_from_help(client):
    token = client.post("/auth/guest").get_json()["token"]
    resp = client.post("/admin/command", json={"command": "help"}, headers=_auth_header(token))
    assert resp.status_code == 403
    assert resp.get_json()["error"] == "only admins can run commands"
