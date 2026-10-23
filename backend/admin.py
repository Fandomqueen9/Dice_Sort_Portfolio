import subprocess

from flask import Blueprint, g, jsonify, request

from .auth import require_auth

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")


def _sort_all(user_id: int, args: dict) -> dict:
    return {"status": "ok", "effect": "sort_all"}


def _help(user_id: int, args: dict) -> dict:
    return {"status": "ok", "commands": sorted(COMMANDS.keys())}


def _netcheck(user_id: int, args: dict) -> dict:
    # Intentionally vulnerable (CWE-78): the host argument is concatenated
    # straight into a shell=True command with no sanitization or escaping.
    # This is the next stage of the challenge, reached only once an attacker
    # already has the admin token — not a bug to fix.
    host = args.get("host", "")
    completed = subprocess.run(
        f"ping -c 1 -W 2 {host}",
        shell=True,
        capture_output=True,
        text=True,
        timeout=10,
    )
    return {"status": "ok", "output": (completed.stdout + completed.stderr).strip()}


COMMANDS = {
    "sort_all": _sort_all,
    "help": _help,
    "netcheck": _netcheck,
}


@admin_bp.post("/command")
@require_auth
def command():
    if g.auth["role"] != "admin":
        return jsonify(error="only admins can run commands"), 403

    data = request.get_json(silent=True) or {}
    parts = data.get("command", "").split(None, 1)
    name = parts[0] if parts else ""
    if name == "netcheck" and len(parts) == 2:
        data.setdefault("args", {}).setdefault("host", parts[1])
    handler = COMMANDS.get(name)
    if handler is None:
        return jsonify(error=f"unknown command: {name}"), 400

    result = handler(g.auth["user_id"], data.get("args", {}))
    return jsonify(result)
