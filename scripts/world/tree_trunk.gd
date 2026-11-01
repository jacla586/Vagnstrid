class_name TreeTrunk
extends StaticBody3D
## The standing trunk's collider. Forwards shell hits to its BreakableTree.


func on_shell_hit(shell_data: ShellData, _point: Vector3, _normal: Vector3,
		velocity: Vector3, _shape: int = -1) -> HitResult:
	var tree := get_parent() as BreakableTree
	return tree.on_shell_hit(shell_data, velocity) if tree != null else null
