## Represents a unit on the game board.
## The board manages its position inside the game grid.
## The unit itself holds stats and a visual representation that moves smoothly in the game world.
@tool
class_name Unit
extends Path2D

## Emitted when the unit reached the end of a path along which it was walking.
signal walk_finished

enum Team {
	ALLY,
	ENEMY,
}

const FRAME_SIZE := Vector2i(64, 64)
const DIRECTION_NAMES := [&"down", &"left", &"right", &"up"]
const WALK_FRAMES := 3
const WALK_FPS := 8.0
const HEALTH_FILL_SIZE := Vector2i(36, 4)
const HEALTH_FRAME_SIZE := Vector2i(40, 8)

static var _health_bar_textures := {}

## Shared resource of type Grid, used to calculate map coordinates.
@export var grid: Resource
## Distance to which the unit can walk in cells.
@export var move_range := 6
## The unit's move speed when it's moving along a path.
@export var move_speed := 600.0
## Unit identifier used by the roster.
@export var unit_id := StringName("")
## Whether the unit belongs to the player or to the opposing force.
@export var team := Team.ALLY:
	set(value):
		team = value
		if not _sprite:
			await ready
		_apply_team_style()
## Sprite sheet used to build the directional idle/walk animations.
@export var sprite_frames: SpriteFrames:
	set(value):
		sprite_frames = value
		if not _sprite:
			await ready
		if sprite_frames:
			_sprite.sprite_frames = sprite_frames
			_play_current_animation()
		else:
			_apply_sprite_sheet()
@export var sprite_sheet: Texture2D:
	set(value):
		sprite_sheet = value
		if not _sprite:
			await ready
		_apply_sprite_sheet()
## Offset to apply to the unit sprite in pixels.
@export var sprite_offset := Vector2(0, -18):
	set(value):
		sprite_offset = value
		if not _sprite:
			await ready
		_apply_sprite_offset()
## Maximum HP shown by the FM2-inspired health bar.
@export var max_hp := 100:
	set(value):
		max_hp = max(1, value)
		current_hp = clamp(current_hp, 0, max_hp)
		if not _health_fill:
			await ready
		_update_health_bar()
## Current HP shown by the FM2-inspired health bar.
@export var current_hp := 100:
	set(value):
		current_hp = clamp(value, 0, max_hp)
		if not _health_fill:
			await ready
		_update_health_bar()

## Coordinates of the current cell the cursor moved to.
var cell := Vector2.ZERO:
	set(value):
		# When changing the cell's value, we don't want to allow coordinates outside
		#	the grid, so we clamp them
		cell = grid.grid_clamp(value)
## Toggles the "selected" animation on the unit.
var is_selected := false:
	set(value):
		is_selected = value
		if is_selected:
			_anim_player.play("selected")
		else:
			_anim_player.play("idle")

var _is_walking := false:
	set(value):
		_is_walking = value
		set_process(_is_walking)

var _facing := &"down"
var _last_walk_offset := Vector2.ZERO

@onready var _sprite: AnimatedSprite2D = $PathFollow2D/Sprite
@onready var _anim_player: AnimationPlayer = $AnimationPlayer
@onready var _path_follow: PathFollow2D = $PathFollow2D
@onready var _shadow: Sprite2D = $PathFollow2D/Shadow
@onready var _health_bar: Node2D = $PathFollow2D/HealthBar
@onready var _health_fill: Sprite2D = $PathFollow2D/HealthBar/Fill
@onready var _health_frame: Sprite2D = $PathFollow2D/HealthBar/Frame


func _ready() -> void:
	set_process(false)
	_path_follow.rotates = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_health_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_health_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	cell = grid.calculate_grid_coordinates(position)
	position = grid.calculate_map_position(cell)

	# We create the curve resource here because creating it in the editor prevents us from
	# moving the unit.
	if not Engine.is_editor_hint():
		curve = Curve2D.new()

	_apply_sprite_sheet()
	_apply_sprite_offset()
	_apply_team_style()
	_update_health_bar()
	_play_current_animation()


func _process(delta: float) -> void:
	_path_follow.progress += move_speed * delta
	var walk_delta := _path_follow.position - _last_walk_offset
	if walk_delta.length_squared() > 0.05:
		_set_facing_from_vector(walk_delta)
	_last_walk_offset = _path_follow.position

	if _path_follow.progress_ratio >= 1.0:
		_is_walking = false
		# Setting this value to 0.0 causes a Zero Length Interval error
		_path_follow.progress = 0.00001
		position = grid.calculate_map_position(cell)
		curve.clear_points()
		_last_walk_offset = Vector2.ZERO
		_play_current_animation()
		emit_signal("walk_finished")


## Starts walking along the `path`.
## `path` is an array of grid coordinates that the function converts to map coordinates.
func walk_along(path: PackedVector2Array) -> void:
	var points := PackedVector2Array([cell])
	for point in path:
		if points[-1] != point:
			points.append(point)

	if points.size() <= 1:
		return

	curve.clear_points()
	curve.add_point(Vector2.ZERO)
	for index in range(1, points.size()):
		curve.add_point(grid.calculate_map_position(points[index]) - position)
	cell = points[-1]
	_set_facing_from_vector(points[1] - points[0])
	_last_walk_offset = Vector2.ZERO
	_play_current_animation(true)
	_is_walking = true


func is_player_controlled() -> bool:
	return team == Team.ALLY


