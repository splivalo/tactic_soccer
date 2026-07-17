# scripts/game — logika igre + autoload singletoni

| Fajl              | Što radi                                                          |
|-------------------|---------------------------------------------------------------------|
| `board.gd`        | 7×10 mreža — konstante, `grid_to_world`, `half_of_row`.            |
| `match_state.gd`  | Čista logika pravila (combo, move, kartoni, offside…) — bez čvorova, bez 3D. |
| `formations.gd`   | Fiksni default raspored igrača (koristi se dok nema pravog placementa/protivnika). |
| `game_flow.gd`    | Autoload — koji je ekran otvoren + podaci proslijeđeni između ekrana. |
| `settings.gd`     | Autoload — glasnoća/vibracija, sprema u `user://settings.cfg`.     |
| `player_rig.gd`   | Kontroler animacije po figuri (jedini fajl ovdje koji ZNA za 3D — animira ono što `main.gd` pozicionira). |

`match_state.gd` je čista logika (ne zna ništa o 3D modelima, samo o mreži i pravilima) — `main.gd` je vizualni sloj koji je čita/prikazuje i okida Mixamo animacije preko `player_rig.gd`.
