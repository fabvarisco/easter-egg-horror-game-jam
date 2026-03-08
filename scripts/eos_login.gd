extends Node
class_name EOSLogin
## EOS Login Helper
## This script handles EOS initialization and matchmaking

signal login_completed(success: bool)
signal match_found
signal lobby_created(code: String)
signal connection_failed(reason: String)

var local_user_id: String = ""
var is_server: bool = false
var eos_setup: bool = false
var local_lobby: HLobby
var peer: EOSGMultiplayerPeer

const GAME_BUCKET_ID := "easteregghorror"
const MAX_PLAYERS := 4


func _ready() -> void:
	if ClassDB.class_exists("EOSGMultiplayerPeer"):
		peer = EOSGMultiplayerPeer.new()


func setup_eos_async() -> bool:
	if eos_setup:
		return true

	if not ClassDB.class_exists("EOSGMultiplayerPeer"):
		push_error("[EOS] Plugin não disponível")
		return false

	print("[EOS] Inicializando...")

	# 1. Initialize EOS Platform
	var init_opts = EOS.Platform.InitializeOptions.new()
	init_opts.product_name = EOSConfig.PRODUCT_NAME
	init_opts.product_version = EOSConfig.PRODUCT_VERSION

	var init_result = EOS.Platform.PlatformInterface.initialize(init_opts)
	if init_result != EOS.Result.Success and init_result != EOS.Result.AlreadyConfigured:
		push_error("[EOS] Falha ao inicializar: " + EOS.result_str(init_result))
		login_completed.emit(false)
		return false

	print("[EOS] SDK inicializado")

	# 2. Create EOS Platform
	var create_opts = EOS.Platform.CreateOptions.new()
	create_opts.product_id = EOSConfig.PRODUCT_ID
	create_opts.sandbox_id = EOSConfig.SANDBOX_ID
	create_opts.deployment_id = EOSConfig.DEPLOYMENT_ID
	create_opts.client_id = EOSConfig.CLIENT_ID
	create_opts.client_secret = EOSConfig.CLIENT_SECRET
	create_opts.encryption_key = EOSConfig.ENCRYPTION_KEY

	var create_result = EOS.Platform.PlatformInterface.create(create_opts)
	if not create_result:
		push_error("[EOS] Falha ao criar plataforma")
		login_completed.emit(false)
		return false

	print("[EOS] Plataforma criada")

	# 3. Setup logging
	EOS.get_instance().logging_interface_callback.connect(_on_eos_log)
	EOS.Logging.set_log_level(EOS.Logging.LogCategory.AllCategories, EOS.Logging.LogLevel.Info)

	# 4. Setup peer callbacks
	if peer:
		peer.peer_connected.connect(_on_peer_connected)
		peer.peer_disconnected.connect(_on_peer_disconnected)

	# 5. Login anonymously
	print("[EOS] Fazendo login anônimo...")
	var login_success = await HAuth.login_anonymous_async("Player")
	if not login_success:
		push_error("[EOS] Falha no login anônimo")
		login_completed.emit(false)
		return false

	local_user_id = HAuth.product_user_id
	eos_setup = true
	print("[EOS] Login OK! PUID: ", local_user_id)
	login_completed.emit(true)
	return true


func find_match_async() -> void:
	if not eos_setup:
		var success = await setup_eos_async()
		if not success:
			connection_failed.emit("Falha ao configurar EOS")
			return

	print("[EOS] Buscando partida...")

	# Try to find existing lobbies
	var lobbies = await HLobbies.search_by_bucket_id_async(GAME_BUCKET_ID)

	if lobbies and lobbies.size() > 0:
		print("[EOS] Lobby encontrado, entrando...")
		await _join_lobby(lobbies[0])
	else:
		print("[EOS] Nenhum lobby, criando...")
		await _create_lobby()


func _create_lobby() -> void:
	var create_opts := EOS.Lobby.CreateLobbyOptions.new()
	create_opts.bucket_id = GAME_BUCKET_ID
	create_opts.max_lobby_members = MAX_PLAYERS

	local_lobby = await HLobbies.create_lobby_async(create_opts)
	if not local_lobby:
		push_error("[EOS] Falha ao criar lobby")
		connection_failed.emit("Falha ao criar lobby")
		return

	# Start P2P server
	var result := peer.create_server(GAME_BUCKET_ID)
	if result != OK:
		push_error("[EOS] Falha ao criar servidor P2P")
		connection_failed.emit("Falha ao criar servidor")
		return

	multiplayer.multiplayer_peer = peer
	is_server = true

	var code := _generate_lobby_code(local_lobby.lobby_id)
	print("[EOS] Lobby criado! Código: ", code)
	lobby_created.emit(code)


func _join_lobby(lobby: HLobby) -> void:
	var joined = await HLobbies.join_by_id_async(lobby.lobby_id)
	if not joined:
		push_error("[EOS] Falha ao entrar no lobby")
		connection_failed.emit("Falha ao entrar no lobby")
		return

	# Connect as P2P client
	var result := peer.create_client(GAME_BUCKET_ID, lobby.owner_product_user_id)
	if result != OK:
		push_error("[EOS] Falha ao conectar P2P")
		connection_failed.emit("Falha na conexão P2P")
		return

	multiplayer.multiplayer_peer = peer
	local_lobby = joined
	is_server = false
	print("[EOS] Conectado ao lobby!")
	match_found.emit()


func leave_match() -> void:
	if peer:
		peer.close()

	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null

	if local_lobby:
		if is_server:
			await local_lobby.destroy_async()
		else:
			await local_lobby.leave_async()
		local_lobby = null


func _generate_lobby_code(lobby_id: String) -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var hash_val := hash(lobby_id)
	var code := ""
	for i in range(6):
		code += chars[abs(hash_val >> (i * 5)) % chars.length()]
	return code


func _on_eos_log(msg) -> void:
	msg = EOS.Logging.LogMessage.from(msg) as EOS.Logging.LogMessage
	print("[EOS SDK] %s | %s" % [msg.category, msg.message])


func _on_peer_connected(peer_id: int) -> void:
	print("[EOS] Peer conectado: ", peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[EOS] Peer desconectado: ", peer_id)


func _exit_tree() -> void:
	leave_match()
