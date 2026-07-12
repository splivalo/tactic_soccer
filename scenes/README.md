# scenes — Godot scene (vizualni sloj)

Plosnato — scene idu direktno ovdje (osim `ui/`):

| Ovdje                | Što ide                                                          |
|----------------------|------------------------------------------------------------------|
| `main.tscn` (root)   | Scena samog meča (stadion + kamera + svjetlo). Više NIJE `run/main_scene` — sad je to `ui/splash_screen.tscn`, meč se pokreće preko `GameFlow.goto(Screen.MATCH)`. |
| `stadium.tscn`       | Inherited Scene iz `stadium.glb` (arena+golovi+teren+linije).   |
| `player.tscn`        | Scena figurice: `player.glb` + broj + AnimationPlayer/Tree.     |
| `ui/`                | Izbornici, tok ekrana i **HUD (na kraju)**: `splash_screen.tscn` → `team_select.tscn` → `formation_setup.tscn` (trenutno stub) → `main.tscn`. Placeholder layout — slobodno redizajnirati u editoru, skripte u `scripts/ui/` diraju samo `unique_name_in_owner` čvorove. |

Pravilo: scene koriste asete iz `assets/` i logiku iz `scripts/game/`.
Sirove `.glb`/`.fbx` NE uređujemo — radimo Inherited Scene ovdje.
