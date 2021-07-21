module NoteSequences

using MIDI, DataStructures

include("constants.jl")
include("instruments.jl")
include("notesequence.jl")
include("PerformanceRepresentation/PerformanceRepresentation.jl")

using .PerformanceRepresentation
export Performance, PerformanceEvent

end
