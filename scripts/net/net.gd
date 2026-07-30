extends Node
## Autoload ("Net"). Firebase client for Godot: anonymous auth + Realtime
## Database over plain REST. Hand-rolled on top of HTTPRequest rather than an
## SDK — Godot has no official Firebase SDK, and the community addon would tie
## the project to someone else's 4.x compatibility (GAME_DESIGN.md §11).
##
## Every call is a coroutine returning a plain Dictionary, so callers read
## top to bottom instead of hopping between signal handlers:
##
##     var res := await Net.db_put("players/%s" % Net.uid, {...})
##     if not res["ok"]:
##         push_error(res["error"])
##
## Result shape is always the same: {ok, code, data, error}.
##
## What this file deliberately does NOT do: validate game rules. Database rules
## guard DATA (who may write where), this guards TRANSPORT, and MatchState
## guards the RULES OF THE GAME. Keeping those three apart is the whole reason
## a modified client can't do more than desync itself out of a match.

## Explicit preload rather than a global `class_name` — see net_config.gd for
## why (headless runs can't rely on the editor's class registry).
const NetConfig := preload("res://scripts/net/net_config.gd")

signal auth_ready(player_uid: String)
signal auth_failed(message: String)

## Fires on BOTH outcomes. auth_ready alone is not enough to wait on: a second
## caller parked on it during a failing sign-in would wait forever, because a
## failure emits auth_failed instead and nothing ever resumes the coroutine.
signal auth_settled

const SIGNUP_URL := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s"
const REFRESH_URL := "https://securetoken.googleapis.com/v1/token?key=%s"

## Where the refresh token is cached. Persisting it is what makes the anonymous
## UID STABLE across launches — without it every start would mint a brand new
## anonymous account, littering the project with throwaway users and making the
## player's identity change under them. Separate from settings.cfg: that file is
## user preferences, this is a credential.
const AUTH_CACHE_PATH := "user://net_auth.cfg"

const REQUEST_TIMEOUT := 10.0
## Refresh a little before the hour is actually up, so a call never departs with
## a token that expires mid-flight.
const TOKEN_REFRESH_MARGIN := 120.0

var uid := ""
var signed_in := false

## Off for a SECOND client in the same process (the two-client test), so it
## signs up as its own anonymous player instead of loading — and then
## overwriting — the real one's cached identity.
var use_token_cache := true

var _id_token := ""
var _refresh_token := ""
var _token_expires_at := 0.0
## Guards against two callers kicking off overlapping sign-in/refresh flows.
var _auth_in_flight := false
var _last_auth_result := {"ok": false, "code": 0, "data": null, "error": "not signed in yet"}


# --- Auth ---------------------------------------------------------------------

## Signs in anonymously, reusing the cached refresh token when there is one.
## Safe to call repeatedly — returns immediately once a valid token is held.
func sign_in() -> Dictionary:
	if signed_in and not _token_expired():
		return _ok(200, {"uid": uid})

	# A second caller during an in-flight sign-in waits for the first to land
	# rather than starting a competing one.
	if _auth_in_flight:
		await auth_settled
		return _last_auth_result

	_auth_in_flight = true
	var res := await _do_sign_in()
	_auth_in_flight = false
	_last_auth_result = res

	if res["ok"]:
		auth_ready.emit(uid)
	else:
		auth_failed.emit(res["error"])
	auth_settled.emit()
	return res


func _do_sign_in() -> Dictionary:
	_load_cached_token()
	if _refresh_token != "":
		var refreshed := await _refresh_id_token()
		if refreshed["ok"]:
			return refreshed
		# The cached token is no longer good. Most likely cause is benign and
		# expected: anonymous accounts are auto-deleted after 30 days of
		# inactivity (GAME_DESIGN.md §11), so a returning player's account is
		# simply gone. Fall through and mint a fresh one — from their side
		# nothing happened, their name lives in settings.cfg either way.
		_clear_cached_token()
	return await _sign_up_anonymous()


