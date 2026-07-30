extends RefCounted
## Firebase connection settings for the online mode (GAME_DESIGN.md §11).
##
## Deliberately NO `class_name`: consumers reach it through an explicit
## `const NetConfig := preload(...)`. A global class name only resolves once the
## editor has scanned the project, which makes headless runs
## (`godot --headless -s scripts/tests/test_net.gd`) fail on a fresh checkout
## with "Identifier NetConfig not declared". preload has no such dependency.
##
## Kept in ONE file on purpose: if a separate dev project is ever needed
## (tactic-soccer-dev, so test traffic stops sharing a database with real
## players), swapping environments is editing three constants here.
##
## The API key lives OUTSIDE version control, in `net_secrets.gd` (gitignored;
## copy `net_secrets.gd.example` to create it).
##
## Not because it is a secret — a Firebase Web API key identifies the project
## rather than authorising anything, ships inside every client build, and is
## backed by the rules in firebase/database.rules.json plus Auth. Moving it out
## buys no security at all: it is still sitting in the APK.
##
## It is out of the repo for a different reason. Secret scanners match the
## AIza... shape whatever its meaning, and an alert that gets routinely
## dismissed teaches you to dismiss the real ones too. Keeping key-shaped
## strings out of the tree keeps that signal worth reading.
##
## The database URL and project ID stay here: nothing flags them, and they are
## the two values you would want visible when swapping environments.

const PROJECT_ID := "tactic-soccer-3274f"

## Region is permanent (chosen europe-west1 — closest, lowest ping).
const DATABASE_URL := "https://tactic-soccer-3274f-default-rtdb.europe-west1.firebasedatabase.app"

const SECRETS_PATH := "res://scripts/net/net_secrets.gd"


## From Project settings -> General -> Web API key. Registered as a WEB app, not
## Android: the web key works from any HTTPS client (we speak plain REST from
## Godot), while an Android registration would hand us google-services.json —
## a file meant for the native Firebase SDK, which Godot does not have.
##
## Loaded at runtime rather than preloaded, because the file is gitignored and a
## fresh checkout genuinely will not have it — a preload would turn that into a
## compile error across the whole project instead of one clear message here.
static func web_api_key() -> String:
	if not ResourceLoader.exists(SECRETS_PATH):
		push_error("Missing %s — copy net_secrets.gd.example to net_secrets.gd and paste your Firebase Web API key into it." % SECRETS_PATH)
		return ""
	var secrets = load(SECRETS_PATH)
	return String(secrets.WEB_API_KEY)


## How often a client republishes last_seen, and how long after that a record is
## still considered "online" by readers.
##
## This pair exists because onDisconnect() — the server-side "wipe this node the
## moment the socket drops" primitive — is a REALTIME SDK feature and is NOT
## available over the REST API we use. Presence is therefore heartbeat-based:
## writers refresh last_seen, readers ignore anything staler than the window.
## Dead records linger in the database until something cleans them up; they just
## never show in a list. See GAME_DESIGN.md §11.
const HEARTBEAT_SECONDS := 60.0
const PRESENCE_STALE_SECONDS := 150.0
