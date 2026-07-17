# TACTIC SOCCER — TODO / Checklist

> Označi `[x]` kad je gotovo. Faze idu grubo redom, ali se preklapaju.
> Pravila: [`rules/igra_pravila.md`](../rules/igra_pravila.md) · Dizajn: [`GAME_DESIGN.md`](GAME_DESIGN.md)

## Faza 0 — Setup ✅
- [x] Pravila pročitana i sažeta (GDD)
- [x] Struktura projekta (scenes / scripts / assets / docs) — plosnata
- [x] Game Design Dokument + TODO

## Faza 1 — Import 3D grafike
- [x] Export + import: `stadium.glb`, `ball.glb`, `player.glb`
- [x] Objekti u `stadium.glb`: `field`, `field_lines`, `arena`, `fence`, `banner`, `seats`, `goal1_frame`, `goal2_frame`, `goal1_net`, `goal2_net`, `reflectors`
- [x] **`field` se poklapa s logičkom mrežom 7×10** (7.0×10.0, top Y 0.2322) — potvrđeno headless
- [x] Provjera nasuprot originalu (dekompilacija 2026-07-09): original je 7×8, mi svjesno zadržavamo 7×10 kao vlastitu varijaciju (vidi `GAME_DESIGN.md` §2)
- [x] `scripts/game/board.gd` — grid↔world mapiranje + SURFACE_Y
- [x] `main.gd` učitava stadium + debug mapa polja (70 točkica)
- [x] Player materijali `primary`/`secondary`/`hair` — farbanje radi
- [ ] Stadium/player kao Inherited Scene u `scenes/` (kad krenu izmjene)
- [ ] Brojevi dresa na `number_front`/`number_back` materijale (numbers PNG)

## Faza 2 — Logika igre (`scripts/game/`)
- [x] `board.gd` — mreža 7×10, koordinate, grid↔world
- [x] `board.gd` — ravne putanje (h/v/d): `is_straight`, `cells_between`, `path_clear`, `reachable_from`
- [x] `formations.gd` — početne pozicije 2×(golman+5), svaki na svojoj polovici
- [x] `main.gd` — postavlja 12 figurica na mrežu (kitovi, brojevi, okrenuti) + reach-debug (potvrđeno: 15 polja iz (3,7))
- [ ] `piece.gd` / logički model figurica (team, cell, number) odvojen od 3D čvorova
- [ ] `match_state.gd` — state machine: dodavanje → povezivanje → ispucavanje → pomicanje
- [ ] `rules.gd` — preuzimanje lopte (1 polje), golman/autogol
- [ ] `rules.gd` — zaleđe, gol samo s protivničke strane
- [ ] `rules.gd` — zadržavanje lopte (žuti/crveni karton)
- [ ] Skor, kraj partije (2 gola / 2 partije), reset pozicija

