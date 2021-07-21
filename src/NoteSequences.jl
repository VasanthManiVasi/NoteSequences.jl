module NoteSequences

using MIDI, DataStructures

include("constants.jl")
include("instruments.jl")
include("notesequence.jl")
include("PerformanceRepr/PerformanceRepr.jl")

using .PerformanceRepr
export Performance, PerformanceEvent

end
