# TACTIC SOCCER — Game Design Dokument (GDD)

> Živi dokument. Nadopunjavamo ga kako igra raste. Kad se nešto odluči — ide ovdje.
> Pravila igre (detaljno, sa slikama) su izvor istine u [`rules/igra_pravila.md`](../rules/igra_pravila.md).

---

## 1. Pregled
- **Žanr:** turn-based (na poteze) taktička nogometna igra.
- **Igrači:** 2 igrača (za sad hot-seat na istom uređaju).
- **Platforma:** mobitel, **portret / okomito**. (Kratko isprobana PC/landscape varijanta 2026-07-08, vraćeno na portret jer se brojevi/UI bolje vide — vidi `docs/CHANGELOG.md`. Kod je platformski neovisan pa je povratak na landscape kasnije lak.)
- **Engine:** Godot 4.6, mobile renderer, Jolt physics.
- **Cilj partije:** dati gol; igra se na 2 dobivene partije / 2 gola (ili po dogovoru).

## 2. Ploča i figurice
- **Teren:** šahovnica **7 × 10 polja** (7 širina X, 10 dubina Z). Po njoj se vrti sva matematika.
  Originalna igra iz 2006. (Football Mania, DiviCo) koristi 7×8 — potvrđeno dekompilacijom
  (2026-07-09). Zadržavamo 7×10 kao svjesnu vlastitu varijaciju (dulji teren, više prostora
  za taktiku), ne grešku — vidi `docs/CHANGELOG.md`.
- **Figurice:** svaki igrač ima **5 figurica + 1 golman**.
- **Koordinate:** logička mreža u `scripts/game/board.gd`; 1 polje = 1 world unit, centar na (0,0,0).
  Uvezeni 3D teren mora se poklapati s ovom mrežom.

## 3. Tijek poteza (sažetak — puna pravila u rules/)
1. **Dodavanje / povezivanje** — lopta se kreće SAMO ravno (horizontalno/vertikalno/dijagonalno),
   1–∞ polja, bez krivudanja. Neograničen broj povezivanja dok postoji ravna putanja između figurica.
   Golman smije sudjelovati ako je na putanji (pazi na autogol — vidi pravila).
2. **Ispucavanje** — zadnja figurica MORA ispucati loptu (h/v/d), staje gdje želi, ne na zauzeto polje.
3. **Pomicanje** — igrač pomakne jednu bilo koju figuricu za **1 polje**, ne na polje s figuricom/loptom.

**Preuzimanje lopte:** moguće samo ako je lopta 1 polje (od 8 susjednih) od figurice → figurica staje na loptu.
**Gol:** samo s protivničke polovice. **Zaleđe:** ako su sve protivničke terenske figurice (golman isključen) strogo iza napadača — nema gola. Ako protivnik nema više nijednu terensku figuricu, zaleđe se ne može dogoditi.
**Kartoni (zadržavanje/vrtnja lopte):** prekršaj je kad novi šut sleti unutar 1 polja (Chebyshev) od figurice koja je odigrala tvoj tim posljednji **čisti** (neprekršajni) šut — bez obzira koja figurica sad puca. Referenca se briše ako se ta figurica u međuvremenu pomakne, ili nakon svakog prekršaja. Samo držati loptu među svojim figuricama je uvijek legalno; kažnjava se doslovno vraćanje istom šutu na isto mjesto. 1. prekršaj = žuti karton, 2. = crveni, 3. = obavezno uklanjanje jedne figurice (`Phase.REMOVE`). Kartoni traju cijelu partiju. Pravilo je potvrđeno dekompilacijom izvornog koda originalne igre iz 2006. (vidi `docs/CHANGELOG.md`, 2026-07-09) — ranije verzije ("ista figurica dva puta zaredom", "isto polje kao zadnji put") su odbačene jer su ili prestroge ili propuštaju rupu s naizmjeničnim figuricama.

## 4. Tehnička arhitektura
Odvajamo **logiku** od **prikaza**:
- **Logika** (`scripts/game/`) — ne zna za 3D, samo mreža 7×10 + pravila.
  Predložene datoteke: `board.gd`, `match_state.gd`, `rules.gd`, `piece.gd`, `team.gd`.
