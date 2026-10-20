extends SceneTree
## Capture native window text with a real renderer at 2x scale.
const OUTPUT_DIR := "res://build/display-qa"
var game: Node2D
var capture_failed := false

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw

func capture(file_name: String) -> void:
	await settle()
	var image := root.get_texture().get_image()
	if image.is_empty() or image.save_png(OUTPUT_DIR.path_join(file_name)) != OK:
		capture_failed = true
		push_error("Could not capture " + file_name)
	else:
		print("CAPTURE ", file_name, " ", image.get_size())
		if file_name == "game-fixed.png":
			image.get_region(Rect2i(1950, 280, 520, 380)).save_png(OUTPUT_DIR.path_join("text-detail.png"))

func freeze_scene() -> void:
	game.set_process(false)
	game.player.set_physics_process(false)
	game.room.active = false
	game.room.set_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Display capture requires a real rendering driver.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	print("SCREEN ", DisplayServer.screen_get_size(), " DPI ", DisplayServer.screen_get_dpi())
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1280, 800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(2560, 1600)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.muted = true
	game.rng.seed = 618
	game._generate_floor()
	freeze_scene()
	await settle()
	var hud: Control = game.hud
	print("DISPLAY FONT ", hud.font.get_font_name(), " direct window canvas; minimum size ", hud.MIN_FONT_SIZE)
	await capture("title-fixed.png")
	game.new_run()
	var neighbor: int = game.rooms[0].doors.values()[0]
	game._enter_room(neighbor, Vector2i.ZERO)
	game.transition = 0
	game.player.position = Vector2(448, 332)
	game.player.facing = Vector2(1, -0.3).normalized()
	game.player.swing_direction = game.player.facing
	game.player.swing = 0.12
	game.player.queue_redraw()
	freeze_scene()
	await capture("game-fixed.png")
	game._offer_reward()
	await capture("reward-fixed.png")
	game.floor_number = 10
	game._generate_floor()
	for i in game.rooms.size():
		if game.rooms[i].kind == "shop":
			game._enter_room(i, Vector2i.ZERO)
			break
	game.transition = 0
	game.mode = "playing"
	game.currency = 650
	game.player.position = DungeonRoom.CENTER
	game.interact()
	game.set_shop_page(1)
	freeze_scene()
	await capture("shop-fixed.png")
	game.queue_free()
	await settle()
	if not capture_failed: print("PASS: direct-window 2560x1600 title, gameplay, rewards and shop captures")
	quit(1 if capture_failed else 0)
