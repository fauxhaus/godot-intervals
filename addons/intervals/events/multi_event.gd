@tool
@icon("res://addons/intervals/icons/multi_event.png")
extends Event
class_name MultiEvent
## A MultiEvent contains multiple events and can be used for advanced, dynamic cutscenes.

signal editor_refresh

## The events that the MultiEvent keeps track of.
@export_storage var events: Array[Event] = []

## Dictionary of stored event connections (from outgoing event branch x to 1 event input target)
## Dictionary[Event, Dict[int, Array[Event]]]
@export_storage var event_connections := {}

## Editor storage for event positions.
## Dictionary[Event, Vector2i]
@export_storage var event_positions := {}

## The condition in which this Multi-Event will emit
## its done signal.
enum CompleteMode {
	AllBranches = 0,	## The multi-event is completed when all branches end.
	AnyBranches = 1,	## The multi-event is completed when any branch ends.
	Immediate = 2,		## The multi-event is completed as soon as it begins.
}

## The complete mode for the multi-event.
@export var complete_mode := CompleteMode.AllBranches

## When true, all started events will log their properties to the terminal.
@export var debug := false

var active_branches := 0
var completed := false

var started_events: Array[Event] = []

#region Runtime Logic
func _get_interval(owner: Node, state: Dictionary) -> Interval:
	completed = false
	started_events = []
	return Func.new(func (owner: Node, state: Dictionary):
		## Get all open-facing branches.
		var unresolved_int_events := get_unresolved_int_events()
		if not unresolved_int_events:
			done.emit()
			return
		
		## Start each one.
		active_branches = unresolved_int_events.size()
		for event in unresolved_int_events:
			_start_branch(event, owner, state, false)
		
		## Immediate complete multievents are done here.
		if complete_mode == CompleteMode.Immediate:
			done.emit()
	)

## Begins an event branch.
func _start_branch(event: Event, owner: Node, state: Dictionary, count_branch := true):
	if count_branch:
		active_branches += 1
	if debug:
		event.print_debug_info()
	started_events.append(event)
	event.play(owner, _end_branch.bind(owner, state, event), state)

## Called when an event branch is complete.
func _end_branch(event: Event, owner: Node, state: Dictionary):
	## Perform all connecting branches.
	for connected_event: Event in get_event_connections(event):
		if connected_event not in started_events:
			_start_branch(connected_event, owner, state)
	
	## Update active branch state.
	active_branches -= 1
	if complete_mode == CompleteMode.AnyBranches and not completed:
		completed = true
		done.emit()
	elif complete_mode == CompleteMode.AllBranches and active_branches == 0:
		done.emit()
#endregion

#region Editor API
## Adds an event to the multi event.
func add_event(event: Event, position: Vector2i = Vector2.ZERO):
	events.append(event)
	event_positions[event] = position
	editor_refresh.emit()

## Removes an event from the multi event.
func remove_event(event: Event):
	if event in events:
		events.erase(event)
		event_positions.erase(event)
		event_connections.erase(event)
		# Dictionary[Event, Dict[int, Array[Event]]]
		for event_ext_ports: Dictionary in event_connections.values():
			for branch: int in event_ext_ports.duplicate():
				var outgoing_connections: Array = event_ext_ports[branch]
				outgoing_connections.erase(event)
				if not outgoing_connections:
					event_ext_ports.erase(branch)
		editor_refresh.emit()

## Connects two events together in data.
func connect_events(pre_event: Event, post_event: Event, pre_event_branch: int = 0):
	# Dictionary[Event, Dict[int, Array[Event]]]
	var event_dict: Dictionary = event_connections.get_or_add(pre_event, {})
	var event_list: Array = event_dict.get_or_add(pre_event_branch, [])
	if post_event not in event_list:
		event_list.append(post_event)
		editor_refresh.emit()
		notify_property_list_changed()

## Disconnects two events from eachother.
func disconnect_events(pre_event: Event, post_event: Event, pre_event_branch: int = 0):
	var event_dict: Dictionary = event_connections.get_or_add(pre_event, {})
	var event_list: Array = event_dict.get_or_add(pre_event_branch, [])
	if post_event in event_list:
		event_list.erase(post_event)
		editor_refresh.emit()
		notify_property_list_changed()

## Determines the events that comes after a given event.
func get_event_connections(event: Event) -> Array:
	return event_connections.get_or_add(event, {}).get_or_add(event.get_branch_index(), [])

## Stores the XY position of the event node in the editor.
func set_event_editor_position(event: Event, position: Vector2i, refresh := true):
	if event_positions.get(event, Vector2i.ZERO) != position:
		event_positions[event] = position
		if refresh:
			editor_refresh.emit()

## Returns a list of all events without an input connection.
## Returns Array[Event]
func get_unresolved_int_events() -> Array:
	var ret_events: Dictionary = {}
	for event in events:
		ret_events[event] = null
	for each_event: Event in event_connections:
		for all_connected_events in event_connections[each_event].values():
			for each_connected_event: Event in all_connected_events:
				# Each event here has a connected INPUT port,
				# so we know that it must be resolved.
				ret_events.erase(each_connected_event)
	return ret_events.keys()

## Returns a list of all events without an output connection.
## Returns Dict[Event, Array[int]]
func get_unresolved_ext_events() -> Dictionary:
	var ret_events := {}
	for event: Event in event_connections:
		for branch_idx in event.get_branch_names().size():
			var connected_events: Array = event_connections[event].get_or_add(branch_idx, [])
			# If this slot has no connected events,
			# we know that it must be unresolved.
			if not connected_events:
				ret_events.get_or_add(event).append(branch_idx)
	return ret_events
#endregion

#region Event Overrides
## Gets the names of the outgoing branches.
func get_branch_names() -> Array:
	var base_names := super()
	
	## Get branches of all unresolved sub-events.
	var unresolved_ext_events := get_unresolved_ext_events()
	for event: Event in unresolved_ext_events:
		var branch_names := event.get_branch_names()
		var event_name: String = event.to_string()
		for branch_idx: int in unresolved_ext_events[event]:
			var branch_name: String = branch_names[branch_idx]
			base_names.append('[%s] %s' % [event_name, branch_idx])
	
	## Return base names.
	return base_names

## Determines the branch index we're choosing based on internal state.
func get_branch_index() -> int:
	return 0

## The color that represents this event in the editor.
static func get_editor_color() -> Color:
	return Color.WEB_MAROON

## String representation of the event. Important to define.
static func get_editor_name() -> String:
	return "MultiEvent"

## The editor description of the event.
func get_editor_description_text(owner: Node) -> String:
	return "[b][center]%s Sub-Events" % (events.size() if events else 0)
#endregion