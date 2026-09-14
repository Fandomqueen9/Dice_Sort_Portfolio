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
