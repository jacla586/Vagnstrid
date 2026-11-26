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


## Client: a clock it runs on itself (mode clocks, countdowns) against the host's value,
## which is a packet's travel old. Taking it as it came set the clock back that much at
## every update (a countdown's seconds flickered). Kept unless they differ by `slack` s.
static func sync_clock(local: float, host: float, slack: float = 0.5) -> float:
	return host if absf(host - local) > slack else local
