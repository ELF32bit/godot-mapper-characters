extends MapperUtilities

const SHADER_FADE_PROPERTY: String = "fade"
const SHADER_FADE_INDEX_PROPERTY: String = "fade_index"
const FADE_MATERIAL_METADATA: String = "fade_material"
const NODE_NAMES: Array = ["ANIMATIONS", "STORAGE",
	"MeshInstance3D",
	"FadeInstance3D",
	"CollisionShape3D",
	"OccluderInstance3D",
]

@warning_ignore("unused_parameter")
static func build(map: MapperMap) -> void:
	# creating storage node for the map data
	var storage_node := Node3D.new()
	map.node.add_child(storage_node)
	map.node.move_child(storage_node, 0)
	storage_node.name = NODE_NAMES[1]

	# finding map layers and deleting empty nodes
	var layers := map.node.find_child("func_group", false, false)
	for child in map.node.get_children():
		if child == storage_node: continue
		if child.get_children().size():
			map.node.remove_child(child)
			storage_node.add_child(child, true)
		else: child.free()
	if not layers: return

	# finding info_animation entity
	var animation_info := MapperEntity.new()
	animation_info.factory = map.factory
	if map.classnames.has("info_animation"):
		animation_info = map.classnames.get("info_animation", [null])[0]

	# reading simple properties from info_animation entity
	var info: Dictionary = {}
	info["autoplay"] = animation_info.get_string_property("autoplay", "").to_lower()
	info["fade_visibility_end"] = animation_info.get_unit_property("fade_visibility_end", 0.0)
	info["visibility_end"] = animation_info.get_unit_property("visibility_end", 0.0)
	info["cast_shadow"] = animation_info.get_int_property("cast_shadow", 1)

	# parsing unsorted animations from map layers
	var animations: Dictionary = {}
	var animation_nodes: Array = []
	for child in layers.get_children():
		var split: PackedStringArray = child.name.split("->", false, 1)
		if split.size() != 2: continue
		split[1] = split[1].replace("_", ".")
		if not split[1].is_valid_float(): continue
		var name := split[0].to_lower()
		var frame := float(split[1])

		animations.get_or_add(name, {})
		animations[name].get_or_add("nodes", []).append(child)
		animations[name].get_or_add("frames", []).append(frame)
		var max_frame: float = animations[name].get_or_add("max_frame", 0.0)
		animations[name]["max_frame"] = maxf(frame, max_frame)

		# reading animation parameters from info_animation entity
		var parameters: Dictionary = animation_info.get_variant_property(split[0], {})
		animations[name]["frame_duration"] = parameters.get("frame_duration", 0.2)
		animations[name]["loop_mode"] = parameters.get("loop_mode", 1)
		animations[name]["fade"] = parameters.get("fade", [])
		animations[name]["fade_loop"] = parameters.get("fade_loop", false)
		animations[name]["fade_before"] = parameters.get("fade_before", true)
		animations[name]["fade_after"] = parameters.get("fade_after", false)
		animations[name]["fade_mode"] = parameters.get("fade_mode", 1)

		animation_nodes.append([child, child.get_meta("_MAPPER_INDEX", 0)])
		child.remove_meta("_MAPPER_INDEX")
		layers.remove_child(child)

	# sorting animations
	for name in animations:
		var old_nodes: Array = animations[name]["nodes"]
		var old_frames: Array = animations[name]["frames"]
		var sorting: Array = []
		for index in range(old_frames.size()):
			sorting.append([old_nodes[index], old_frames[index]])
		sorting.sort_custom(func(a, b): return a[1] < b[1])

		var new_nodes: Array = []
		var new_frames: Array = []
		for index in range(sorting.size()):
			new_nodes.append(sorting[index][0])
			new_frames.append(sorting[index][1])
		animations[name]["nodes"] = new_nodes
		animations[name]["frames"] = new_frames

	# sorting animation nodes by TB layer index and hiding them
	animation_nodes.sort_custom(func(a, b): return a[1] < b[1])
	for node in animation_nodes:
		map.node.add_child(node[0])
		node[0].visible = false

	# merging layer data
	for index in range(animation_nodes.size()):
		var node: Array = animation_nodes[index]
		var layer_node: Node3D = node[0]
		var transform := layer_node.transform.affine_inverse()
		var mesh_instances := layer_node.find_children("*", "MeshInstance3D", true, false)
		var collision_shapes := layer_node.find_children("*", "CollisionShape3D", true, false)
		var occluder_instances := layer_node.find_children("*", "OccluderInstance3D", true, false)

		mesh_instances = mesh_instances.filter(func(instance):
			return instance.get_meta("_MAPPER_MERGE", false))
		collision_shapes = collision_shapes.filter(func(instance):
			return instance.get_meta("_MAPPER_MERGE", false))
		occluder_instances = occluder_instances.filter(func(instance):
			return instance.get_meta("_MAPPER_MERGE", false))

		var mesh_instance := _merge_mesh_instances(mesh_instances, transform)
		var collision_shape := _merge_collision_shapes(collision_shapes, transform)
		var occluder_instance := _merge_occluder_instances(occluder_instances, transform)

		# setting default properties for the RESET animation
		mesh_instance.cast_shadow = info["cast_shadow"]
		mesh_instance.visibility_range_end = info["visibility_end"]
		collision_shape.disabled = true
		for other_node in layer_node.find_children("*", "CollisionShape3D", true, false):
			if other_node.disabled: other_node.set_meta("_MAPPER_DISABLED", true)
			other_node.disabled = true

		# duplicating mesh instance as fade instance
		var fade_instance := mesh_instance.duplicate()
		fade_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fade_instance.visibility_range_end = info["fade_visibility_end"]
		fade_instance.visible = false

		# removing nodes that were used for merging
		for old_node in layer_node.find_children("*", "", true, false):
			if not is_instance_valid(old_node): continue
			if not old_node.get_meta("_MAPPER_MERGE", false): continue
			var old_node_children := old_node.get_children()
			old_node_children = old_node_children.filter(func(child):
				return not child.get_meta("_MAPPER_MERGE", false))
			if old_node_children.size():
				old_node.remove_meta("_MAPPER_MERGE")
				change_node_type(old_node, "Node3D")
			else: old_node.free()

		# manually naming merged nodes to ignore project naming settings
		mesh_instance.name = NODE_NAMES[2]
		fade_instance.name = NODE_NAMES[3]
		collision_shape.name = NODE_NAMES[4]
		occluder_instance.name = NODE_NAMES[5]

		# adding merged nodes to the layer node
		var has_collision := true
		if occluder_instances.size():
			layer_node.add_child(occluder_instance, true)
			layer_node.move_child(occluder_instance, 0)
		else: occluder_instance.free()
		if collision_shapes.size():
			layer_node.add_child(collision_shape, true)
			layer_node.move_child(collision_shape, 0)
		else:
			collision_shape.free()
			has_collision = false
		if mesh_instances.size():
			layer_node.add_child(fade_instance, true)
			layer_node.move_child(fade_instance, 0)
			layer_node.add_child(mesh_instance, true)
			layer_node.move_child(mesh_instance, 0)
		else:
			mesh_instance.free()
			fade_instance.free()

		# setting visibility parent for all other nodes in the layer
		if is_instance_valid(mesh_instance):
			for other_node in layer_node.get_children():
				if not other_node is Node3D: continue
				if other_node.name in [NODE_NAMES[2], NODE_NAMES[3],
					NODE_NAMES[4], NODE_NAMES[5]]: continue
				other_node.visibility_parent = other_node.get_path_to(mesh_instance)

		# changing layer node type if collision shape is missing
		if not has_collision:
			var new_layer_node := change_node_type(layer_node, "Node3D")
			for name in animations:
				# DANGER: searching array for the node that has been freed
				var i: int = animations[name]["nodes"].find(layer_node)
				if not i < 0: animations[name]["nodes"][i] = new_layer_node
			animation_nodes[index] = [new_layer_node, node[1]]

	# removing empty group nodes from the map
	for group_node in map.node.find_children("*", "", true, false):
		if not is_instance_valid(group_node): continue
		if not group_node.get_meta("_MAPPER_GROUP", false): continue
		if group_node.get_parent() == map.node:
			group_node.remove_meta("_MAPPER_GROUP")
		elif group_node.get_children().size():
			group_node.remove_meta("_MAPPER_GROUP")
		else: group_node.free()

	# replacing layer nodes that failed to parse as animations
	for layer_node in layers.get_children():
		if not layer_node.get_children().size(): layer_node.free()
		elif layer_node.get_meta("_MAPPER_EMPTY", false):
			layer_node.remove_meta("_MAPPER_EMPTY")
			change_node_type(layer_node, "Node3D")
	if not layers.get_children().size():
		layers.free()

	# creating animation player
	var animation_player := AnimationPlayer.new()
	map.node.add_child(animation_player, true)
	map.node.move_child(animation_player, 0)
	animation_player.name = NODE_NAMES[0]

	# moving animation player to the physics process if collision shapes are present
	for index in range(animation_nodes.size()):
		var layer_node: Node3D = animation_nodes[index][0]
		if not layer_node.find_children("*", "CollisionShape3D", true, false).size(): continue
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		break

	# creating animation library for the animation player
	var animation_library := AnimationLibrary.new()
	_create_animation_table(map, animations, animation_nodes, animation_library, info)
	animation_player.add_animation_library("", animation_library)
	animation_player.autoplay = info["autoplay"]

	# creating reset animation for the animation player
	MapperUtilities.create_reset_animation(animation_player, animation_library)


