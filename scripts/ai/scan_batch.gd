class_name ScanBatch
extends Node
## Look rounds of bots (and squads) run together once a frame, the per-target work on
## threads (PRESTANDA_PLAN.md, 2026-11-22). A scanner (BotController, Squad) registers.
## Each frame, first in _process (before every other node's _process, so nothing moves in
## between):
##   1. BEGIN (main thread): every scanner whose round is due (scan_due) prepares it
##      (scan_begin: what to look at, as jobs: scan_job_count); then every tank and soldier
##      the threads may read has its global transform resolved here (Node3D works them out
##      lazily, and two threads doing that at once read wrong values: 5 in 2 400 in a test).
##   2. WORKERS (threads): Worker nodes in sub-thread process groups share the jobs of all
##      due scanners (scan_job: one target's look, its sight lines cast right there). They
##      only read nodes (positions) and cast rays in a space fetched on the main thread,
##      and write their job's own result slot. A WorkerThreadPool task can't do this:
##      Godot lets only thread groups read nodes.
##   3. END (main thread): scan_end, the bookkeeping (signals, memories, target choice).
## A scanner's answers are the same as one round done all on the main thread.

const ORDER: int = -1000000

## The registered scanners (nodes with scan_due/scan_begin/scan_job_count/scan_job/scan_end).
static var _scanners: Array[Node] = []
static var _begin: ScanBatch = null
static var _active: Array[Node] = []
## This frame's jobs: scanner and its job index.
static var _job_scanner: Array[Node] = []
static var _job_index: PackedInt32Array = PackedInt32Array()
static var _workers: int = 1
## False: every due round runs whole on the main thread, with its prefetch, as before the
## batch (for A/B measurements: tools/perf/growth_probe.gd ab=threads).
static var threaded: bool = true

var _is_end: bool = false


## Called by a scanner in its _ready.
static func register(scanner: Node) -> void:
	if not _scanners.has(scanner):
		_scanners.append(scanner)
	if _begin != null and is_instance_valid(_begin):
		return
	_begin = ScanBatch.new()
	_begin.name = "ScanBatchBegin"
	_begin.process_thread_group = Node.PROCESS_THREAD_GROUP_MAIN_THREAD
	_begin.process_thread_group_order = ORDER
	_workers = clampi(OS.get_processor_count() - 1, 1, 16)
	for k: int in _workers:
		var worker := Worker.new()
		worker.slot = k
		_begin.add_child(worker)
	var end := ScanBatch.new()
	end.name = "ScanBatchEnd"
	end._is_end = true
	end.process_thread_group = Node.PROCESS_THREAD_GROUP_MAIN_THREAD
	end.process_thread_group_order = ORDER + 2
	_begin.add_child(end)
	scanner.get_tree().root.add_child.call_deferred(_begin)


func _exit_tree() -> void:
	if _begin == self:
		_begin = null


func _process(_delta: float) -> void:
	if _is_end:
		for scanner_v: Variant in _active:
			var scanner: Node = (scanner_v as Node) if is_instance_valid(scanner_v) else null
			if is_instance_valid(scanner):
				scanner.call("scan_end")
		_active.clear()
		_job_scanner.clear()
		_job_index.clear()
		return
	_active.clear()
	_job_scanner.clear()
	_job_index.clear()
	var i: int = 0
	while i < _scanners.size():
		var scanner_v: Variant = _scanners[i]
		var scanner: Node = (scanner_v as Node) if is_instance_valid(scanner_v) else null
		if not is_instance_valid(scanner):
			_scanners.remove_at(i)
			continue
		i += 1
		if not scanner.is_inside_tree():
			continue
		if not bool(scanner.call("scan_due")):
			continue
		if not threaded:
			scanner.call("scan_begin", false)
			for j: int in int(scanner.call("scan_job_count")):
				scanner.call("scan_job", j)
			scanner.call("scan_end")
			continue
		scanner.call("scan_begin")
		_active.append(scanner)
		for j: int in int(scanner.call("scan_job_count")):
			_job_scanner.append(scanner)
			_job_index.append(j)
	if not _active.is_empty():
		_resolve_transforms()


## Works out every global transform the threads read (see the class comment).
func _resolve_transforms() -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t != null:
			t.resolve_sight_transforms()
	for node: Node in get_tree().get_nodes_in_group("squads"):
		var s := node as Squad
		if s != null:
			s.resolve_sight_transforms()


## One thread's share of the jobs (every _workers-th), in a sub-thread process group run
## right after BEGIN.
class Worker extends Node:
	var slot: int = 0

	func _ready() -> void:
		process_thread_group = Node.PROCESS_THREAD_GROUP_SUB_THREAD
		process_thread_group_order = ScanBatch.ORDER + 1

	func _process(_delta: float) -> void:
		var n: int = ScanBatch._job_index.size()
		var j: int = slot
		while j < n:
			ScanBatch._job_scanner[j].call("scan_job", ScanBatch._job_index[j])
			j += ScanBatch._workers
