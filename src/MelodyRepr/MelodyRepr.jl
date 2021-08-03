module MelodyRepr

using MIDI
using ..NoteSequences

# Melody representation related constants
const NUM_SPECIAL_MELODY_EVENTS = 2
const MELODY_NOTE_OFF = -1
const MELODY_NO_EVENT = -2
const MIN_MELODY_EVENT = -2
const MAX_MELODY_EVENT = 127

include("melody.jl")

end