static func _merge_mesh_instances(mesh_instances: Array, inverse_transform: Transform3D) -> MeshInstance3D:
	var materials: Dictionary = {}
	var surface_tools: Dictionary = {}
	for mesh_instance in mesh_instances:
		if not mesh_instance.visible: continue
		if not mesh_instance.mesh: continue
		var mesh: ArrayMesh = mesh_instance.mesh
		var transform := inverse_transform * get_global_transform(mesh_instance)
		for surface_index in range(mesh.get_surface_count()):
			var surface_name := mesh.surface_get_name(surface_index)
			if not materials.has(surface_name):
				materials[surface_name] = [null, null]
			materials[surface_name][0] = mesh.surface_get_material(surface_index)
			materials[surface_name][1] = mesh_instance.get_surface_override_material(surface_index)
			if not surface_tools.has(surface_name):
				surface_tools[surface_name] = SurfaceTool.new()
			surface_tools[surface_name].set_material(materials[surface_name][0])
			surface_tools[surface_name].append_from(mesh, surface_index, transform)

	var merged_mesh := ArrayMesh.new()
	for surface_name in surface_tools:
		merged_mesh = surface_tools[surface_name].commit(merged_mesh)
		var surface_index := merged_mesh.get_surface_count() - 1
		merged_mesh.surface_set_name(surface_index, surface_name)

	var merged_mesh_instance := MeshInstance3D.new()
	merged_mesh_instance.mesh = merged_mesh
	for surface_index in range(merged_mesh.get_surface_count() if merged_mesh else 0):
		var surface_name := merged_mesh.surface_get_name(surface_index)
		var override_material: Material = materials.get(surface_name, [null, null])[1]
		merged_mesh_instance.set_surface_override_material(surface_index, override_material)
	merged_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	return merged_mesh_instance


