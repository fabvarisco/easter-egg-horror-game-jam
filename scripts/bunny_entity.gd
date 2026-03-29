extends Node3D
class_name bunny_entity 

enum State { DORMANT, SPAWNING, SEARCHING, LEAVING, APPROACHING, KILLING }

@export var bunny_wake_up_sound:AudioStream 
@onready var model: Node3D = $model


const SPAWN_DISTANCE: float = 10.0  
const WATCH_DISTANCE: float = 20.0  
const APPROACH_DISTANCES: Array[float] = [15.0, 8.0, 3.0]  
const DETECTION_RANGE: float = 30.0  
const APPROACH_SPEED: float = 15.0
const SHAKE_INTENSITY: float = 0.3
const SHAKE_DURATION: float = 0.5
const RESPAWN_DELAY: float = 1.0
const IDLE_TIMEOUT: float = 10.0 
const ATTACK_RANGE: float = 4.0 


var _state: State = State.DORMANT
var _target_player: Node3D = null
var _approach_count: int = 0
var _blink_timer: float = 0.0
var _is_blinking: bool = false
var _blink_phase_timer: float = 0.0
var _fixed_rotation: float = 0.0 
var _idle_timer: float = 0.0 

signal player_killed(player: Node3D)
signal all_players_dead

func _play_kill_scene(_killed_player: Node3D) -> void:
	pass

func _kill_player() -> void:
	_state = State.KILLING

	var killed_player := _target_player

	if killed_player and killed_player.has_method("die"):
		killed_player.die()
		_play_kill_scene(killed_player)

		if _is_multiplayer_active() and multiplayer.is_server():
			var host_manager := get_node_or_null("/root/HostManager")
			if host_manager:
				var player_id := int(killed_player.name)
				host_manager.bunny_kill_player(player_id)

	player_killed.emit(killed_player)

	if model:
		model.visible = true

	# Wait a moment then check for more players
	await get_tree().create_timer(1.0).timeout
	_hunt_next_player()


func _is_multiplayer_active() -> bool:
	# Check if we're actually in a multiplayer game, not just having EOS plugin loaded
	var single_player := get_tree().get_first_node_in_group("player")
	if single_player:
		return false  # Singleplayer mode

	return multiplayer.has_multiplayer_peer() and \
		   multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _hunt_next_player() -> void:
	_target_player = null
	_approach_count = 0

	# Find remaining alive players
	var alive_players := _get_alive_players()

	if alive_players.is_empty():
		# No more players - game over
		all_players_dead.emit()
		_state = State.DORMANT
		visible = false
		return

	# Reset and hunt next player
	_target_player = alive_players[0]
	_start_spawn_sequence()

func _get_alive_players() -> Array[Node]:
	var alive: Array[Node] = []
	var players := get_tree().get_nodes_in_group("players")

	for player in players:
		if player.has_method("is_dead") and not player.is_dead():
			alive.append(player)

	# Also check singular "player" group
	var single_player := get_tree().get_first_node_in_group("player")
	if single_player and single_player.has_method("is_dead") and not single_player.is_dead():
		if not alive.has(single_player):
			alive.append(single_player)

	return alive

func _spawn_at_distance(_distance: float) -> void:
	pass  # Override in child class

func _start_spawn_sequence() -> void:
	pass  # Override in child class
