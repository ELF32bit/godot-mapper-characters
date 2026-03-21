@tool
extends AnimationPlayer

@export var update_cache: int = 0:
	set(value):
		if value > 0 and update_cache != value:
			var _mode: int = 0
			var _animation: Animation = null
			var _name := StringName(current_animation)
			var _time := float(current_animation_position)
			var _length := float(current_animation_length)
			if has_animation(_name): _animation = get_animation(_name)
			if _animation: _mode = _animation.loop_mode
			update_cache = value
			if _mode == 2:
				push_error("Cache fix does not support LOOP_PINGPONG mode")
			elif _animation:
				stop(false)
				call_deferred("clear_caches")
				call_deferred("seek", _time, true)
				call_deferred("play", _name)