func _sign_up_anonymous() -> Dictionary:
	var res := await _http_json(
		SIGNUP_URL % NetConfig.web_api_key(),
		HTTPClient.METHOD_POST,
		{"returnSecureToken": true})
	if not res["ok"]:
		return _err(res["code"], "anonymous sign-in failed: %s" % res["error"])

	var d: Dictionary = res["data"]
	_apply_tokens(
		String(d.get("idToken", "")),
		String(d.get("refreshToken", "")),
		float(String(d.get("expiresIn", "3600")).to_int()),
		String(d.get("localId", "")))
	if uid == "":
		return _err(res["code"], "sign-in response had no localId")
	return _ok(res["code"], {"uid": uid})


func _refresh_id_token() -> Dictionary:
	# This endpoint is form-encoded, not JSON, and answers in snake_case —
	# unlike the identitytoolkit one right above. Easy to trip over.
	var body := "grant_type=refresh_token&refresh_token=%s" % _refresh_token.uri_encode()
	var res := await _http_raw(
		REFRESH_URL % NetConfig.web_api_key(),
		HTTPClient.METHOD_POST,
		body,
		["Content-Type: application/x-www-form-urlencoded"])
	if not res["ok"]:
		return _err(res["code"], "token refresh failed: %s" % res["error"])

	var d: Dictionary = res["data"]
	_apply_tokens(
		String(d.get("id_token", "")),
		String(d.get("refresh_token", "")),
		float(String(d.get("expires_in", "3600")).to_int()),
		String(d.get("user_id", "")))
	return _ok(res["code"], {"uid": uid})


func _apply_tokens(id_token: String, refresh_token: String, expires_in: float, user_id: String) -> void:
	_id_token = id_token
	if refresh_token != "":
		_refresh_token = refresh_token
	if user_id != "":
		uid = user_id
	_token_expires_at = Time.get_unix_time_from_system() + expires_in
	signed_in = _id_token != "" and uid != ""
	if signed_in:
		_save_cached_token()


func _token_expired() -> bool:
	return Time.get_unix_time_from_system() >= _token_expires_at - TOKEN_REFRESH_MARGIN


## Every DB call funnels through here so a long session can't fire a request
## with an hour-old token. Returns the FULL result, not a bool: the caller needs
## the real reason. An earlier version collapsed every auth problem into a bare
## "not signed in", which is how a missing Android INTERNET permission showed up
## as an unexplainable error on the phone while the desktop worked fine.
func _ensure_token() -> Dictionary:
	if signed_in and not _token_expired():
		return _ok(200, {"uid": uid})
	return await sign_in()


func _save_cached_token() -> void:
	if not use_token_cache:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "refresh_token", _refresh_token)
	cfg.set_value("auth", "uid", uid)
	cfg.save(AUTH_CACHE_PATH)


func _load_cached_token() -> void:
	if not use_token_cache or _refresh_token != "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(AUTH_CACHE_PATH) != OK:
		return
	_refresh_token = cfg.get_value("auth", "refresh_token", "")
	uid = cfg.get_value("auth", "uid", "")


func _clear_cached_token() -> void:
	_refresh_token = ""
	uid = ""
	signed_in = false
	if use_token_cache:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTH_CACHE_PATH))


## Drops local credentials (testing, or "sign out" later). The anonymous account
## itself stays until Firebase's 30-day cleanup collects it.
func sign_out() -> void:
	_id_token = ""
	_token_expires_at = 0.0
	_clear_cached_token()


# --- Realtime Database (REST) --------------------------------------------------

func db_get(path: String) -> Dictionary:
	return await _db_call(HTTPClient.METHOD_GET, path, null)


func db_put(path: String, value) -> Dictionary:
	return await _db_call(HTTPClient.METHOD_PUT, path, value)


func db_patch(path: String, value: Dictionary) -> Dictionary:
	return await _db_call(HTTPClient.METHOD_PATCH, path, value)


