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
- [x] **Žuti/crveni karton** — ~~prvotna verzija (ISTA figurica na ISTO polje kao zadnji put)~~ **zamijenjena** (2026-07-09) nakon dekompilacije originalne igre iz 2006 (`.jar`, ne samo screenshotovi): konačno, izvorom-potvrđeno pravilo je **blizina novog šuta (Chebyshev ≤1) posljednjoj poziciji figurice koja je odigrala tvoj tim zadnji ČISTI šut**, bez obzira koja figurica sad puca — hvata i "naizmjenično 1,2,1,2 blizu istog mjesta" rupu koju je stara verzija propuštala. ~~Referenca se briše ako se ta figurica pomakne prije novog šuta, ili nakon svakog prekršaja (svježi start). Zadržavanje lopte među svojim figuricama je uvijek legalno.~~ **Ovaj cijeli "zadržavanje lopte" okidač ZAMIJENJEN** (2026-07-21) kontestiranim 50-50 duelom pri PREUZIMANJU lopte — vidi `docs/CHANGELOG.md` 2026-07-21. Eskalacija ostaje: 1. prekršaj = žuti, 2.+ = crveni + odmah obavezno uklanjanje. Crveni karton uvodi fazu `Phase.REMOVE` — igrač tapne koju svoju figuricu izbacuje (`MatchState.remove_figure`, `_remove_tap` u main.gd), troši mu potez. Kartoni traju cijelu partiju.
- [x] **Autogol** (2026-07-13) — u ovom modelu lopta u mrežu dolazi samo ispucavanjem, pa nema kompleksne "korner" geometrije iz papirnatih pravila (dodavanje golmanu uvijek stane NA golmana, ne prođe pored njega). Zrcalna grana postojeće provjere gola u `MatchState.execute_combo`: ispucavanje u VLASTITI gol (`is_own_goal_cell`) → protivnik zabija, tim koji je primio kickoffa. `res["own_goal"]` zastavica; gol-kinematika (kamera + slow-mo + golmanov pad) radi automatski. Test: `scripts/tests/test_autogol.gd`.
- [ ] HUD: rezultat/kartoni/tko je na potezu (Faza 7)
- [ ] HUD: prikaz žuti/crveni karton po timu (status ikone/boje)
- [ ] HUD: naznaka koliko je tim "blizu" kartona ako je izvedivo (npr. highlight kontestiranih 50-50 ćelija i van poteza, ne samo dok se pomak bira — vidi `MatchState.is_contested_recovery`)
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

## Faza 8 — Online multiplayer (odlučeno 2026-07-29, vidi `GAME_DESIGN.md` §11)
> Firebase RTDB + Anonymous Auth, REST+SSE bez plugina, sinkroniziraju se POTEZI (append-only log)
> a ne stanje. Redoslijed je namjeran: **B prije C** jer se ne isplati trošiti vrijeme na kamere
> dok se ne zna radi li mreža uopće; **C prije D** jer je lista igrača koja te ubaci u meč s
> krivom perspektivom gora nego da liste nema.

**A — temelj** (samostalno, odmah kaže radi li Firebase iz Godota)
- [ ] Firebase projekt: Anonymous Auth + RTDB (europe-west1) — *traži korisnikov Google račun*
- [ ] Uključiti auto-cleanup anonimnih računa (30 dana neaktivnosti) — čisti testne račune sam;
      bezopasno DOK UID ne nosi ništa trajno, vidi uvjet u `GAME_DESIGN.md` §11
- [x] **Security rules postavljene ODMAH**, ne u test modeu — `firebase/database.rules.json`
      (verzionirano u repou). Prvotno su bile planirane za fazu E; korisnik je s pravom pitao
      zašto ne odmah kad se ionako jednako lako mijenjaju — a "zaključat ću kasnije" se ne
      ispuni, dok database URL ionako putuje u APK-u. Doseg i RTDB gotcha o nasljeđivanju
      `.write` s roditelja objašnjeni u komentaru samog fajla.
- [x] Config fajl s database URL + Web API key (NISU tajne — ionako se šalju u APK-u; sigurnost
      dolazi od database rules, ne od skrivanja ključa) — `scripts/net/net_config.gd`
