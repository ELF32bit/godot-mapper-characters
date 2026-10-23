extends MapperUtilities

@warning_ignore("unused_parameter")
static func build(map: MapperMap, entity: MapperEntity) -> Node:
	for property in entity.properties:
		var value: String = entity.properties[property]
		entity.properties[property] = value.replace("'", '"')
	return null
