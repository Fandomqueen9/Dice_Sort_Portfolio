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
