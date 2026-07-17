# scenes — Godot scene (vizualni sloj)

Plosnato — scene idu direktno ovdje (osim `ui/`):

| Ovdje                    | Što ide                                                          |
|--------------------------|------------------------------------------------------------------|
| `main.tscn` (u root-u projekta, ne `scenes/`) | Scena samog meča (stadion + kamera + HUD). Nije `run/main_scene` — to je `ui/splash_screen.tscn`; meč se pokreće preko `GameFlow.goto(Screen.MATCH)`. Rana faza te iste scene je i postavljanje formacije (vidi `main.gd::_start_placement`) — nema zasebnog "formation setup" ekrana. |
| `player_rigged.tscn`     | Animirana figurica (Mixamo rig) — `main.gd`'s `player_scene` pokazuje na ovo, ne na stari statični `player.glb`. |
| `selection_indicator.tscn` | Vizualni marker za odabranu figuru/ćeliju.                    |
| `ui/`                    | Izbornici, tok ekrana i HUD: `splash_screen.tscn` → `team_select.tscn` → `main.tscn`. Placeholder layout — slobodno redizajnirati u editoru, skripte u `scripts/ui/` diraju samo `unique_name_in_owner` čvorove. |

Pravilo: scene koriste asete iz `assets/` i logiku iz `scripts/game/`.
Sirove `.glb`/`.fbx` NE uređujemo — radimo Inherited Scene ovdje.
