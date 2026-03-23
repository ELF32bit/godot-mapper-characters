extends MapperUtilities

@warning_ignore("unused_parameter")
static func build(map: MapperMap, entity: MapperEntity) -> Node:
	if map.is_group_entity(entity, "_tb_group"):
		map.bind_group_entities(entity, "_tb_group")
	elif map.is_group_entity(entity, "_tb_layer"):
		map.bind_group_entities(entity, "_tb_layer")
	else: return null
	var group_center := Vector3.ZERO
	var count: int = 0

	# parenting group entities to the group node
	for group_entity in map.group_entities.get(entity, []):
		group_entity.parent = entity

	# calculating group center
	for group_entity in map.group_entities.get(entity, []):
		if group_entity.brushes.size():
			group_center += group_entity.center
			count += 1
	for brush in entity.brushes:
		group_center += brush.center
		count += 1

	# binding group properties
	if count:
		group_center /= count
	entity.node_properties["position"] = group_center
	entity.bind_string_property(map.settings.group_entity_name_property, "name")

	# creating group node
	var node := build_animated_geometry(map, entity)
	if node and map.is_group_entity(entity, "_tb_layer"):
		node.remove_meta("_MAPPER_MERGE")
	elif not node and map.is_group_entity(entity, "_tb_layer"):
		node = AnimatableBody3D.new()
		node.set_meta("_MAPPER_EMPTY", true)
	elif not node:
		node = Node3D.new()
		node.set_meta("_MAPPER_GROUP", true)

	# returning group node with TB layer index metadata
	if map.is_group_entity(entity, "_tb_layer"):
		node.set_meta("_MAPPER_INDEX", entity.get_int_property(
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
