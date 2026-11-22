class_name AirplaneController
extends Node
## Base class for every input source that can pilot an airplane.
##
## The airplane pulls one PlaneInput from its controller per physics tick, so
## keyboard, touch, AI and remote pilots are interchangeable at runtime.

var plane: Airplane


func bind(target: Airplane) -> void:
	plane = target


## Override in subclasses. `delta` is the physics step being simulated.
func get_plane_input(_delta: float) -> PlaneInput:
	return PlaneInput.new()
