class_name NetRelevance
extends RefCounted
## Which tanks go into a client's snapshot this tick. v1 sends every tank every time;
## for big games, far tanks can be sent less often here (e.g. every 2nd or 4th
## snapshot beyond 800 m) without touching anything else.


static func include(_tank: Tank, _peer: int, _snapshot: int, _viewer: Tank) -> bool:
	return true
