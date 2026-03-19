extends MapperUtilities

@warning_ignore("unused_parameter")
static func build(map: MapperMap, entity: MapperEntity) -> Node:
	var node := preload("func_group.gd").build_animated_geometry(map, entity)
	if node: return node
	match entity.get_classname_property():
		map.settings.world_entity_classname: return null
	return Marker3D.new()