- **Prikaz** (`scenes/`) — čita stanje logike, prikazuje figurice/loptu, okida animacije.
- **Podaci** (`scripts/data/`) — `country_kits.gd` (16 reprezentacija), `player_appearance.gd`.

## 5. Grafika (3D) — izvor: Blender, ~3 fajla
Modeli idu **plosnato** u `assets/models/` (bez podfoldera):
- **`stadium.glb`** — arena + stolice + golovi + teren (šahovnica) + linije, sve kao
  **odvojeni imenovani objekti** (`Arena`, `Goal_L`, `Goal_R`, `Pitch`, `Lines`) unutar
  jednog exporta. Podjela živi kao node-ovi u sceni, ne kao zasebni fajlovi/folderi.
- **`ball.glb`** — lopta.
- **`player.glb`** — **jedan** lik. Boju dresa mijenja kod po državi (light/dark kit).
- **`goalkeeper.glb`** *(opcionalno)* — ako golman treba drugu odjeću; inače isti lik + skin swap.

Node `Pitch` mora se poklapati s logičkom mrežom 7×10 (detalji u `assets/models/README.md`).

## 6. Animacije (Mixamo — kasnije)
- Klipovi u `assets/animations/`, spajaju se preko `AnimationLibrary` na model igrača.
- **Kombinacija (pass→shoot) okida animaciju.**
- **Gol:** kamera se spušta i pokazuje akciju atraktivnije + animacija slavlja.
- Skeleton Mixamo klipova mora odgovarati modelu igrača.

## 7. Kamera
- Portret, taktički pogled odozgo/koso na cijelu ploču.
- Kut/kompoziciju/FOV **tunira korisnik u editoru** (Camera3D transform u `main.tscn`). Kod (`_fit_camera` u `main.gd`) samo klizi kameru po toj istoj osi gledanja tako da cijeli teren uvijek stane, na bilo kojem omjeru ekrana — nikad ne mijenja kut.
- Poseban "gol" pogled: spuštanje kamere na akciju (nije još implementirano).
- ⚠️ Pri ručnom upisu `Transform3D(...)` u `.tscn`: Godot zapisuje bazis TRANSPONIRANO (vidi `docs/CHANGELOG.md`, 2026-07-08) — ne upisuj `basis.x, basis.y, basis.z` redom bez transponiranja, ili koristi editor/Transform dijalog umjesto ručnog upisa.

## 8. Zvuk (`assets/audio/`)
- `sfx/`: dodavanje, šut, gol, zvižduk, karton, preuzimanje lopte.
- `music/`: menu, slavlje nakon gola.

## 9. Prezentacija / meta
- 16 reprezentacija, single-elimination bracket (vidi `country_kits.gd`).
- Zastave: `assets/textures/ui/countries/<kod>.png`.
- Brojevi na dresu: `assets/textures/numbers/`.
- **HUD** (`scenes/ui/hud.tscn`): grbovi, skor, kartoni, timer, footer (tko je na potezu).
- **Tok ekrana** (`GameFlow` autoload, `scripts/game/game_flow.gd`): splash →
  glavni izbornik (po uzoru na original iz 2006: 1/2 Player, Options,
  Instructions, Credits, Quit) → odabir momčadi (Player 1=Home, Player 2=Away,
  fiksno) → meč. `run/main_scene` je `scenes/ui/splash_screen.tscn` (ne `main.tscn`).
  Splash je korisnikov vlastiti dizajn (ne dirati izgled); ostali ekrani u
  `scenes/ui/` su namjerno gole placeholder scene (izgled je za urediti u
  editoru). Ručno postavljanje figura (golman pa redom ostali, samo igračeva
  strana) živi kao rana faza unutar SAME meč-scene (`main.gd::_start_placement`),
  ne kao zaseban ekran. Instructions ekran već ima pravi sažetak pravila.

## 10. Otvorena pitanja / odluke za kasnije
- [ ] Online multiplayer ili samo hot-seat?
- [ ] AI protivnik?
- [ ] Točan izgled/uvjeti "zaleđa" u kodu (rub slučajevi).
- [ ] Vizual za brojeve: pravi broj na dresu (numbers PNG) vs. `Label3D` iznad glave.
- [ ] Poklapanje uvezenog terena s logičkom mrežom (skala/origin).

---
*Zadnje ažurirano: 2026-07-09. Uz ovaj dokument idi i [`docs/TODO.md`](TODO.md).*
