class_name NetReplicator
extends Node
## Host: sends every client one snapshot packet per SNAPSHOT_TICKS physics ticks (20 Hz).
## Built per recipient: NetRelevance picks the tanks, and the recipient's own tank adds
## its owner data (hp, modules, reload). Packet: type u8, tick u32, count u8, states.

const SNAPSHOT_TICKS: int = 3

var game: NetGame
var _tick: int = 0
var _snapshot: int = 0


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % SNAPSHOT_TICKS != 0 or game == null:
		return
	_snapshot += 1
	for peer: int in multiplayer.get_peers():
		var viewer: Tank = game.tank_of_peer(peer)
		var buf := StreamPeerBuffer.new()
		buf.put_u8(NetSession.PACKET_SNAPSHOT)
		buf.put_u32(_tick)
		var count_at: int = buf.get_position()
		buf.put_u8(0)
		var count: int = 0
		for net_id: int in game.tanks:
			var tank: Tank = game.tanks[net_id]
			if not is_instance_valid(tank) or not NetRelevance.include(tank, peer, _snapshot, viewer):
				continue
			tank.get_net_state(game.owners.get(net_id, 0) == peer).write(buf)
			count += 1
			if count == 255:
				break
		var bytes: PackedByteArray = buf.data_array
		bytes[count_at] = count
		NetSession.instance.send_raw(bytes, peer, NetSession.CH_SNAPSHOT)
