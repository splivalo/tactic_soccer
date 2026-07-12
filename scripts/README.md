# scripts — sav GDScript kod

| Folder     | Što ide                                                                                          |
|------------|---------------------------------------------------------------------------------------------------|
| `game/`    | **Čista logika, bez vizuala**: `board.gd`, `formations.gd`, `match_state.gd` (pravila, potezi, kartoni, zaleđe), `game_flow.gd` (autoload — tok ekrana + odabrana strana/država). |
| `data/`    | Podaci/definicije: `country_kits.gd` (dresovi 16 reprezentacija), `player_appearance.gd` (boje kita + kosa + broj). |
| `ui/`      | Kontroleri ekrana za `scenes/ui/` (splash, odabir momčadi, formacija, HUD) — čitaju/pišu `GameFlow`, izgled ostaje u `.tscn`/editoru. |
| `visuals/` | Vizualni efekti (`board_fx.gd` i sl.) — čvorovi/shaderi, bez pravila igre.                        |
| `tests/`   | Headless testovi (`test_match.gd`, `test_shader.gd`) — `godot --headless -s res://scripts/tests/<ime>.gd`. |

`main.gd` (u rootu) je vizualni sloj meča: čita `MatchState`, gradi/animira
teren i figure, prosljeđuje input. Nova pravila idu u `game/match_state.gd`,
ne u `main.gd`.

Sva pravila su opisana u `rules/igra_pravila.md`, sažeta u `docs/GAME_DESIGN.md`.