func _apply_sprite_sheet() -> void:
	if sprite_frames:
		_sprite.sprite_frames = sprite_frames
		_play_current_animation()
		return

	if not sprite_sheet:
		_sprite.sprite_frames = SpriteFrames.new()
		return

	_sprite.sprite_frames = _build_sprite_frames(sprite_sheet)
	_play_current_animation()


func _apply_sprite_offset() -> void:
	_sprite.position = sprite_offset
	_health_bar.position = sprite_offset + Vector2(-HEALTH_FRAME_SIZE.x / 2, -42)


func _apply_team_style() -> void:
	var textures := _get_health_bar_textures(team)
	_health_fill.texture = textures["fill"]
	_health_frame.texture = textures["frame"]
	_update_health_bar()


func _update_health_bar() -> void:
	if not _health_fill:
		return

	var ratio := float(current_hp) / float(max_hp)
	var visible_width := int(round(HEALTH_FILL_SIZE.x * ratio))
	_health_fill.visible = visible_width > 0
	_health_fill.region_enabled = true
	_health_fill.region_rect = Rect2(Vector2.ZERO, Vector2(visible_width, HEALTH_FILL_SIZE.y))


func _build_sprite_frames(texture: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()

	for direction_index in range(DIRECTION_NAMES.size()):
		var direction_name: StringName = DIRECTION_NAMES[direction_index]
		var idle_animation := "idle_%s" % direction_name
		var walk_animation := "walk_%s" % direction_name

		frames.add_animation(idle_animation)
		frames.set_animation_loop(idle_animation, true)
		frames.add_frame(idle_animation, _create_atlas_frame(texture, direction_index, 0))

		frames.add_animation(walk_animation)
		frames.set_animation_speed(walk_animation, WALK_FPS)
		frames.set_animation_loop(walk_animation, true)
		for frame_index in range(1, WALK_FRAMES + 1):
			frames.add_frame(walk_animation, _create_atlas_frame(texture, direction_index, frame_index))

	return frames


func _create_atlas_frame(texture: Texture2D, row: int, column: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2(column * FRAME_SIZE.x, row * FRAME_SIZE.y), FRAME_SIZE)
	return atlas


func _play_current_animation(is_walking := false) -> void:
	if not _sprite.sprite_frames:
		return

	var animation := "%s_%s" % ["walk" if is_walking else "idle", _facing]
	if _sprite.sprite_frames.has_animation(animation):
		_sprite.play(animation)


func _set_facing_from_vector(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		_facing = &"right" if direction.x > 0.0 else &"left"
	else:
		_facing = &"down" if direction.y > 0.0 else &"up"

	if _is_walking:
		_play_current_animation(true)
	else:
		_play_current_animation()


func _get_health_bar_textures(team_value: int) -> Dictionary:
	if _health_bar_textures.has(team_value):
		return _health_bar_textures[team_value]

	var palette := _get_team_bar_palette(team_value)
	var textures := {
		"fill": _create_health_fill_texture(palette["fill_start"], palette["fill_end"]),
		"frame": _create_health_frame_texture(palette["accent"]),
	}
	_health_bar_textures[team_value] = textures
	return textures


func _get_team_bar_palette(team_value: int) -> Dictionary:
	match team_value:
		Team.ENEMY:
			return {
				"fill_start": Color8(255, 213, 112),
				"fill_end": Color8(201, 57, 43),
				"accent": Color8(132, 31, 19),
			}
		_:
			return {
				"fill_start": Color8(142, 243, 221),
				"fill_end": Color8(76, 178, 103),
				"accent": Color8(24, 88, 74),
			}


func _create_health_fill_texture(start_color: Color, end_color: Color) -> ImageTexture:
	var image := Image.create(HEALTH_FILL_SIZE.x, HEALTH_FILL_SIZE.y, false, Image.FORMAT_RGBA8)

	for x in range(HEALTH_FILL_SIZE.x):
		var t := float(x) / float(max(1, HEALTH_FILL_SIZE.x - 1))
		var base := start_color.lerp(end_color, t)
		for y in range(HEALTH_FILL_SIZE.y):
			var tint := 1.15 if y == 0 else 0.82 if y == HEALTH_FILL_SIZE.y - 1 else 1.0
			image.set_pixel(
				x,
				y,
				Color(
					clampf(base.r * tint, 0.0, 1.0),
					clampf(base.g * tint, 0.0, 1.0),
					clampf(base.b * tint, 0.0, 1.0),
					1.0
				)
			)

	return ImageTexture.create_from_image(image)


func _create_health_frame_texture(accent: Color) -> ImageTexture:
	var image := Image.create(HEALTH_FRAME_SIZE.x, HEALTH_FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	var border := Color8(17, 22, 28)
	var background := Color8(32, 38, 46, 224)

	image.fill(Color(0, 0, 0, 0))
	for x in range(HEALTH_FRAME_SIZE.x):
		for y in range(HEALTH_FRAME_SIZE.y):
			var color := background
			if x == 0 or y == 0 or x == HEALTH_FRAME_SIZE.x - 1 or y == HEALTH_FRAME_SIZE.y - 1:
				color = border
			elif y == 1:
				color = accent
			elif y == HEALTH_FRAME_SIZE.y - 2:
				color = Color8(13, 16, 20)
			image.set_pixel(x, y, color)

	return ImageTexture.create_from_image(image)