static func _merge_collision_shapes(collision_shapes: Array, inverse_transform: Transform3D) -> CollisionShape3D:
	var merged_faces: PackedVector3Array = []
	for collision_shape in collision_shapes:
		if collision_shape.disabled: continue
		if not collision_shape.shape: continue
		var debug_mesh: ArrayMesh = collision_shape.shape.get_debug_mesh()
		var transform := inverse_transform * get_global_transform(collision_shape)
		var faces := transform * debug_mesh.generate_triangle_mesh().get_faces()
		merged_faces.append_array(faces)

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = ConcavePolygonShape3D.new()
	if merged_faces.size():
		collision_shape.shape.set_faces(merged_faces)

	return collision_shape


static func _merge_occluder_instances(occluder_instances: Array, inverse_transform: Transform3D) -> OccluderInstance3D:
	var merged_vertices: PackedVector3Array = []
	var merged_indices: PackedInt32Array = []
	for occluder_instance in occluder_instances:
		if not occluder_instance.visible: continue
		if not occluder_instance.occluder: continue
		var occluder: ArrayOccluder3D = occluder_instance.occluder
		var transform := inverse_transform * get_global_transform(occluder_instance)
		var vertices := occluder.get_vertices()
		var indices := occluder.get_indices()

		vertices = transform * vertices
		var last_size := merged_vertices.size()
		for index in range(indices.size()):
			indices[index] += last_size
		merged_indices.append_array(indices)
		merged_vertices.append_array(vertices)

	var occluder_instance := OccluderInstance3D.new()
	occluder_instance.occluder = ArrayOccluder3D.new()
	if merged_vertices.size() and merged_indices.size():
		occluder_instance.occluder.set_arrays(merged_vertices, merged_indices)

	return occluder_instance


