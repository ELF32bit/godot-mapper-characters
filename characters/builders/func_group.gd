extends MapperUtilities

@warning_ignore("unused_parameter")
static func build(map: MapperMap, entity: MapperEntity) -> Node:
	if map.is_group_entity(entity, "_tb_group"):
		map.bind_group_entities(entity, "_tb_group")
	elif map.is_group_entity(entity, "_tb_layer"):
		map.bind_group_entities(entity, "_tb_layer")
	else: return null

	# parenting group entities to the group node
	for group_entity in map.group_entities.get(entity, []):
		group_entity.parent = entity

	# calculating group AABB from brushes
	var aabb := AABB()
	var aabb_is_empty := true
	for group_entity in map.group_entities.get(entity, []):
		if not group_entity.aabb.has_surface(): continue
		if aabb_is_empty:
			aabb = group_entity.aabb
			aabb_is_empty = false
		else: aabb = aabb.merge(group_entity.aabb)
	for brush in entity.brushes:
		if not brush.aabb.has_surface(): continue
		if aabb_is_empty:
			aabb = brush.aabb
			aabb_is_empty = false
		else: aabb = aabb.merge(brush.aabb)

	# calculating group AABB from point entities if there are no brushes
	if aabb_is_empty:
		for group_entity in map.group_entities.get(entity, []):
			if not group_entity.brushes.size() == 0: continue
			var origin = group_entity.get_origin_property(null)
			if origin == null: continue
			if aabb_is_empty:
				aabb = AABB(origin, Vector3.ZERO)
				aabb_is_empty = false
			else: aabb = aabb.expand(origin)

	# binding group properties
	entity.node_properties["position"] = aabb.get_center()
	entity.bind_string_property(map.settings.group_entity_name_property, "name")

	# creating group node
	var node := build_animated_geometry(map, entity)
	if node and map.is_group_entity(entity, "_tb_layer"):
		node.remove_meta("_MAPPER_MERGE")
	elif not node and map.is_group_entity(entity, "_tb_layer"):
		node = AnimatableBody3D.new()
		node.set_meta("_MAPPER_LAYER_REPLACE", true)
	elif not node:
		node = Node3D.new()
		node.set_meta("_MAPPER_GROUP", true)

	# setting additional group node properties from map options
	node.set("physics_material_override", map.settings.options.get("physics_material", null))
	node.set("collision_layer", map.settings.options.get("collision_layer", 1))
	node.set("collision_mask", map.settings.options.get("collision_mask", 1))

	# returning group node with TB layer index metadata
	if map.is_group_entity(entity, "_tb_layer"):
		node.set_meta("_MAPPER_LAYER_INDEX", entity.get_int_property(
			map.settings.tb_layer_index_property, 0))
	return node

@warning_ignore("unused_parameter")
static func build_animated_geometry(map: MapperMap, entity: MapperEntity) -> Node:
	var node := create_merged_brush_entity(entity, "AnimatableBody3D")
	if not node: return null
	for child in node.find_children("*", "", true, false):
		child.set_meta("_MAPPER_MERGE", true)
	node.set_meta("_MAPPER_MERGE", true)
	return node
