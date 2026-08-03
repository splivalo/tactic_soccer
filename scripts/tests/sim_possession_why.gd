extends SceneTree

## Not "how bad is it" — sim_move_range.gd already answered that — but HOW the
## attacker keeps the ball, so a rule aimed at it can be aimed at the right
## thing instead of the nearest thing.
##
##   godot --headless -s res://scripts/tests/sim_possession_why.gd
##
## Records, for every kick: how far it travelled, and who was standing next to
## where it landed. If retained possession is mostly short kicks into a crowd of
## your own, a minimum kick distance fixes it. If it is mostly long kicks that
## still land where only you are, distance is irrelevant and the answer is about
## who gets to claim a contested ball.

const MATCHES := 15
const MAX_TURNS := 1200
const DIFFICULTY := "Medium"


func _initialize() -> void:
	var dist := {}          # kick length -> count
	var kept_dist := {}     # kick length -> count, only kicks that retained possession
	var kicks := 0
	var kept := 0
	var uncontested := 0    # landed with own figures adjacent and no opponent
	var contested := 0      # both sides adjacent
	var loose := 0          # nobody adjacent
	var theirs_only := 0

	for m in MATCHES:
		seed(m * 7919)
		var ms := MatchState.new()
		ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)
		var turns := 0
		while ms.score["HomeTeam"] < 2 and ms.score["AwayTeam"] < 2 and turns < MAX_TURNS:
			turns += 1
			match ms.phase:
				MatchState.Phase.COMBO:
					var shooter: Vector2i = Vector2i(-1, -1)
					var shoot := AIPlayer.decide_combo(ms, DIFFICULTY)
					if shoot == Vector2i(-1, -1):
						ms.forfeit()
						continue
					if not ms.chain.is_empty():
						shooter = ms.chain[-1]
					var kicker := ms.current
					var res := ms.execute_combo(shoot)
					if shooter != Vector2i(-1, -1):
						var d: int = maxi(absi(shoot.x - shooter.x), absi(shoot.y - shooter.y))
						kicks += 1
						dist[d] = dist.get(d, 0) + 1
						var mine := _adjacent_count(ms, shoot, kicker)
						var theirs := _adjacent_count(ms, shoot, ms.opponent(kicker))
						if mine > 0 and theirs == 0:
							uncontested += 1
						elif mine > 0 and theirs > 0:
							contested += 1
						elif theirs > 0:
							theirs_only += 1
						else:
							loose += 1
						# Retained = the kicker still has it when their turn
						# comes round, which is what "possession" means here.
						if mine > 0 and theirs == 0:
							kept += 1
							kept_dist[d] = kept_dist.get(d, 0) + 1
					if res["goal"]:
						if res["win"]:
							continue
						ms.reset(Formations.home(), Formations.away(), Vector2i(3, 8), res["kickoff"])
				MatchState.Phase.MOVE:
					var mv := AIPlayer.decide_move(ms, DIFFICULTY)
					if not mv.has("from"):
						ms.forfeit()
						continue
					ms.do_move(mv["from"], mv["to"])
				MatchState.Phase.REMOVE:
					var cell := AIPlayer.decide_removal(ms, DIFFICULTY)
					if cell == Vector2i(-1, -1):
						ms.forfeit()
						continue
					ms.remove_figure(cell)

	print("%d kicks over %d matches\n" % [kicks, MATCHES])
	print("where the ball landed")
	print("  only MY players next to it     %5.1f%%   <- possession kept for free" \
		% (100.0 * uncontested / maxi(kicks, 1)))
	print("  both sides next to it          %5.1f%%" % (100.0 * contested / maxi(kicks, 1)))
	print("  only THEIR players next to it  %5.1f%%" % (100.0 * theirs_only / maxi(kicks, 1)))
	print("  nobody next to it              %5.1f%%   <- a real race" \
		% (100.0 * loose / maxi(kicks, 1)))

	print("\nkick length        all kicks     of those, kept possession")
	var lengths := dist.keys()
	lengths.sort()
	for d in lengths:
		var n: int = dist[d]
		var k: int = kept_dist.get(d, 0)
		print("  %2d squares      %5.1f%%  (%4d)     %5.1f%%" \
			% [d, 100.0 * n / maxi(kicks, 1), n, 100.0 * k / maxi(n, 1)])
	quit(0)


func _adjacent_count(ms: MatchState, cell: Vector2i, team: String) -> int:
	var n := 0
	for c in ms.pieces:
		if ms.pieces[c]["team"] == team \
				and maxi(absi(cell.x - c.x), absi(cell.y - c.y)) <= 1:
			n += 1
	return n
