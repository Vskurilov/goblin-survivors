class_name WeaponData
extends TaggedResource

enum TargetMode{NEAREST, FARTHEST, RANDOM}


@export var weapon_name:String = ''
@export var fire_rate:float = 1.0
@export var weapon_bonuses : Dictionary = {}

func  fire(player:Node):
	push_warning("fire не реализован для: " + weapon_name)

func pick_target(player:Node, mode:TargetMode) -> Node2D:
	var targets = pick_targets(player, mode, 1)
	if targets.size() > 0:
		return targets[0]
	else:
		return null
		

func pick_targets(player:Node, mode: TargetMode, count: int) -> Array[Node2D]:
	var candidates: Array = []
	match  mode:
		TargetMode.NEAREST:
			candidates =  player.get_enemies_sorted(player.nearest_criteria)
		TargetMode.FARTHEST:
			candidates =  player.get_enemies_sorted(player.fartest_criteria)
		TargetMode.RANDOM:
			candidates =  player.get_tree().get_nodes_in_group("enemies")
			candidates.shuffle()
	var actual_count = min(count, candidates.size())
	var result: Array[Node2D] = []
	for i in range(actual_count):
		result.append(candidates[i])
	return result
