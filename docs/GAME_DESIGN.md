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
3. **Pomicanje** — igrač pomakne jednu bilo koju figuricu **neograničeno daleko u ravnoj liniji**
   (h/v/d), dok ne udari u prvu prepreku (drugu figuricu, loptu, ili rub terena) — ista gramatika
   kretanja kao i lopta (`Board.DIRS`, `MatchState.move_targets`). Golman i dalje smije stati SAMO
   na svoja 3 gol-polja. **Promjena od izvornog "1 polje"** (2026-07-1x, vidi `docs/CHANGELOG.md`):
   bez nje je tim koji nema loptu praktički nikad nije mogao stići do nje.

**Svaki tim ima TOČNO 2 akcije po redu** — ovo je temeljni izum koji drži igru poštenom bez obzira
tko trenutno ima loptu:
- **Ako tim VEĆ ima loptu** na početku svog reda: 1) combo (dodavanje→ispucavanje, koliko god
  povezivanja) je 1. akcija, 2) obavezni pomak jedne figurice nakon (neuspio) šuta je 2. akcija
  (`Phase.MOVE`, `moves_left = 1`).
- **Ako tim NEMA loptu**: kreće u **reaktivnu MOVE fazu** s **2 raspoloživa poteza**
  (`moves_left = 2`, `_move_is_reactive = true`) — dovoljno da dovede DRUGU figuricu u igru, ili
  istu figuricu zaobiđe prepreku u "L" (2 poteza, obrambeno pozicioniranje, BEZ šuta). Ako prvi od
  ta 2 poteza već dovede figuricu do lopte, red se odmah nadograđuje u pravi `Phase.COMBO` na toj
  istoj figurici (potez + šut = 2 akcije, isto kao napadač) — drugi rezervni potez se ne troši
  uzalud. **Ali** ako se lopta dosegne tek **drugim (zadnjim)** reaktivnim potezom, NEMA
  nadogradnje — red se normalno završava (potez + potez = već 2 akcije potrošene, treći bonus-šut
  se nikad ne dodjeljuje). Vidi `MatchState.do_move`/`execute_combo`, `_combo_from_reactive`.