- [x] `Net` autoload (`scripts/net/net.gd`): anonimna prijava + RTDB REST. Refresh token se čuva u
      `user://net_auth.cfg` da UID bude STABILAN kroz pokretanja — bez toga svaki start pravi novi
      anonimni račun. Svaki poziv je korutina koja vraća `{ok, code, data, error}`.
- [x] `scripts/tests/test_net.gd` — end-to-end protiv ŽIVE baze: prijava, upis/čitanje, serverski
      timestamp, te **dva namjerna pokušaja koja pravila MORAJU odbiti** (nepoznato polje, pisanje
      u tuđi zapis). Prošlo 10/10, oba odbijanja vratila 401 → pravila su živa.
- [ ] SSE stream (`HTTPClient`, realtime push) — treba tek u fazi B za sobu i poteze; lista igrača
      se namjerno dohvaća na zahtjev, ne streama
- [x] Ime igrača: upisuje se **na samom Online ekranu**, prvi put kad zatreba (`Settings.player_name`
      → `settings.cfg`, pa objava na `/players/{uid}`). Odstupanje od prvotnog plana: polje u
      `SettingsModal` je izostavljeno jer nitko ne ide u postavke prije nego tapne Online — ondje
      bi ga tek trebalo tražiti. "Promijeni ime" gumb stoji uz listu.
- [x] Izbornik: **`OnlineButton` odvojen od hot-seata** (`main_menu.tscn`). Dotad je JEDAN gumb
      pisao "Online game" a vodio na lokalni hot-seat — zato je pokušaj online igre tražio odabir
      države za drugog igrača. Stari gumb sad piše "Two players (1 device)".
- [x] `scenes/ui/online_screen.tscn` + `scripts/ui/online_screen.gd`: prijava → objava sebe →
      heartbeat (60 s) → popis ostalih, sa **filtriranjem** zapisa starijih od 150 s. Popis se
      dohvaća na zahtjev (gumb "Osvježi"), namjerno se NE streama. Izgled je placeholder kao i
      ostali ekrani u `scenes/ui/` — za urediti u editoru.
- [x] *Gotovo kad:* dva uređaja vide da se međusobno pojavljuju i nestaju — **potvrđeno na
      desktopu + mobu 2026-07-30**. Usput otkriveno: Android build je imao
      `permissions/internet=false` u export presetu, pa je prijava padala s `can't resolve host`
      dok je desktop radio. Mora se kvačiti **u editoru** (Project → Export → Android →
      Permissions), jer editor drži presete u memoriji i prepisuje ručnu izmjenu fajla.

**A+ — pozivi (dodano nakon što se lista pokazala lakšom nego kod; vidi bilješku uz fazu B)**
- [x] Gumb "Invite" u svakom redu liste; igrač koji je zauzet dobije **onemogućen** gumb s
      natpisom "In match" (informacija je bolja od gumba kojeg nema)
- [x] Poziv → protivnik dobije Accept/Decline → oboje završe u istoj sobi. Nitko se ne ubacuje u
      igru bez pristanka, a nepotvrđen poziv istekne sam nakon 60 s
- [x] Soba se stvara **`PATCH`-em po poljima, ne `PUT`-om cijele sobe** — pravila namjerno ne daju
      `.write` na `/rooms/$code` jer bi to u RTDB-u dalo i sve ispod, uključujući `turns`.
      `test_net.gd` to i **provjerava**: PATCH prolazi, PUT cijele sobe mora biti odbijen
- [x] `test_net.gd` proširen na sobe i pozive — 18/18 protiv žive baze, uključujući da je tuđi
      inbox poziva nečitljiv

**B — soba preko koda + meč se stvarno sinkronizira** (~70% posla)
- [x] Izbornik: **hot-seat uklonjen**, ostaju dva načina — Single player i Online (odluka
      2026-07-30; dva igrača na jednom mobitelu su rubni slučaj, gumb je samo dodavao izbor bez
      vrijednosti). Logika hot-seata u `main.gd`/`MatchState` nije dirana, nestao je samo ulaz.
