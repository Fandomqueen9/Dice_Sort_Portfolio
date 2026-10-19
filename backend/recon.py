from flask import Blueprint

recon_bp = Blueprint('recon', __name__)

@recon_bp.route('/old-deploy-notes.txt')
def old_deploy_notes():
    """Legacy deploy notes left behind — contains dev credentials."""
    notes = """=== Dice Game Deployment Notes (INTERNAL) ===

Admin account: admin
Password: password1

SSH keys stored in: .deploy/id_ed25519
Game server user: dicegame

Remember to remove this file before production.
"""
    return notes, 200, {'Content-Type': 'text/plain'}