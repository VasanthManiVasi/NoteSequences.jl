module PerformanceRepresentation

using ..NoteSequences

# Performance representation related constants
const NOTE_ON = 1
const NOTE_OFF = 2
const TIME_SHIFT = 3
const VELOCITY = 4
const DEFAULT_MAX_SHIFT_STEPS = 100

export NOTE_ON, NOTE_OFF, TIME_SHIFT, VELOCITY

include("performance.jl")

end