- [x] **Država se bira PRIJE uparivanja**, lokalno, i pamti se — ne u sobi. Inače bi svaki meč
      počinjao s dva čekanja (država, pa formacija). `team_select` je dobio online-način:
      jedan prolaz, biraš samo sebe.
- [x] Tok je **Izbornik → države (Back/Next) → lista igrača**, isti oblik kao Single player
      (izbornik → težina → države → meč). Kratko je postojao zaseban "Country" gumb na Online
      ekranu; maknut jer je nedosljedan s AI tokom i jer je taj ekran ionako imao previše gumba.
      Back s liste vraća na države — tako se država i mijenja, bez ijednog dodatnog gumba.
- [x] **Duplikati država dopušteni**, ista država → gost u alternativnom dresu (host zadržava
      domaći). Determinističko, bez dogovora. Time **živi lobby za odabir države OTPADA** — bio je
      planiran ovdje, ali koordinacija više nema svrhu. Vidi `GAME_DESIGN.md` §11.
- [ ] Create room / join by code (`KX7P2M`)
- [ ] Formacija se isto pamti kao postavka i ponovno koristi (tko je ne postavi → `Formations`
      default), da meč kreće odmah po prihvaćanju poziva
- [ ] HUD: ime igrača umjesto kratice države (samo online) — `hud.gd::set_team` piše u `name_label`,
      `set_turn` čita isti label pa se footer povuče sam. **Skratiti (~8-10 + `…`) I OČISTITI**
      (prijelomi retka, kontrolni znakovi) — tekst dolazi od stranca i ide ravno u HUD
- [ ] Sudar boja između različitih država (Hrvatska–Peru) — traži usporedbu kitova, ne samo
      provjeru jednakosti; za sad se hvata samo identična država
- [x] **Sloj za sinkronizaciju poteza gotov i dokazan** — `scripts/net/net_match.gd` (append-only
      log, slanje/primanje/redoslijed) + `scripts/net/net_action.gd` (žični format + JEDNO mjesto
      koje akciju primjenjuje i time je validira). `test_net_match.gd` glumi **dva klijenta s dva
      odvojena anonimna računa u istom procesu** i odigra prave poteze preko žive baze: 27/27.
      Ključna tvrdnja koju testira: nakon svake razmjene oba `MatchState`-a imaju isti red, fazu,
      poziciju lopte i rezultat. To je cijeli smisao "šaljemo poteze, ne stanje".
- [x] Validacija protivnikove akcije kroz vlastiti `MatchState` (`NetAction.apply`) — ilegalna
      akcija se odbija i NIŠTA ne mijenja; prepisivanje već odigranog indeksa vraća 401
- [x] Replay iz loga: svjež klijent odigra log od nule i završi u istoj poziciji kao igrači —
      time je reconnect riješen istim kodom kojim se prati normalna igra
- [ ] **Ožičiti u `main.gd`**: mrežni protivnik kao treći izvor inputa uz tap i AI, po uzoru na
      `_is_ai_turn()`/`_maybe_ai_turn()` (main.gd:2195) — primljena akcija ide kroz iste
      `_do_combo`/`_apply_move`/`_remove_at`, lokalna se šalje. Treba zastavica da se primijenjena
      mrežna akcija ne pošalje natrag kao vlastita.
- [x] **Traženje protivnika je OVERLAY na terenu, ne zaseban ekran** (odluka 2026-07-30). Tok:
      izbornik → države → teren (slažeš formaciju) → overlay s listom → protivnik prihvati →
      overlay nestane i meč kreće na ploči koju već gledaš. Nema promjene scene ni drugog
      učitavanja. `Screen.ONLINE` je zato uklonjen iz `GameFlow`; overlay se instancira iz koda
      (`main.gd::_show_online_overlay`) da se ne dira `main.tscn`. Ekran je dobio prozirni scrim
      umjesto pozadinske slike.
- [x] Predaja iz sobe u meč: `GameFlow.online_room` / `online_opponent_name` / `online_is_host`,
      strane se dodjeljuju (host = HomeTeam) i države upisuju prije `_start_coin_toss()`
