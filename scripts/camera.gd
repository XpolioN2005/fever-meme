extends Camera3D

func _unhandled_input(event):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            handle_click(event.position)


func handle_click(mouse_pos: Vector2):
    var origin = project_ray_origin(mouse_pos)
    var direction = project_ray_normal(mouse_pos)

    var query = PhysicsRayQueryParameters3D.create(
        origin,
        origin + direction * 3.0
    )

    var hit = get_world_3d().direct_space_state.intersect_ray(query)

    if hit.is_empty():
        return

    var collider = hit.get("collider")

    if collider == null:
        return

    if collider.is_in_group("btn") and collider.has_method("press"):
        collider.press()