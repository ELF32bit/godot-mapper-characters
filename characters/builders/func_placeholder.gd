extends MapperUtilities

@warning_ignore("unused_parameter")
static func build(map: MapperMap, entity: MapperEntity) -> Node:
	var node := preload("func_group.gd").build_animated_geometry(map, entity)
	if node: # preparing a node for the placeholder point/brush entity
		if not map.settings.options.get("collision_convex", true):
			node = change_node_type(node, "Node3D")
		elif map.settings.options.get("collision_siblings", true):
			node = change_node_type(node, "Node3D")
	else: node = Node3D.new()
	node.set_meta("_MAPPER_MERGE", false)

	# configuring func_placeholder targets (storage weapons/items)
	node.set_script(map.loader.load_script("scripts/func_placeholder"))
	entity.bind_node_path_array_property("target", "targetname", "_targets")
	entity.bind_node_path_property("target", "targetname", "_target")

	return node
