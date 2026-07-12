class_name CountryKits
extends RefCounted

## 16-nation roster (single-elimination bracket).
## Each country has a home + away kit {primary, secondary, number} and a flag.
## COLOURS ARE STARTER VALUES — tune them freely, this is the single source of truth.
const KITS := {
	"Croatia": {
		"flag": "res://assets/textures/ui/countries/hr.png",
			"code": "CRO",
		"home": {"primary": Color("e1121a"), "secondary": Color("ffffff"), "number": Color("101418")},
		"away": {"primary": Color("14235c"), "secondary": Color("ffffff"), "number": Color("ffffff")},
	},
	"Brazil": {
		"flag": "res://assets/textures/ui/countries/br.png",
			"code": "BRA",
		"home": {"primary": Color("ffdf00"), "secondary": Color("009c3b"), "number": Color("14235c")},
		"away": {"primary": Color("2a2f8f"), "secondary": Color("ffffff"), "number": Color("ffffff")},
	},
	"Germany": {
		"flag": "res://assets/textures/ui/countries/de.png",
			"code": "GER",
		"home": {"primary": Color("ffffff"), "secondary": Color("111111"), "number": Color("111111")},
		"away": {"primary": Color("1a1a1a"), "secondary": Color("d00000"), "number": Color("ffffff")},
	},
	"France": {
		"flag": "res://assets/textures/ui/countries/fr.png",
			"code": "FRA",
		"home": {"primary": Color("1a2a6c"), "secondary": Color("ffffff"), "number": Color("ffffff")},
		"away": {"primary": Color("ffffff"), "secondary": Color("1a2a6c"), "number": Color("1a2a6c")},
	},
	"Italy": {
		"flag": "res://assets/textures/ui/countries/it.png",
			"code": "ITA",
		"home": {"primary": Color("0066b3"), "secondary": Color("ffffff"), "number": Color("ffffff")},
		"away": {"primary": Color("ffffff"), "secondary": Color("0066b3"), "number": Color("0066b3")},
	},
	"Spain": {
		"flag": "res://assets/textures/ui/countries/es.png",
			"code": "ESP",
		"home": {"primary": Color("c60b1e"), "secondary": Color("12203f"), "number": Color("ffd400")},
		"away": {"primary": Color("12203f"), "secondary": Color("ffd400"), "number": Color("ffd400")},
	},
	"England": {
		"flag": "res://assets/textures/ui/countries/gb-eng.png",
			"code": "ENG",
		"home": {"primary": Color("ffffff"), "secondary": Color("14235c"), "number": Color("14235c")},
		"away": {"primary": Color("c8102e"), "secondary": Color("ffffff"), "number": Color("ffffff")},
	},
	"Argentina": {
		"flag": "res://assets/textures/ui/countries/ar.png",
			"code": "ARG",
		"home": {"primary": Color("6cace4"), "secondary": Color("ffffff"), "number": Color("0a1a4a")},
		"away": {"primary": Color("0a1a4a"), "secondary": Color("6cace4"), "number": Color("ffffff")},
	},
	"Netherlands": {
		"flag": "res://assets/textures/ui/countries/nl.png",
			"code": "NED",
		"home": {"primary": Color("f36c21"), "secondary": Color("111111"), "number": Color("111111")},
		"away": {"primary": Color("1a2a5c"), "secondary": Color("f36c21"), "number": Color("ffffff")},
	},
	"Portugal": {
		"flag": "res://assets/textures/ui/countries/pt.png",
			"code": "POR",
		"home": {"primary": Color("d00027"), "secondary": Color("006600"), "number": Color("ffffff")},
		"away": {"primary": Color("ffffff"), "secondary": Color("d00027"), "number": Color("d00027")},
	},
	"Belgium": {
		"flag": "res://assets/textures/ui/countries/be.png",
			"code": "BEL",
		"home": {"primary": Color("e30613"), "secondary": Color("111111"), "number": Color("ffd700")},
		"away": {"primary": Color("ffffff"), "secondary": Color("111111"), "number": Color("111111")},
	},
	"USA": {
		"flag": "res://assets/textures/ui/countries/us.png",
			"code": "USA",
		"home": {"primary": Color("ffffff"), "secondary": Color("0a2240"), "number": Color("0a2240")},
		"away": {"primary": Color("0a2240"), "secondary": Color("bd1e2c"), "number": Color("ffffff")},
	},
	"Japan": {
		"flag": "res://assets/textures/ui/countries/jp.png",
			"code": "JPN",
		"home": {"primary": Color("001e62"), "secondary": Color("ffffff"), "number": Color("ffffff")},
		"away": {"primary": Color("ffffff"), "secondary": Color("001e62"), "number": Color("001e62")},
	},
	"Mexico": {
		"flag": "res://assets/textures/ui/countries/mx.png",
			"code": "MEX",
		"home": {"primary": Color("006341"), "secondary": Color("ffffff"), "number": Color("ffffff")},
		"away": {"primary": Color("1a1a1a"), "secondary": Color("ce1126"), "number": Color("ffffff")},
	},
	"Denmark": {
		"flag": "res://assets/textures/ui/countries/dk.png",
			"code": "DEN",
		"home": {"primary": Color("c8102e"), "secondary": Color("ffffff"), "number": Color("ffffff")},
		"away": {"primary": Color("ffffff"), "secondary": Color("c8102e"), "number": Color("c8102e")},
	},
	"Sweden": {
		"flag": "res://assets/textures/ui/countries/se.png",
			"code": "SWE",
		"home": {"primary": Color("ffcd00"), "secondary": Color("006aa7"), "number": Color("006aa7")},
		"away": {"primary": Color("003366"), "secondary": Color("ffcd00"), "number": Color("ffcd00")},
	},
}


## Returns the {primary, secondary, number} dict for a country + variant ("home"/"away").
static func get_kit(country: String, variant: String = "home") -> Dictionary:
	if not KITS.has(country):
		push_warning("Unknown country '%s' — falling back to Croatia." % country)
		country = "Croatia"
	var entry: Dictionary = KITS[country]
	return entry.get(variant, entry["home"])


## 3-letter code for HUD/scoreboard display (e.g. "CRO").
static func get_code(country: String) -> String:
	if not KITS.has(country):
		return "???"
	return KITS[country].get("code", "???")


## True when two primary colours are too similar to tell teams apart.
static func colors_clash(a: Color, b: Color) -> bool:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	var dist := sqrt(dr * dr + dg * dg + db * db)
	return dist < 0.35  # tweak threshold to taste


## Picks kits for a match: home team wears home; away team switches to its
## away kit if the two home primaries would clash. Returns {"home": kit, "away": kit}.
static func resolve_match(home_country: String, away_country: String) -> Dictionary:
	var home_kit := get_kit(home_country, "home")
	var away_kit := get_kit(away_country, "home")
	if colors_clash(home_kit["primary"], away_kit["primary"]):
		away_kit = get_kit(away_country, "away")
	return {"home": home_kit, "away": away_kit}
