# assets/models — 3D grafika (plosnato)

Malo je fajlova, pa **bez podfoldera** — sve `.glb` ide direktno ovdje.
Preporuka format: **`.glb`**.

Realno imamo ~3 modela:

| Fajl                       | Sadržaj                                                        |
|----------------------------|----------------------------------------------------------------|
| `stadium.glb`              | Arena + stolice + **golovi** + **teren (šahovnica)** + **linije**, sve kao **odvojeni imenovani objekti** unutar istog exporta. |
| `ball.glb`                 | Lopta.                                                          |
| `player.glb`               | **Jedan** lik igrača. Boju dresa mijenja kod (`player_appearance.gd`) po državi (light/dark kit). |
| `goalkeeper.glb` *(opc.)*  | Ako golman treba drugu odjeću. Inače koristimo istog `player.glb` i samo mijenjamo skin/boju u Godotu. |

## Odvojeni dijelovi = node-ovi, ne fajlovi
Dijelovi su odvojeni objekti u Blenderu, ali izlaze u **jedan `stadium.glb`**.
Godot ih uveze kao zasebne child node-ove. **Stvarna imena u trenutnom modelu:**
`field`, `field_lines`, `arena`, `fence`, `banner`, `seats`,
`goal1_frame`, `goal2_frame`, `goal1_net`, `goal2_net`, `reflectors`.
Svakom pristupaš iz koda po imenu (npr. sakriti liniju, tint terena).

## Ključno za teren (matematika!) — POTVRĐENO
Node `field` (šahovnica) poklapa se s logičkom mrežom **7×10** iz `scripts/game/board.gd`:
- Izmjereno: **7.0 (X) × 10.0 (Z)**, gornja ploha **Y = 0.2322**, centar na (0,0,0).
- `board.gd`: `TILE_SIZE = 1.0`, `SURFACE_Y = 0.2322` (figurice stoje na toj visini).
- Ako promijeniš model i skala se razlikuje → `main.gd` to ispiše (`GRID: ... MISMATCH`)
  pa tuniramo konstante. Sirovi `.glb` **ne diramo**.

`player.glb`: jedan node `Player`, materijali `primary`, `secondary`, `hair`, `skin`,
`eyes`, `number_front`, `number_back`, `shoes`, `shoes_sole`. Bez rig-a/animacija (Mixamo kasnije).

## Import
1. Prevuci `.glb` ovdje (Godot auto-uvozi).
2. Klik → **Import** tab → provjeri skalu → desni klik → **New Inherited Scene** za proširenje.
3. Inherited scene spremaj u `scenes/` (npr. `scenes/stadium.tscn`, `scenes/player.tscn`).

> `Soccer Pass.fbx.unwrap_cache` = ostatak ranijeg importa, može ostati.
