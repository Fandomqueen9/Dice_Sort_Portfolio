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
