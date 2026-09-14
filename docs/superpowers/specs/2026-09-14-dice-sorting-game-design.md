# Dice Sorting Game — Design Spec

## Context

A 3D single-player dice-sorting game, built as the cover/context application for a later cyber security assessment. The game itself is not assessed — it exists to give the security challenge a realistic target: a login system with a deliberately weak admin account, gated debug commands, and a real (if small) attack surface. This spec covers only the game and its backend; the rest of the security challenge (additional admin commands, the vulnerability chain to reach them) is added later and is out of scope here.

Genre reference: "tidying/organizing simulator" games (*Black Friday Janitor: Clean the Whole Mall*, *Librarian: Tidy Up the Arcane Library*, *Megastore: Tidy Up Together*) — a satisfying pile of items sorted into their correct places, cozy pacing, no punishment for mistakes.

## Goals

- A first-person 3D game where the player sorts a pile of D&D dice into color-matched sets.
- Three login paths: create account (progress saved), guest (no save), admin (weak credentials by design).
- Admin-only in-game debug console, starting with one command (`sort_all`), built so more commands can be added later without restructuring.
- Client and backend run on separate Linux VMs, communicating over HTTP — this split is the actual point of the exercise, not an implementation detail.

## Non-Goals

- No multiplayer or shared game state — every player has an independent pile and progress (confirmed single-player-only).
- No timer/scoring — win condition is simply "all sets sorted."
- No punishment or feedback for dropping a die in the wrong tray — it's a silent non-event.
- No auto-updater or installer for the client — distribution to player VMs is manual (shared folder / scp) for this lab context.
- The rest of the security challenge (the vulnerability chain beyond guessing the admin password, and any debug commands beyond `sort_all`) is not designed here.

## Architecture

```
┌─────────────────────────┐         HTTP (REST)          ┌──────────────────────────┐
│  Player VM (Ubuntu       │ ───────────────────────────► │  Hosting VM (Debian 12)  │
│  Desktop 24.04)          │ ◄─────────────────────────── │                          │
│  Godot 4 client (Linux   │                               │  Flask API + SQLite     │
│  binary), first-person   │                               │  - auth / sessions       │
│  sorting game            │                               │  - save/load game state │
└─────────────────────────┘                               │  - admin command exec    │
                                                            └──────────────────────────┘
```

- **Hosting VM (Debian 12):** Flask REST API, run via gunicorn behind systemd. SQLite for storage — no separate DB server needed at this scale.
- **Player VM(s) (Ubuntu Desktop 24.04):** Godot 4 (GDScript) client, exported as a Linux binary. All gameplay (physics grab-and-carry, sorting, win check) runs client-side, since there's no shared state to sync. The client talks to the backend only for login, save/load, and admin commands.
- **Rendering constraint:** player VMs likely lack GPU passthrough, so 3D rendering falls back to software rendering (llvmpipe). Use Godot's Compatibility renderer and keep the scene low-poly (simple dice models, minimal dynamic lighting) to stay playable. If GPU passthrough/vGPU becomes available on any player VM, this constraint can be relaxed.
- **Backend URL is a single config value** in the Godot client, not hardcoded in multiple places — pointing the client at a different hosting VM is a one-line change.

## Auth Model

Three paths at the login screen:

1. **Create Account** — username + password. Password hashed server-side with bcrypt/argon2. Progress is saved.
2. **Guest** — no credentials. Session-only token, never persisted server-side. Save is unavailable (hidden client-side; also rejected server-side if attempted).
3. **Admin** — a fixed, seeded account with an intentionally weak password (e.g. `admin` / `password1`). This is the deliberate vulnerability for the later challenge, not an oversight — everything else in the auth system follows normal security practice so the admin account is the one deliberately weak point, not a symptom of a generally insecure system.

All logins (any role) return the same generic "invalid credentials" message on failure — no signal that distinguishes a wrong admin password from a wrong guest/user attempt.

## Data Model (SQLite)

- `users`: `id, username, password_hash, role` — `role` is `user` or `admin`. The admin row is seeded at setup time.
- `saves`: `user_id, dice_state (JSON: per-die id → position, rotation, tray), updated_at`

## Data Flow

**Login:** Client → `POST /auth/login` | `/auth/register` | `/auth/guest` → Flask validates and returns a session token + role. Client holds the token in memory and sends it as an `Authorization` header on every subsequent request.

**Save/load:** Client → `POST /game/save` with full dice state (position/rotation/tray per die) — on quit and/or periodic autosave. Returning users → `GET /game/load` to reconstruct the exact scene they left. Guests always get a freshly generated pile; `/game/save` is rejected server-side for guest tokens regardless of what the client sends.

**Admin commands:** The console overlay (`~` key) only renders client-side if the session's role is `admin` — this is UX only. Every command still `POST`s to `/admin/command` with the token, and Flask re-checks the role server-side before executing anything. Commands are implemented as a dispatch table (`command name → handler function`), starting with one entry:

- `sort_all` — marks every die's server-side state as correctly sorted; client then snaps the scene to match.

This dispatch table is the extension point for the rest of the challenge later.

## Gameplay

**Pile generation:** A fresh session spawns 5–10 dice sets (configurable), each a standard 7-piece polyhedral set (d4, d6, d8, d10, d12, d20, d%) in one color. All dice for a session spawn with physics enabled, dropped from height into a pile in the center of the room so they scatter naturally.

**Interaction:** First-person camera/controller. Raycast from camera center highlights the die under the crosshair (outline/glow) when in reach — no repeated text prompt. A single one-time tooltip appears on the player's very first pickup only, to teach the mechanic. Left-click picks up a highlighted die (held in front of the camera); left-click again releases it.

**Sorting:** One tray per color, placed around the room, each with a trigger volume. Releasing a held die inside its matching tray snaps it into a neat stack and marks it sorted in local state. Releasing it anywhere else (wrong tray or open floor) just drops it physically — no visual/audio feedback, no penalty.

**Win condition:** All `sets × 7` dice marked sorted → completion popup. No timer, no score.

## Error Handling

- Duplicate username on register → rejected, no account created, no partial state.
- Invalid login (any role) → generic "invalid credentials" message.
- Guest attempts to save → hidden client-side; 403 server-side if attempted anyway.
- Server unreachable at login → client shows a connection-error screen rather than hanging indefinitely.

## Testing

- **3D interaction (grab/carry/sort feel):** manual playtesting only — not worth automating.
- **Flask backend:** automated tests (pytest) for password hashing, role gating on `/admin/command`, guest save rejection, and session token validation. This logic is exactly what the later security challenge depends on being correctly *not* broken — only the admin password itself should be weak, not the enforcement code around it.

## Deployment

- **Hosting VM:** Flask app behind gunicorn, managed by systemd, listening on the VM's LAN IP:port. SQLite file lives alongside the app.
- **Player VM(s):** Godot project exported to a Linux binary, distributed manually (shared folder/scp) to each player VM. Player enters the hosting VM's IP:port at the login screen to connect.
