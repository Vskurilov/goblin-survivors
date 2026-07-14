class_name StatusEffectData
extends TaggedResource

@export var duration:float= 3.0
@export var tick_interval = 0.5
@export var max_stacks:int = 1
@export var stack_group: StringName = &"" 


func apply_tick(_enemy:Node2D, _owner_actor: Actor = null, _weapon_bonuses : Dictionary = {}, _crit_chance:float = 0.05, _crit_mult:float = 2.0) -> void:
	push_error("StatusEffectData.apply_tick() не переопределен в " + str(get_script().resource_path))
