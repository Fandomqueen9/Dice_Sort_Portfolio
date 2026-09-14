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