## Faza 3 — Interakcija (touch, portret)
- [x] Lopta (`ball.glb`) na mreži + klik/tap → polje (raycast na teren)
- [x] Klik na loptu → prikaz meta: zeleno = ispucavanje (prazno), plavo = dodavanje suigraču
- [x] Lopta uvijek na PRAZNOM polju (nikad na figurici)
- [x] COMBO: tapneš niz svojih figurica (od one do lopte) + prazno polje → lopta proputuje i stane
- [x] Potez = 2 radnje: COMBO (ako imaš loptu) + MOVE (pomak 1 figurice)
- [x] Golman samo unutar svoja 3 gol-polja; ostali ne smiju u gol (stupci 2,3,4)
- [x] Posjed = figurica do lopte (8 polja) na početku poteza
- [x] Zadržan `SelectionIndicator` (strelice smjerova za pomicanje)
- [x] Gol: ispucavanje u protivnički gol (3 srednja polja) s protivničke polovice → rezultat + reset (primatelj izvodi)
- [x] Pobjeda: `goals_to_win` (default 2) — ispis pobjednika
- [x] **Refactor**: čista logika u `scripts/game/match_state.gd` (bez čvorova); `main.gd` = vizualni sloj; headless test `scripts/tests/test_match.gd` (svi prolaze)
- [x] Vizual: sve oznake (tap/chain/select) sad isti oblik (zaobljeni kvadrat) kao move/shoot polja, samo druge boje; boje + tuning (`fx_*`) sad @export na Main
- [x] Golmani nose poseban GK dres (crno/žuti kod, zeleno/bijeli gost), nikad boje ispolja
- [x] Ne može se ispucati na polje na kojem lopta trenutno stoji
- [x] Promjena mišljenja pri odabiru primatelja (klik na drugog dostupnog igrača umjesto prvog)
- [x] Rewind lanca: klik na već odabranu figuricu (bilo gdje u nizu) skraćuje lanac do nje umjesto petlje (1→2→3→2 nemoguće); `MatchState.rewind()` + test
- [x] **Tap vs Drag sustav** (rješava nedosljednost oko "dvije figurice do lopte u liniji"): TAP uvijek (re)pokreće lanac ili radi rewind; DRAG (uz snap na najbližu metu) je jedini način za dodavanje/ispucavanje. `Board.nearest_cell()` (čisto, testirano) + `_on_press/_on_motion/_on_release` u main.gd.
- [x] Neprekidno povlačenje kroz više figurica (auto-connect čim prst stvarno stigne do mete, bez puštanja) + highlight sad samo mijenja boju (posvjetljenje), ne povećava pločicu.
- [x] **Pravi uzrok "nasumičnog" promašaja klika/dodira nađen i popravljen**: nagnuta kamera + visina figure (~1.45) znači da tap na TIJELO figure (ne bazu) raycasta na ravnu podlogu i pogađa POGREŠNO, udaljenije polje. Popravljeno "cilindar testom" (`Board.ray_vertical_closest`, čisto/testirano) — tap/drag na figuru sad pogađa njen stupac bez obzira gdje na tijelu dotakneš. Primijenjeno posvuda: COMBO tap (`_combo_tap`), MOVE tap (`_move_click`), i drag (`_on_motion`) — sve sad kroz jedinstveni `_resolve_target()`.
- [x] Naknadni bug istog uzroka: drugi tap na već odabranu figuru znao je "procuriti" na susjedno prazno polje (jer se prazna polja provjeravaju ravnom podlogom prije figura) i pomaknuti je tamo. Popravljeno: **figure (cilindar) se uvijek provjeravaju prije praznih polja (ravna podloga)** u `_combo_tap` i `_move_click`.
- [x] Za zauzeta polja `_resolve_target` sad prihvaća pogodak **i** na tijelu figure (cilindar) **i** na pločici na kojoj stoji (ravna podloga) — koji god je bliži.
- [x] **Eksperiment:** drag dodan i za MOVE fazu (pomicanje figure), kao dodatna opcija uz postojeći tap. Press+drag izravno na figuru = "podigni pa spusti" u jednom potezu; ili odaberi tapom pa povuci do cilja. Tap-only i dalje radi nepromijenjeno. **Ako se ne pokaže dobrim u praksi, lako se vraća — samo `_on_motion`/`_on_release`/`_draw_move` diraju.** Treba live test.
- [x] Energetski trag prebačen na shader (garantirano animira, bivši `fx_trail_scroll` bug riješen); dodano biranje dash/dot (`fx_trail_pattern`), emission i rim (`fx_trail_emission`, `fx_trail_rim`), gustoća (`fx_trail_density`), popuna (`fx_trail_fill`) — sve @export na Main
- [x] `scripts/tests/test_shader.gd` — headless provjera da se shader stvarno kompajlira (odvojeno od test_match.gd)
- [x] Isprobana pa **odbačena** PC/landscape platforma (2026-07-08) — vraćeno na mobitel/portret (bolja čitljivost brojeva/UI). Detalji i naučena pouka o Transform3D u `docs/CHANGELOG.md`.
- [x] **Zaleđe**: napadač u zaleđu ako su SVI terenski protivnici (golman isključen — uvijek je na gol-liniji pa bi ga uključivanje učinilo nemogućim) strogo dalje od gola nego on. Gol se ne broji, potez ide dalje normalno. `MatchState.is_offside()` + `offside_line_row()`, testirano.
- [x] **Vizualni prikaz zaleđa na terenu** (ne samo konzola): crtkana linija preko cijele širine terena na redu zadnjeg protivničkog terenskog igrača (kao u originalu iz 2006) + istaknuto polje napadača, sve u `color_offside`. Nestaje nakon `offside_flash_seconds` (default 1.8s). Zaseban `BoardFx` sloj (`_fx_effects`) da se ne briše čim se osvježi tap/drag prikaz.
- [x] **Žuti/crveni karton** — ~~prvotna verzija (ISTA figurica na ISTO polje kao zadnji put)~~ **zamijenjena** (2026-07-09) nakon dekompilacije originalne igre iz 2006 (`.jar`, ne samo screenshotovi): konačno, izvorom-potvrđeno pravilo je **blizina novog šuta (Chebyshev ≤1) posljednjoj poziciji figurice koja je odigrala tvoj tim zadnji ČISTI šut**, bez obzira koja figurica sad puca — hvata i "naizmjenično 1,2,1,2 blizu istog mjesta" rupu koju je stara verzija propuštala. Referenca se briše ako se ta figurica pomakne prije novog šuta, ili nakon svakog prekršaja (svježi start). Zadržavanje lopte među svojim figuricama je uvijek legalno. 1. prekršaj = žuti, 2. = crveni, 3. = obavezno uklanjanje figurice. Trajni ID po figurici (`pieces[cell]["id"]`), `stall_ref_id`/`stall_ref_cell` po timu (`match_state.gd`). Crveni karton uvodi fazu `Phase.REMOVE` — igrač tapne koju svoju figuricu izbacuje (`MatchState.remove_figure`, `_remove_tap` u main.gd), troši mu potez. Kartoni traju cijelu partiju. Testirano (54 checka, uklj. korisnikov originalni protuprimjer + cross-figure slučaj + 3-strike eskalacija + brisanje reference pri pomaku). Detalji rasuđivanja: `docs/CHANGELOG.md` 2026-07-09.
- [x] **Autogol** (2026-07-13) — u ovom modelu lopta u mrežu dolazi samo ispucavanjem, pa nema kompleksne "korner" geometrije iz papirnatih pravila (dodavanje golmanu uvijek stane NA golmana, ne prođe pored njega). Zrcalna grana postojeće provjere gola u `MatchState.execute_combo`: ispucavanje u VLASTITI gol (`is_own_goal_cell`) → protivnik zabija, tim koji je primio kickoffa. `res["own_goal"]` zastavica; gol-kinematika (kamera + slow-mo + golmanov pad) radi automatski. Test: `scripts/tests/test_autogol.gd`.
- [ ] HUD: rezultat/kartoni/tko je na potezu (Faza 7)
- [ ] HUD: prikaz žuti/crveni karton po timu (status ikone/boje)
- [ ] HUD: naznaka koliko je tim "blizu" kartona ako je izvedivo (npr. da li postoji aktivna stalling-referenca)
- [x] Pravila objašnjena igračima izvan HUD-a: `scenes/ui/instructions_screen.tscn` ("Upute" u glavnom izborniku) sadrži sažetak poteza/gola/zaleđa/kartona. HUD tooltip *tijekom* meča (kontekstualan, ne samo statičan ekran) ostaje otvoren za kasnije.
- [x] Vizualni feedback (`scripts/visuals/board_fx.gd`): svijetleća polja (pomak/ispucavanje), prstenovi (tappable figure), energetski trag (lanac)
- [ ] Prikaz putanje/finije animacije (Mixamo) + ni​šan na ispucavanju

