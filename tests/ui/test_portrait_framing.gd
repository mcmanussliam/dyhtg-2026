extends RefCounted
## Cosmetics share one camera per portrait style; tall hats may crop in face closeups.


func run(tree: SceneTree, check: Callable) -> void:
	for close_up in [true, false]:
		var expected_pose := Transform3D.IDENTITY
		var expected_size := 0.0
		for hat in CharacterHats.IDS:
			var portrait := ScoreCharacter.new()
			portrait.hat_id = hat
			portrait.close_up = close_up
			portrait.animated = false
			tree.root.add_child(portrait)
			var viewport := portrait.get_child(0) as SubViewport
			var camera := viewport.get_camera_3d()
			if hat == &"none":
				expected_pose = camera.transform
				expected_size = camera.size
			check.call(
				(
					camera.transform.is_equal_approx(expected_pose)
					and is_equal_approx(camera.size, expected_size)
				),
				"Portrait framing is independent of hat: %s, closeup=%s" % [hat, close_up]
			)
			portrait.free()
	await tree.process_frame
