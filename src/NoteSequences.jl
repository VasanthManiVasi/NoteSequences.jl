module NoteSequences

using MIDI
using DataStructures

include("constants.jl")
include("instruments.jl")
include("notesequence.jl")
include("utils.jl")
include("PerformanceRepr/PerformanceRepr.jl")
include("MelodyRepr/MelodyRepr.jl")

using .PerformanceRepr
export Performance, PerformanceEvent

using .MelodyRepr
export Melody

export encode_event, decode_event

end
