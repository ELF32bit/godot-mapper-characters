const MAPPER_GAMES: Dictionary = {
	"Generic": {
		"game_directory": "res://mapping/generic",
		"alternative_game_directories": ["res://mapping/quake"],
		"game_loader": MapperSettings.DEFAULT_GAME_LOADER,
	},
	"Quake": {
		"game_directory": "res://mapping/quake",
		"game_loader": MapperSettings.QUAKE_GAME_LOADER,
		"skip_material_affects_collision": false,
		"prefer_static_lighting": true,
	},
	"Characters": {
		"game_directory": "res://characters",
		"game_loader": MapperSettings.DEFAULT_GAME_LOADER,
		"world_entity_extra_brush_entities_enabled": false,
		"cast_shadow_meshes": false,
	},
}