- [x] **Dresovni sudar NE treba novi kod** — `CountryKits.resolve_match` ga već rješava, i to
      usporedbom boja a ne samo država, pa pokriva i Hrvatsku–Peru. Ranija bilješka da je to
      budući posao bila je netočna. Dovoljno je da host bude HomeTeam.
- [x] **Zrcaljenje formacije za gosta** (`main.gd::_mirror_formation`) — formacija se slaže PRIJE
      nego se zna koja si strana, pa je gost složi na domaćoj polovici. Rotacija za 180° premješta
      je na gostujuću polovicu čuvajući oblik; kako je i kamera gosta okrenuta, njemu izgleda
      identično onome što je postavio.
- [ ] Stegnuti pravila za polja sobe (`state`, `ready`, `country`) — sad traže samo prijavu, jer
      bi prije implementacije to bilo pogađanje; vidi doseg u `firebase/database.rules.json`
- [ ] **Popraviti `host` / `created_at` iz write-once u "vlasnik smije prepisati/obrisati"** —
      trenutno `".write": "auth != null && !data.exists()"` znači da se soba NIKAD ne može
      obrisati, pa napuštene sobe ostaju zauvijek. Bezopasno po veličini (~desetak bajtova), ali
      je stvarna greška u dizajnu pravila. `test_net.gd` tu rupu **namjerno tvrdi kao test**, pa
      će pući čim se popravi — to je znak da se test ažurira, ne da je nešto slomljeno.
- [ ] Zamijeniti pollanje (3 s) SSE streamom za poziv i sobu — lista igrača namjerno OSTAJE na
      dohvat-na-zahtjev zbog kvadratnog rasta prometa
- [ ] **Provjeriti ima li `MatchState` slučajnosti u meč-putu** → ako ima, zajednički seed iz sobe
- [ ] *Gotovo kad:* dva uređaja odigraju punu partiju preko mreže

**C — perspektiva + paralelne formacije**
- [ ] Kamera rotirana 180° za Away igrača (logika se NE dira — vidi §11 zašto)
- [ ] Zamjena grbova u HUD-u
- [ ] Zrcaljenje gol-cinematike (Cam A/Cam B) i reprizne top-down kamere
- [ ] Obojica postavljaju formaciju istovremeno + "čekam protivnika..." stanje
      (`_start_placement` sad postavlja samo svoju stranu i pretpostavlja fiksni `Formations`)

**D — lista igrača + pozivi**
- [ ] Presence preko **heartbeata** (`last_seen` svakih 60 s, stale nakon 150 s) + status uz ime
      (Slobodan / U meču). NE `onDisconnect()` — to je realtime-SDK funkcija koje na REST API-ju
      nema, vidi ispravak u `GAME_DESIGN.md` §11
- [ ] Poziv → prihvati/odbij s timeoutom (tap NIKAD ne ubacuje protivnika u meč izravno)
- [ ] Tag protiv kolizija imena (`Marko#7K2`)
- [ ] Filter psovki + gumb "Prijavi" (Play Store zahtjev, ne kozmetika)
- [ ] `limitToFirst` + osvježavanje na zahtjev, NE trajni stream cijele liste (trošak)
- [ ] Odspoji se kad app ode u pozadinu (100 istovremenih konekcija je zid na Sparku)

**E — otpornost**
- [ ] Reconnect kroz replay append-only loga
- [ ] Protivnik otišao: "napustio je meč — uzmi pobjedu / čekaj"
- [ ] Istek poteza po **serverskom** vremenu (`deadline_at`), ne lokalnom satu — inače driftaju
- [ ] Provjeriti stabilnost SSE streama na Androidu pri prelasku u pozadinu

## Backlog / ideje
- [x] ~~Online multiplayer?~~ → odlučeno, vidi Fazu 8 gore
- [x] ~~AI protivnik?~~ → implementirano, vidi `GAME_DESIGN.md` §10
- [ ] Tutorial / prikaz pravila u igri
- [ ] Povezivanje računa (anonimni → Google/email) — **obavezno PRIJE** bilo kakve trajne
      progresije vezane uz UID (statistika, rang, prijatelji, otključavanja), jer je auto-cleanup
      anonimnih računa uključen; vidi `GAME_DESIGN.md` §11
