extends Camera3D

func camera_raycast(camera: Camera3D, distance: float = 1000.0) -> Dictionary:
	var viewport = get_viewport()
	var screen_center = viewport.get_visible_rect().size * 0.5

	var origin = camera.project_ray_origin(screen_center)
	var direction = camera.project_ray_normal(screen_center)

	var query = PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * distance
	)

	var space_state = get_world_3d().direct_space_state
	return space_state.intersect_ray(query)