func db_delete(path: String) -> Dictionary:
	return await _db_call(HTTPClient.METHOD_DELETE, path, null)


## Server-side clock. Written as the RTDB sentinel {".sv": "timestamp"} so the
## SERVER stamps it, not the device — two phones with skewed clocks would
## otherwise disagree about turn deadlines and presence freshness.
static func server_timestamp() -> Dictionary:
	return {".sv": "timestamp"}


func _db_call(method: int, path: String, value) -> Dictionary:
	var auth := await _ensure_token()
	if not auth["ok"]:
		return auth
	var url := "%s/%s.json?auth=%s" % [
		NetConfig.DATABASE_URL,
		path.strip_edges().lstrip("/"),
		_id_token.uri_encode()]
	return await _http_json(url, method, value)


# --- HTTP plumbing -------------------------------------------------------------

func _http_json(url: String, method: int, value) -> Dictionary:
	var body := "" if value == null else JSON.stringify(value)
	return await _http_raw(url, method, body, ["Content-Type: application/json"])


func _http_raw(url: String, method: int, body: String, headers: PackedStringArray) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)

	var started := http.request(url, headers, method, body)
	if started != OK:
		http.queue_free()
		return _err(0, "could not start request (error %d)" % started)

	var out: Array = await http.request_completed
	http.queue_free()

	var result: int = out[0]
	var code: int = out[1]
	var raw: PackedByteArray = out[3]
	var text := raw.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		return _err(code, _transport_error(result))

	var parsed = null
	if text.strip_edges() != "":
		parsed = JSON.parse_string(text)
		# Firebase always answers JSON; unparseable text means something else
		# replied (captive portal, proxy error page) — report it verbatim
		# instead of pretending it was a null value.
		if parsed == null and text.strip_edges() != "null":
			return _err(code, "unparseable response: %s" % text.left(200))

	if code < 200 or code >= 300:
		return _err(code, _error_message(parsed, text))

	return _ok(code, parsed)


## Turns HTTPRequest's numeric Result into something a person can act on.
## "transport error 3" told us nothing when the phone couldn't sign in; the
## actual meaning (DNS resolution failed) points straight at the cause, so the
## Android case even names it outright — a build exported without the INTERNET
## permission fails exactly like this while the same code works on desktop.
func _transport_error(result: int) -> String:
	var names := {
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: "chunked body size mismatch",
		HTTPRequest.RESULT_CANT_CONNECT: "can't connect to host",
		HTTPRequest.RESULT_CANT_RESOLVE: "can't resolve host (DNS)",
		HTTPRequest.RESULT_CONNECTION_ERROR: "connection error",
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS handshake failed",
		HTTPRequest.RESULT_NO_RESPONSE: "no response",
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "response too large",
		HTTPRequest.RESULT_REQUEST_FAILED: "request failed",
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "too many redirects",
		HTTPRequest.RESULT_TIMEOUT: "timed out after %.0f s" % REQUEST_TIMEOUT,
	}
	var msg: String = names.get(result, "transport error %d" % result)

	var no_route := result == HTTPRequest.RESULT_CANT_RESOLVE \
		or result == HTTPRequest.RESULT_CANT_CONNECT
	if no_route and OS.get_name() == "Android":
		msg += " — check that the Android export preset has the INTERNET permission enabled"
	return msg


## Digs the human-readable bit out of Firebase's two different error shapes:
## Identity Toolkit answers {"error": {"message": "..."}}, while the Realtime
## Database answers {"error": "Permission denied"}.
func _error_message(parsed, fallback: String) -> String:
	if parsed is Dictionary and parsed.has("error"):
		var e = parsed["error"]
		if e is Dictionary:
			return String(e.get("message", JSON.stringify(e)))
		return String(e)
	return fallback.left(200)


func _ok(code: int, data) -> Dictionary:
	return {"ok": true, "code": code, "data": data, "error": ""}


func _err(code: int, message: String) -> Dictionary:
	return {"ok": false, "code": code, "data": null, "error": message}
