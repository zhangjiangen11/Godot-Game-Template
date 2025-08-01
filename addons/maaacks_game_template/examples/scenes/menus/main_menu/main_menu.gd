extends MainMenu

@export var level_select_packed_scene: PackedScene
@export var confirm_new_game : bool = true

var level_select_scene : Node

func load_game_scene() -> void:
	GameStateExample.start_game()
	super.load_game_scene()

func new_game() -> void:
	if confirm_new_game and GameStateExample.has_game_state():
		%NewGameConfirmationDialog.popup_centered()
	else:
		GlobalState.reset()
		load_game_scene()

func _add_level_select_if_set() -> void: 
	if level_select_packed_scene == null: return
	if GameStateExample.get_levels_reached() <= 1 : return
	level_select_scene = level_select_packed_scene.instantiate()
	level_select_scene.hide()
	%LevelSelectContainer.call_deferred("add_child", level_select_scene)
	if level_select_scene.has_signal("level_selected"):
		level_select_scene.connect("level_selected", load_game_scene)
	%LevelSelectButton.show()

func _show_continue_if_set() -> void:
	if GameStateExample.has_game_state():
		%ContinueGameButton.show()

func _ready() -> void:
	super._ready()
	_add_level_select_if_set()
	_show_continue_if_set()

func _on_continue_game_button_pressed() -> void:
	GameStateExample.continue_game()
	load_game_scene()

func _on_level_select_button_pressed() -> void:
	_open_sub_menu(level_select_scene)

func _on_new_game_confirmation_dialog_confirmed() -> void:
	GlobalState.reset()
	load_game_scene()
