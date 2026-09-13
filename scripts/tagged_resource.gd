class_name TaggedResource
extends Resource

## Чем сущность БЬЁТ. В отличие от identity, может быть выдано по ходу забега
## (grant-апгрейды, Этап 1.5b).

@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.ELEMENT_HINT) var tags:Array[String] = []

func  has_tag(tag: String) -> bool:
	return tag in tags
 