static func _create_animation_table(map: MapperMap, animations: Dictionary, animation_nodes: Array, animation_library: AnimationLibrary, info: Dictionary) -> void:
	# creating animations
	for name in animations:
		var data: Dictionary = animations[name]
		var has_frames := float(data["max_frame"] > 0.0)
		var is_autoplay := bool(name == info["autoplay"])
		var fade_percentages: Array = [0.0] + data["fade"]
		var fade_frames: int = data["fade"].size()
		var frames: int = data["frames"].size()

		var animation := Animation.new()
		if data["loop_mode"] == Animation.LOOP_PINGPONG: has_frames = false
		animation.length = (data["max_frame"] + has_frames) * data["frame_duration"]
		animation.loop_mode = data["loop_mode"]

		# creating animation tracks
		for node_index in range(animation_nodes.size()):
			var node: Node3D = animation_nodes[node_index][0]
			var node_path := str(map.node.get_path_to(node))
			var track_index := animation.get_track_count()

			var mesh_instance := node.find_child(NODE_NAMES[2], false, false)
			var fade_instance := node.find_child(NODE_NAMES[3], false, false)
			var collision_shape := node.find_child(NODE_NAMES[4], false, false)
			var occluder_instance := node.find_child(NODE_NAMES[5], false, false)

			animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track_index, node_path + ":visible")
			animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
			animation.track_set_interpolation_loop_wrap(track_index, false)
			animation.track_insert_key(track_index, 0.0, false)
			animation.track_set_imported(track_index, true)
			track_index += 1

			animation.add_track(Animation.TYPE_VALUE)
			if not mesh_instance is MeshInstance3D:
				animation.track_set_enabled(track_index, false)
			animation.track_set_path(track_index, node_path + "/%s:visible" % NODE_NAMES[2])
			animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
			animation.track_set_interpolation_loop_wrap(track_index, false)
			animation.track_insert_key(track_index, 0.0, false)
			animation.track_set_imported(track_index, true)
			track_index += 1

			for child in node.get_children():
				if not child is Node3D: continue
				if child.name in [NODE_NAMES[2], NODE_NAMES[3],
					NODE_NAMES[4], NODE_NAMES[5]]: continue
				if not child.visible: continue
				animation.add_track(Animation.TYPE_VALUE)
				animation.track_set_path(track_index, node_path + "/%s:visible" % [child.name])
				animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
				animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
				animation.track_set_interpolation_loop_wrap(track_index, false)
				animation.track_insert_key(track_index, 0.0, false)
				animation.track_set_imported(track_index, true)
				track_index += 1

			animation.add_track(Animation.TYPE_VALUE)
			if not fade_instance is MeshInstance3D:
				animation.track_set_enabled(track_index, false)
			animation.track_set_path(track_index, node_path + "/%s:visible" % NODE_NAMES[3])
			animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
			animation.track_set_interpolation_loop_wrap(track_index, false)
			animation.track_insert_key(track_index, 0.0, false)
			animation.track_set_imported(track_index, true)
			track_index += 1

			if fade_instance is MeshInstance3D:
				for surface_index in range(fade_instance.get_surface_override_material_count()):
					var material: Material = fade_instance.get_active_material(surface_index)

					# trying to load fade material from material metadata
					var fade_material = material
					if material.has_meta(FADE_MATERIAL_METADATA):
						fade_material = material.get_meta(FADE_MATERIAL_METADATA, null)
						if fade_material != null:
							if not fade_material is ShaderMaterial: continue
							if fade_material.get_shader_parameter(SHADER_FADE_PROPERTY) == null:
								continue

					# duplicating fade material for each animation
					fade_material = fade_material.duplicate()
					fade_instance.set_surface_override_material(surface_index, fade_material)
					var material_path := "/%s:surface_material_override/%s"
					material_path = material_path % [NODE_NAMES[3], surface_index]

					var default_priority: int = fade_material.render_priority
					var priority_path := "%s:render_priority" % [material_path]
					var fade_path := "%s:shader_parameter/%s" % [material_path, SHADER_FADE_PROPERTY]
					var fade_index_path := "%s:shader_parameter/%s" % [material_path, SHADER_FADE_INDEX_PROPERTY]

					animation.add_track(Animation.TYPE_VALUE)
					animation.track_set_path(track_index, node_path + priority_path)
					animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
					animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
					animation.track_set_interpolation_loop_wrap(track_index, false)
					animation.track_insert_key(track_index, 0.0, default_priority)
					animation.track_set_imported(track_index, true)
					track_index += 1

					animation.add_track(Animation.TYPE_VALUE)
					animation.track_set_path(track_index, node_path + fade_path)
					if data["fade_mode"] == 1:
						animation.value_track_set_update_mode(track_index, Animation.UPDATE_CONTINUOUS)
						animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_LINEAR)
						animation.track_set_interpolation_loop_wrap(track_index, true)
					elif data["fade_mode"] == 2:
						animation.value_track_set_update_mode(track_index, Animation.UPDATE_CONTINUOUS)
						animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_CUBIC)
						animation.track_set_interpolation_loop_wrap(track_index, true)
					else:
						animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
						animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
						animation.track_set_interpolation_loop_wrap(track_index, false)
					animation.track_insert_key(track_index, 0.0, 1.0)
					animation.track_set_imported(track_index, true)
					track_index += 1

					animation.add_track(Animation.TYPE_VALUE)
					animation.track_set_path(track_index, node_path + fade_index_path)
					animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
					animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
					animation.track_set_interpolation_loop_wrap(track_index, false)
					animation.track_insert_key(track_index, 0.0, 0.0)
					animation.track_set_imported(track_index, true)
					track_index += 1

			animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track_index, node_path + "/%s:top_level" % NODE_NAMES[3])
			animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
			animation.track_set_interpolation_loop_wrap(track_index, false)
			animation.track_set_imported(track_index, true)
			animation.track_set_enabled(track_index, false)
			track_index += 1

			animation.add_track(Animation.TYPE_VALUE)
			if not collision_shape is CollisionShape3D:
				animation.track_set_enabled(track_index, false)
			animation.track_set_path(track_index, node_path + "/%s:disabled" % NODE_NAMES[4])
			animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
			animation.track_set_interpolation_loop_wrap(track_index, false)
			animation.track_insert_key(track_index, 0.0, true)
			animation.track_set_imported(track_index, true)
			track_index += 1

			for child in node.find_children("*", "CollisionShape3D", true, false):
				if child == collision_shape: continue
				if child.get_meta("_MAPPER_DISABLED", false): continue
				animation.add_track(Animation.TYPE_VALUE)
				animation.track_set_path(track_index, str(map.node.get_path_to(child)) + ":disabled")
				animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
				animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
				animation.track_set_interpolation_loop_wrap(track_index, false)
				animation.track_insert_key(track_index, 0.0, false)
				animation.track_set_imported(track_index, true)
				track_index += 1

			animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track_index, node_path + "/%s:top_level" % NODE_NAMES[4])
			animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
			animation.track_set_interpolation_loop_wrap(track_index, false)
			animation.track_set_imported(track_index, true)
			animation.track_set_enabled(track_index, false)
			animation.track_set_enabled(track_index, false)
			track_index += 1

			if occluder_instance is OccluderInstance3D:
				animation.add_track(Animation.TYPE_VALUE)
				animation.track_set_path(track_index, node_path + "/%s:visible" % NODE_NAMES[5])
				animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
				animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
				animation.track_set_interpolation_loop_wrap(track_index, false)
				animation.track_insert_key(track_index, 0.0, true)
				animation.track_set_imported(track_index, true)
				track_index += 1

		# inserting keys into the animation
		for index1 in range(data["nodes"].size()):
			var node: Node3D = data["nodes"][index1]
			var main_track_path := str(map.node.get_path_to(node)) + ":visible"
			var main_track_index := animation.find_track(main_track_path, Animation.TYPE_VALUE)
			for index2 in range(frames):
				var frame_time: float = data["frames"][index2] * data["frame_duration"]
				var fade_frames_min := 1 + mini(mini(index2, (frames - index2 - 1)), fade_frames)
				var is_visible := false
				match animation.loop_mode:
					Animation.LOOP_NONE:
						for i in range(fade_frames_min):
							if index2 == (index1 + i):
								if i == 0 or data["fade_before"]:
									is_visible = true
							if index2 == (index1 - i):
								if i == 0 or data["fade_after"]:
									is_visible = true
					Animation.LOOP_LINEAR:
						for i in range(fade_frames if data["fade_loop"] else fade_frames_min):
							if index2 == posmod(index1 + i, frames):
								if i == 0 or data["fade_before"]:
									is_visible = true
							if index2 == posmod(index1 - i, frames):
								if i == 0 or data["fade_after"]:
									is_visible = true
					Animation.LOOP_PINGPONG:
						for i in range(fade_frames_min):
							if index2 == posmod(index1 + i, frames):
								is_visible = true
							if index2 == posmod(index1 - i, frames):
								is_visible = true
				animation.track_insert_key(main_track_index, frame_time, is_visible)

			# inserting mesh instance track keys
			var mesh_track_path := str(map.node.get_path_to(node)) + "/%s:visible" % NODE_NAMES[2]
			var mesh_track_index := animation.find_track(mesh_track_path, Animation.TYPE_VALUE)
			if not mesh_track_index < 0:
				for index2 in range(frames):
					var frame_time: float = data["frames"][index2] * data["frame_duration"]
					animation.track_insert_key(mesh_track_index, frame_time, bool(index2 == index1))

			# inserting fade instance track keys
			var fade_track_path := str(map.node.get_path_to(node)) + "/%s:visible" % NODE_NAMES[3]
			var fade_track_index := animation.find_track(fade_track_path, Animation.TYPE_VALUE)
			if not fade_track_index < 0:
				for index2 in range(frames):
					var frame_time: float = data["frames"][index2] * data["frame_duration"]
					animation.track_insert_key(fade_track_index, frame_time, bool(index2 != index1))

			# inserting visibility tracks keys for other nodes
			if not mesh_track_index < 0 and not fade_track_index < 0:
				for track_index in range(mesh_track_index + 1, fade_track_index):
					for index2 in range(frames):
						var frame_time: float = data["frames"][index2] * data["frame_duration"]
						animation.track_insert_key(track_index, frame_time, bool(index2 == index1))

			# inserting fade instance shader material tracks keys
			if not mesh_track_index < 0 and not fade_track_index < 0:
				var default_priority: int = 0
				var empty_track_path := str(map.node.get_path_to(node)) + "/%s:top_level" % NODE_NAMES[3]
				var empty_track_index := animation.find_track(empty_track_path, Animation.TYPE_VALUE)
				for track_index in range(fade_track_index + 1, empty_track_index):
					var c: int = track_index - (fade_track_index + 1)
					var track_offset: int = (fade_track_index + 1) + int(c / 3.0) * 3
					if track_index == track_offset:
						default_priority = animation.track_get_key_value(track_offset + 0, 0)

					for index2 in range(frames):
						var frame_time: float = data["frames"][index2] * data["frame_duration"]
						var fade_frames_min := 1 + mini(mini(index2, (frames - index2 - 1)), fade_frames)
						var priority := int(default_priority)
						var fade_index: float = 0.0
						var fade: float = 1.0
						match animation.loop_mode:
							Animation.LOOP_NONE:
								for i in range(fade_frames_min):
									if index2 == (index1 + i):
										if i == 0 or data["fade_before"]:
											priority = default_priority - i
											fade = fade_percentages[i]
										if i != 0 and data["fade_before"]:
											fade_index = float(-i)
									if index2 == (index1 - i):
										if i == 0 or data["fade_after"]:
											priority = default_priority - i
											fade = fade_percentages[i]
										if i != 0 and data["fade_after"]:
											fade_index = float(i)
							Animation.LOOP_LINEAR:
								for i in range(fade_frames if data["fade_loop"] else fade_frames_min):
									if index2 == posmod(index1 + i, frames):
										if i == 0 or data["fade_before"]:
											priority = default_priority - i
											fade = fade_percentages[i]
										if i != 0 and data["fade_before"]:
											fade_index = float(-i)
									if index2 == posmod(index1 - i, frames):
										if i == 0 or data["fade_after"]:
											priority = default_priority - i
											fade = fade_percentages[i]
										if i != 0 and data["fade_after"]:
											fade_index = float(i)
							Animation.LOOP_PINGPONG:
								for i in range(fade_frames_min):
									if index2 == posmod(index1 + i, frames):
										priority = default_priority - i
										fade = fade_percentages[i]
										if i != 0: fade_index = float(-i)
									if index2 == posmod(index1 - i, frames):
										priority = default_priority - i
										fade = fade_percentages[i]
										if i != 0: fade_index = float(-i)
						if c % 3 == 0: animation.track_insert_key(track_index, frame_time, priority)
						elif c % 3 == 1: animation.track_insert_key(track_index, frame_time, fade)
						elif c % 3 == 2: animation.track_insert_key(track_index, frame_time, fade_index)

			# inserting collision shape track keys
			var collision_track_path := str(map.node.get_path_to(node)) + "/%s:disabled" % NODE_NAMES[4]
			var collision_track_index := animation.find_track(collision_track_path, Animation.TYPE_VALUE)
			if not collision_track_index < 0:
				for index2 in range(frames):
					var frame_time: float = data["frames"][index2] * data["frame_duration"]
					animation.track_insert_key(collision_track_index, frame_time, not bool(index2 == index1))

			# inserting collision shape tracks keys for other nodes
			var empty_track_path2 := str(map.node.get_path_to(node)) + "/%s:top_level" % NODE_NAMES[4]
			var empty_track_index2 := animation.find_track(empty_track_path2, Animation.TYPE_VALUE)
			if not collision_track_index < 0 and not empty_track_index2 < 0:
				for track_index in range(collision_track_index + 1, empty_track_index2):
					for index2 in range(frames):
						var frame_time: float = data["frames"][index2] * data["frame_duration"]
						animation.track_insert_key(track_index, frame_time, bool(index2 != index1))

			# inserting occluder instance track keys
			var occluder_track_path := str(map.node.get_path_to(node)) + "/%s:visible" % NODE_NAMES[5]
			var occluder_track_index := animation.find_track(occluder_track_path, Animation.TYPE_VALUE)
			if not occluder_track_index < 0:
				for index2 in range(frames):
					var frame_time: float = data["frames"][index2] * data["frame_duration"]
					animation.track_insert_key(occluder_track_index, frame_time, bool(index2 == index1))

			# enabling autoplay nodes
			if (index1 == 0 and is_autoplay):
				var collision_shape := node.find_child(NODE_NAMES[4], false, false)
				if collision_shape is CollisionShape3D: collision_shape.disabled = false
				for child in node.find_children("*", "CollisionShape3D", true, false):
					if child == collision_shape: continue
					if child.get_meta("_MAPPER_DISABLED", false): continue
					child.disabled = false
				node.visible = true

			# clearing some leftover metadata
			for child in node.find_children("*", "CollisionShape3D", true, false):
				if child.has_meta("_MAPPER_DISABLED"): child.remove_meta("_MAPPER_DISABLED")

		# removing empty tracks
		var removed_tracks: int = 0
		var tracks_to_remove: Array = []
		for track_index in animation.get_track_count():
			if not animation.track_is_enabled(track_index):
				tracks_to_remove.append(track_index)
		for track_index in tracks_to_remove:
			animation.remove_track(track_index - removed_tracks)
			removed_tracks += 1

		# finishing animation and adding it to the library
		MapperUtilities.remove_repeating_animation_keys(animation)
		animation_library.add_animation(name, animation)