## Faza 3.5 — Tok ekrana (splash → meni → odabir → formacija → meč)
- [x] `scripts/game/game_flow.gd` — `GameFlow` autoload: `Screen` enum (SPLASH, MAIN_MENU, TEAM_SELECT, OPTIONS, INSTRUCTIONS, LEGAL, MATCH, WIN_SCREEN, LOSE_SCREEN) + čuva odabranu stranu (`player_side`), države (`home_country`/`away_country`) i postavljenu formaciju (`player_formation`), `goto(Screen)` mijenja scenu (`get_tree().change_scene_to_file`, deferred)
- [x] `scenes/ui/splash_screen.tscn` — **korisnikov vlastiti dizajn** (pozadina, logo, custom font/theme `my_theme_gold.tres`); bilo koji tap/klik/tipka → glavni izbornik. Kod ne dira izgled, samo cilj navigacije.
- [x] `scenes/ui/main_menu.tscn` — po uzoru na izbornik originala iz 2006: 1 Player game (onemogućen dok nema AI), 2 Player game → odabir momčadi, Options, Instructions, Credits (namjerno `flat` gumb, ne ističe se kao ostali), Quit. Layout je placeholder (samo `my_theme_gold.tres` font), za redizajn u editoru.
- [x] `scenes/ui/team_select.tscn` — dva `OptionButton`-a (država za Domaći/Gost, popunjeno iz `CountryKits.KITS`) + prekidač "Ja igram kao: Domaći/Gost" (`player_side`) + Natrag/Dalje
- [x] `scenes/ui/options_screen.tscn`, `instructions_screen.tscn`, `legal_screen.tscn` — dijele isti generički `scripts/ui/info_stub.gd` (naslov + tekst + Natrag). Instructions ima pravi sažetak pravila; Options je "uskoro"; Legal ima TODO placeholder tekst za autora/impressum/licence koji treba urediti izravno u `legal_screen.tscn` (`LegalScreen.body_text`)
- [x] `main.gd` (`_ready`) čita `GameFlow.home_country`/`away_country` ako su postavljeni (prazan string = nepostavljeno → koristi svoj `@export` default), tako da `main.tscn` i dalje radi samostalno pokrenut u editoru
- [x] `run/main_scene` je `splash_screen.tscn`
- [x] Ručno postavljanje figura (golman pa redom ostali, na svoju polovicu) — nije zaseban `formation_setup.tscn` ekran (uklonjen), nego rana faza unutar `main.gd`/`main.tscn` samog (`_start_placement`/`_placement_*`), ponovno koristi već učitanu kameru/teren/HUD. Postavlja se samo IGRAČEVA strana (`GameFlow.player_side`); protivnik i dalje koristi `Formations.home()/away()` dok ne postoji pravi online.
- [ ] Options ekran bez stvarnog sadržaja (zvuk/jezik/kontrole) — čeka te sustave

## Faza 4 — Animacije (Mixamo) + kamera
- [ ] Mixamo idle na figuricama
- [ ] Kombinacija (pass→shoot) okida animaciju
- [ ] Gol: spuštanje kamere + animacija slavlja
- [ ] Sinkronizacija animacije s kretanjem lopte

## Faza 5 — Zvuk
- [ ] SFX: dodavanje, šut, gol, zvižduk, karton
- [ ] Glazba: menu, slavlje

## Faza 6 — Meta / prezentacija
- [ ] 16 reprezentacija + bracket (single-elimination)
- [ ] Zastave u `assets/flags/`
- [ ] Brojevi na dresu
- [ ] Odabir tima / kita (clash → away kit)

## Faza 7 — HUD (na kraju) `scenes/ui/`
- [ ] Skor + tko je na potezu
- [ ] Kartoni, imena timova
- [ ] Menu / pobjeda ekran

## Backlog / ideje
- [ ] Online multiplayer?
- [ ] AI protivnik?
- [ ] Tutorial / prikaz pravila u igri
