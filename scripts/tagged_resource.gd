class_name TaggedResource
extends Resource

@export_flags("Physical", "Fire", "Ice", "Poison", "Lightning") var 	tags: int = 0

func  has_tag(tag: Tags.Type) -> bool:
	return tags & (1 << tag) != 0
 
