# scripts/game — logika igre (bez vizuala)

Prazno za sad. Ovdje ide state machine poteza i pravila iz `rules/igra_pravila.md`:
`board.gd`, `match_state.gd`, `rules.gd`, `piece.gd`, `team.gd`.

Cilj: ova logika ne zna ništa o 3D modelima — samo o mreži 7×10 i pravilima.
Scena (`scenes/`) je vizualni sloj koji je čita i prikazuje + okida Mixamo animacije.
