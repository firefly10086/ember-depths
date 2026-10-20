extends SceneTree
## Run with a real renderer to also compare retained geometry against cached quads.
var failures: Array[String] = []
var game: Node2D

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in 5: await process_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	var room: DungeonRoom = game.room
	var hud: Control = game.hud
	var builds: int = hud.cache_builds
	var room_builds: int = room.static_builds
	var styles_count: int = hud.styles.size()
	var state := room.rng.state
	var appearance := room.tiles.duplicate(true)
	await settle()
	verify(hud.cache_builds == builds, "Static menu does not rebuild HUD")
	verify(room.static_builds == room_builds, "Room static cache does not rebuild per frame")
	verify(room.static_viewport.world_2d != root.world_2d, "Room cache has an isolated canvas")
	verify(hud.cache_layer.get_viewport() == root, "HUD retains commands on the native window canvas")
	room.set_locked(true)
	await settle()
	verify(room.static_builds == room_builds + 1, "Door state invalidates the static cache once")
	room.set_locked(true)
	verify(room.static_builds == room_builds + 1, "Repeated lock value does not rebuild cache")
	verify(room.rng.state == state and room.tiles == appearance, "Cache rebuild preserves RNG and tile appearance")
	builds = hud.cache_builds
	game.player.hp -= 1
	await settle()
	verify(hud.cache_builds == builds + 1, "HP change refreshes HUD once")
	builds = hud.cache_builds
	game.player.damage += 1
	game.player.speed += 1
	game.player.attack_range += 1
	game.player.attack_cooldown *= 0.9
	game.permanent_shards += 1
	game.kills += 1
	game.muted = not game.muted
	await settle()
	verify(hud.cache_builds == builds + 1, "Multiple stat events coalesce into a single refresh")
	builds = hud.cache_builds
	game.elapsed = 12.0
	hud._process(0.5)
	verify(int(hud.displayed_elapsed) == 12 and hud.cache_builds == builds + 1, "Timer refreshes on half-second ticks")
	verify(hud.styles.size() == styles_count, "HUD redraws reuse warmed styles")
	game.mode = "playing"
	game.transition = 0
	game.player.set_physics_process(false)
	game.set_process(false)
	room.active = false
	await settle()
	builds = hud.cache_builds
	await settle()
	verify(hud.cache_builds == builds, "Idle play and cursor do not rebuild HUD")
	game._offer_reward()
	await settle()
	verify(hud.cache_builds > builds, "Reward mode invalidates HUD")
	game.mode = "paused"
	await settle()
	if DisplayServer.get_name() != "headless":
		await benchmark(room, "paused")
		game.mode = "playing"
		await settle()
		await benchmark(room, "idle_play")
	game.queue_free()
	await settle()
	if failures.is_empty():
		print("PASS: cache invalidation, RNG preservation, HUD events, timer, style reuse and idle stability")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)

func render_info() -> Dictionary:
	return {
		"primitives": root.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"draw_calls": root.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
	}

func benchmark(room: DungeonRoom, scenario: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var cached := render_info()
	# Replay the room's static draw routine, keeping native-resolution HUD text.
	# This gives a reproducible same-scene geometry comparison, not a GPU power claim.
	room.cached_sprite.hide()
	var room_direct := DungeonRoom.RoomLayer.new()
	room_direct.room = room
	room_direct.static_content = true
	room.add_child(room_direct)
	await settle()
	await RenderingServer.frame_post_draw
	var direct := render_info()
	print("RENDER ", scenario, " cached=", cached, " direct_static_geometry=", direct)
	verify(cached.primitives < direct.primitives, "Cached textures reduce submitted primitives")
	room_direct.queue_free()
	room.cached_sprite.show()
