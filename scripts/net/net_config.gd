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
## NOT SECRETS. A Firebase Web API key ships inside every client build anyway —
## anyone can unzip the APK and read it. Firebase's security model does not rely
## on hiding it: access is controlled by database rules
## (firebase/database.rules.json) plus Auth. So this belongs in version control,
## same as the database URL.

const PROJECT_ID := "tactic-soccer-3274f"

## Region is permanent (chosen europe-west1 — closest, lowest ping).
const DATABASE_URL := "https://tactic-soccer-3274f-default-rtdb.europe-west1.firebasedatabase.app"

## From Project settings -> General -> Web API key. Registered as a WEB app, not
## Android: the web key works from any HTTPS client (we speak plain REST from
## Godot), while an Android registration would hand us google-services.json —
## a file meant for the native Firebase SDK, which Godot does not have.
const WEB_API_KEY := "AIzaSyB1XjDWjOYHkVPJvy6YVZyZDfpzTY5fGY8"


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
