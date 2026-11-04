class_name NetRole
extends RefCounted
## Which side of the network this game runs on. Set by the Net autoload; plain scripts
## (also @tool ones, which run in the editor) read it here instead of touching Net.

enum Role { OFFLINE, HOST, CLIENT }

static var role: Role = Role.OFFLINE


static func is_client() -> bool:
	return role == Role.CLIENT


static func is_host() -> bool:
	return role == Role.HOST


static func is_online() -> bool:
	return role != Role.OFFLINE
