module NoteSequences

using MIDI
using DataStructures

include("constants.jl")
include("instruments.jl")
include("notesequence.jl")
include("PerformanceRepr/PerformanceRepr.jl")
include("MelodyRepr/MelodyRepr.jl")

using .PerformanceRepr
export Performance, PerformanceEvent

using .MelodyRepr
export Melody

export encodeindex, decodeindex

end