- **Nema dragovoljnog odustanka od reaktivnih poteza** (2026-07-20, svjesno maknuto — postojao je
  "End Move" gumb, ali korisnik je odlučio da mora ostati dosljedno "tjeramo dinamiku, ne dopuštamo
  zadržavanje igre" isto kao i kod combo faze gdje si prisiljen odigrati loptu ako je imaš). Oba
  reaktivna poteza uvijek moraju biti odigrana.

**Preuzimanje lopte / posjed:** tim "ima" loptu čim je JEDNA njegova figurica susjedna lopti
(Chebyshev 1) — bez obzira koliko je protivničkih figurica isto tako blizu. (Isprobano pa **ukinuto**
pravilo "nadjačavanja" — tim koji ju je upravo dosegnuo reaktivnim potezom morao bi imati pravo
igrati loptom bez obzira koliko protivnika stoji uz nju, jer ionako nije njihov red.)
**Gol:** samo s protivničke polovice. **Zaleđe:** ako su sve protivničke terenske figurice (golman isključen) strogo iza napadača — nema gola. Ako protivnik nema više nijednu terensku figuricu, zaleđe se ne može dogoditi.
**Kartoni (kontestirani 50-50 duel):** prekršaj VIŠE NIJE zadržavanje/vrtnja lopte — taj okidač je **uklonjen** (2026-07-21, vidi `docs/CHANGELOG.md`). Umjesto toga: kad reaktivni potez (tim koji NIJE imao loptu) doseže loptu i pritom sleti u ćeliju koja je **točno nasuprot** protivničkoj figurici preko lopte (bilo koja od 4 osi kroz centar — okomito, vodoravno, obje dijagonale — vidi `MatchState.is_contested_recovery`), to je "izgubljen duel za loptu": prekršaj. Razlog promjene: s uvedenim reaktivnim potezima i pravilom "2 akcije po redu", tim praktički više nikad nije mogao stvarno zadržavati loptu (izmjereno empirijski ~0.5% šutova u AI-vs-AI partijama) dok samo preuzimanje lopte nije nosilo nikakav rizik — pa je stari okidač postao gotovo mrtvo pravilo, a novi unosi stvaran, čitljiv rizik točno tamo gdje ga i treba biti (borba za loptu, ne mirno posjedovanje). Nagrada za prekršaj se **oduzima**: čak i žuti karton poništava nadogradnju u combo tog poteza (potez se potroši kao običan pomak, bez šuta) — kao u pravom nogometu, faul nikad ne donosi prednost onome tko ga je napravio. Eskalacija ostaje ista kao i prije (namjerno odstupa od originala iz 2006., 2026-07-19): 1. prekršaj = samo žuti karton, 2. i svaki sljedeći = crveni karton **I odmah obavezno uklanjanje figurice u istom potezu** (`Phase.REMOVE`, timer se tijekom te faze zaustavlja). Kartoni traju cijelu partiju (`foul_count` se NE resetira na kickoff, samo na `setup()`).

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

## 6. Animacije (Mixamo) — implementirano
- **8 izvornih Mixamo klipova** (Idle, Breathing Idle, Jog Forward, Jog Forward Diagonal, Soccer
  Pass, Strike Forward Jog, Goalkeeper Idle, Goalkeeper Miss) pečeni u
  `assets/animations/player_anims.res` preko `scripts/tools/build_player.gd` (headless builder,
  ne pokreće se svaki put). Automatski su dodane zrcaljene (`_L`) i "soft" varijante za
  pass/strike (jačina udarca ovisi o udaljenosti) — ukupno 14 klipova u biblioteci.
  `jog_diag` je pečen ali **trenutno neiskorišten** — lik uvijek rotira prema cilju i koristi
  obični `jog`, i za ravne i za dijagonalne poteze (odluka: ne uvoditi ga bez punog seta smjerova,
  vidi `docs/CHANGELOG.md`).
- **Koreografija combo/šuta** (`main.gd::_play_combo_choreography`, dijeli je i gol repriza — vidi
  ispod): tempiranje svakog udarca da noga dotakne loptu TOČNO kad stigne (bez zastoja "kotrljanje→
  stani→zamah→kotrljanje"), stvarna kontakt-točka na nozi (ne centar polja), lukovi lopte skalirani
  jačinom/udaljenosti, brzina hoda (`jog` speed_scale) skalirana udaljenosti kretanja.
- **Gol cinematika** (`main.gd`, "Goal Cinematic" export grupa): dvije STATIČNE kamere — Cam A iza
  strijelca (niz os šuta), Cam B kod gol-linije — s jednim tvrdim rezom između njih dok lopta leti
  (nikad pan/rotacija kamere). Usporenje leta (`goal_slowmo`), skok golmana (`gk_miss`), bujenje
  mreže (shader `net_dent.gdshader`), pad lopte pod gravitacijom, tribine se otkrivaju samo za ovaj
  trenutak (`hide_stadium_dressing_during_play`).
- **Gol repriza** (export grupa "Goal Replay", `main.gd::_play_goal_replay`): nakon cinematike,
  JOŠ jedan prikaz iste akcije — fiksna top-down kamera (kut zaključan, samo udaljenost auto-fitana
  kao i glavna kamera), puna koreografija ponovljena (isti udarci/golmanov skok), HUD sakriven,
  cijela postava opet vidljiva (cinematika sakriva sve osim strijelca/golmana), bijeli flash-rez pri
  ulasku, desaturacija + vinjeta samo na repriznoj kameri (`Camera3D.environment`), blinkajući
  "REPLAY" natpis (`GoalReplayTag/RLabel` u `main.tscn`, tween s `set_ignore_time_scale` da
  usporenje ne uspori i sam blink).

## 7. Kamera
- Portret, taktički pogled odozgo/koso na cijelu ploču.
- Kut/kompoziciju/FOV **tunira korisnik u editoru** (Camera3D transform u `main.tscn`). Kod (`_fit_camera` u `main.gd`) samo klizi kameru po toj istoj osi gledanja tako da cijeli teren uvijek stane, na bilo kojem omjeru ekrana — nikad ne mijenja kut. Ista "autor tunira kut, kod fita samo udaljenost" logika ponovno iskorištena za repriznu top-down kameru (`_place_replay_cam`).
- Poseban "gol" pogled: implementirano — vidi §6 (gol cinematika dvije statične kamere + top-down repriza).
- ⚠️ Pri ručnom upisu `Transform3D(...)` u `.tscn`: Godot zapisuje bazis TRANSPONIRANO (vidi `docs/CHANGELOG.md`, 2026-07-08) — ne upisuj `basis.x, basis.y, basis.z` redom bez transponiranja, ili koristi editor/Transform dijalog umjesto ručnog upisa.

## 8. Zvuk (`assets/audio/`)
- `sfx/`: dodavanje, šut, gol, zvižduk, karton, preuzimanje lopte. **Implementirano za sad samo
  šut** (`assets/audio/sfx/ball_kick.mp3`, `PlayerRig._kick_sfx`/`KICK_SOUND`, `SFX` bus iz
  `bus_layout.tres`) — svira točno na `kick_contact` signalu (isti frame kad noga dotakne loptu),
  glasnoća tunirana preko `@export kick_sfx_volume_db` na PlayerRig. Ostatak (pass/gol/zvižduk/
  karton/preuzimanje) su i dalje samo placeholderi u planu, zvuk nije ožičen.
- `music/`: menu, slavlje nakon gola.

## 9. Prezentacija / meta
- 16 reprezentacija, single-elimination bracket (vidi `country_kits.gd`).
- Zastave: `assets/textures/ui/countries/<kod>.png`.
- Brojevi na dresu: `assets/textures/numbers/`.
- **HUD** (`scenes/ui/hud.tscn`): grbovi, skor, kartoni, timer, footer (tko je na potezu).
  Veliki, jasno vidljivi banner za žuti/crveni karton i zaleđe (`play_announcement`) — footer tekst
  sam nije bio dovoljno uočljiv. Timer po redu (`turn_time_limit`, dijele ga COMBO+MOVE/REMOVE istog
  reda) staje tijekom `Phase.REMOVE` (nema isteka — inače bi istek poništio kaznu za prekršaj).
- **Oznaka vlastitog tima** (`scripts/game/player_rig.gd`, `OwnTeamTileGlow` u `player_rigged.tscn`):
  tihi, nisko-alfa zaobljeni kvadrat pod nogama SAMO igračevih vlastitih figura, boju/alfu/veličinu
  tunira autor u editoru na baziranoj sceni. `top_level=true` da se ne rotira s figuricom.
- **Tok ekrana** (`GameFlow` autoload, `scripts/game/game_flow.gd`): splash →
  glavni izbornik (po uzoru na original iz 2006: 1/2 Player, Options,
  Instructions, Credits, Quit) → odabir momčadi (Player 1=Home, Player 2=Away,
  fiksno) → meč. `run/main_scene` je `scenes/ui/splash_screen.tscn` (ne `main.tscn`).
  Splash je korisnikov vlastiti dizajn (ne dirati izgled); ostali ekrani u
  `scenes/ui/` su namjerno gole placeholder scene (izgled je za urediti u
  editoru). Ručno postavljanje figura (golman pa redom ostali, samo igračeva
  strana) živi kao rana faza unutar SAME meč-scene (`main.gd::_start_placement`),
  ne kao zaseban ekran. Instructions ekran već ima pravi sažetak pravila.

## 10. AI protivnik (Single Player)
- `scripts/game/ai_player.gd` — implementiran, testiran (`scripts/tests/test_ai_ranked.gd`).
- **Jedan zajednički mehanizam** za SVAKU vrstu odluke (combo korak, pomak, uklanjanje figure nakon
  crvenog kartona): sve kandidate boduje jedna scoring funkcija, poredaju se po rangu, pa
  `_rank_pick` bira NASUMIČNO po vjerojatnosti ovisno o težini — ne odvojena heuristika po vrsti
  odluke.
- **Težine = vjerojatnost odabira najboljeg (rang #1) poteza** za Medium/Easy: ~90%/~70% top rang,
  ostatak padne na rang #2/#3, ista evaluacija kao Hard, samo lošija stopa pogotka.
  **Hard je od 2026-07-19 kvalitativno druga priča** (korisnik se žalio da ga pobjeđuje u par
  poteza): `decide_combo` na Hard ne hoda pohlepno korak-po-korak nego pravom backtracking
  pretragom cijelog combo stabla (`_search_best_combo`/`_search_combo_step`, beam-limited na
  `COMBO_SEARCH_BEAM=2` po grani zbog performansi — vidi ispod) — može odabrati dodavanje koje
  odmah ne izgleda najbolje jer priprema siguran gol 2-3 dodira kasnije. Isto tako `decide_move`
  na Hard, kad reaktivni potez dosegne loptu, pokreće ISTU pretragu (`_reach_ball_value`) da odabere
  KOJI dohvat vodi do najjačeg napada, ne samo bilo koji.
- Combo bodovanje: pravi gol vrijedi najviše, minus za ostavljanje lopte blizu protivničkih figura,
  MALI bonus za blizinu vlastitih figura (namjerno spušten s 3.0 na 0.5× jačine napredovanja prema
  golu 2026-07-19 — na starijoj težini ta "ostani blizu podrške" kazna je gotovo uvijek nadjačala
  nagradu za stvaran napredak, pa je AI gurao loptu minimalno i stao umjesto da stvarno
  napreduje/čisti loptu iz obrane). Svaki kandidat za šut ISTO provjerava
  (`_post_shot_threat_penalty`) ostavlja li protivniku odmah otvorenu priliku za uzvratni gol — ovo
  vrijedi za SVE težine, ne samo Hard. Šutovi više ne mogu izazvati karton (vidi §3) pa nema kazne
  za to u combo bodovanju.
- **Obrana**: `_defense_score` nagrađuje ulazak na trenutno otvorenu ravnu liniju šuta prema
  vlastitom golu (`Board.is_straight`/`path_clear`/`cells_between`) — AI ne samo juri loptu, nego i
  brani gol kad je na potezu za pomicanje. Pomak-bodovanje (`_move_score`) ISTO teško kažnjava
  (`_contested_recovery_penalty`) reaktivni potez koji bi sletio u kontestiranu 50-50 ćeliju (vidi
  §3) kad postoji sigurnija alternativa koja jednako tako dohvaća loptu — AI nikad namjerno ne
  riskira karton bez razloga.
- **Performanse (mobitel je cilj, ne desktop)**: `_rank_pick` je nekad zvao funkciju bodovanja
  VIŠE PUTA po kandidatu tijekom sortiranja (bezazleno dok je bodovanje bilo jeftino, ali otkad
  `_reach_ball_value` unutra pokreće punu pretragu, jedna AI odluka je znala potrajati i 11 SEKUNDI)
  — sad se svaki bod računa točno jednom prije sortiranja. Dodatno: ciljevi šuta unutar pretrage su
  i sami beam-limited prije skupe provjere prijetnje, i `decide_move` ima tvrdi strop
  (`MAX_REACH_BALL_SEARCHES=3`) koliko kandidata uopće smije pokrenuti tu skupu pretragu po pozivu.
  Rezultat: `decide_combo` ~75ms, `decide_move` ~150-400ms na desktopu (bilo 350-450ms / 11000ms).
- AI izvršava odluke kroz ISTE funkcije koje bi tap odigrao (`_do_combo`/`_apply_move`/`_remove_at`
  u `main.gd`), pa se animira identično čovjeku; kratka umjetna "razmišljam" pauza
  (`AI_THINK_TIME`) prije poteza da ne djeluje trenutačno/robotski.

## 11. Otvorena pitanja / odluke za kasnije
- [ ] Online multiplayer (Firebase) — u planu da zamijeni lokalni hot-seat "2 Player"; taj način
  za sad ostaje samo kao test placeholder.
- [ ] Točan izgled/uvjeti "zaleđa" u kodu (rub slučajevi).
- [ ] Vizual za brojeve: pravi broj na dresu (numbers PNG) vs. `Label3D` iznad glave.
- [ ] Poklapanje uvezenog terena s logičkom mrežom (skala/origin).

---
*Zadnje ažurirano: 2026-07-19. Uz ovaj dokument idi i [`docs/TODO.md`](TODO.md).*
