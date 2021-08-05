export PerformanceOneHotEncoding
import ..encodeindex, ..decodeindex

using ..NoteSequences: MIN_MIDI_PITCH, MAX_MIDI_PITCH

"""
    PerformanceOneHotEncoding <: Any

One-Hot encoder for [`PerformanceEvent`](@ref)s.

## Fields
* `event_ranges::Vector{NTuple{3, Int}}`: Stores the min and max values of each event type.
* `num_classes::Int`: Total number of event classes. It is the sum of all `NOTE_ON`,
`NOTE_OFF`,`TIME_SHIFT` and `VELOCITY` events.
"""
struct PerformanceOneHotEncoding
    event_ranges::Vector{NTuple{3, Int}}
    num_classes::Int

    function PerformanceOneHotEncoding(;num_velocitybins::Int=0,
                                        max_shift_steps::Int=DEFAULT_MAX_SHIFT_STEPS,
                                        minpitch::Int=MIN_MIDI_PITCH,
                                        maxpitch::Int=MAX_MIDI_PITCH)
        event_ranges = [
            (NOTE_ON, minpitch, maxpitch),
            (NOTE_OFF, minpitch, maxpitch),
            (TIME_SHIFT, 1, max_shift_steps)
        ]
        num_velocitybins > 0 && push!(event_ranges, (VELOCITY, 1, num_velocitybins))
        num_classes = sum([max - min + 1 for (type, min, max) in event_ranges])
        new(event_ranges, num_classes)
    end
end

function Base.getproperty(encoder::PerformanceOneHotEncoding, sym::Symbol)
    if sym === :labels
        return 1:encoder.num_classes
    elseif sym === :defaultevent
        return PerformanceEvent(TIME_SHIFT, DEFAULT_MAX_SHIFT_STEPS)
    else
        getfield(encoder, sym)
    end
end

"""
    encodeindex(event::PerformanceEvent, encoder::PerformanceOneHotEncoding)

Encodes a `PerformanceEvent` to its corresponding one hot index.
"""
function encodeindex(event::PerformanceEvent, encoder::PerformanceOneHotEncoding)
    # Start at one to account for 1-based indexing
    offset = 1
    for (type, min, max) in encoder.event_ranges
        if event.event_type == type
            return offset + event.event_value - min
        end
        offset += (max - min + 1)
    end

    throw(error("Unknown type for PerformanceEvent"))
end

"""
    decodeindex(idx::Int, encoder::PerformanceOneHotEncoding)

Decodes a one hot index to its corresponding `PerformanceEvent`.
"""
function decodeindex(idx::Int, encoder::PerformanceOneHotEncoding)
    # Start at one to account for 1-based indexing
    offset = 1
    for (type, min, max) in encoder.event_ranges
        if idx < offset + (max - min + 1)
            return PerformanceEvent(type, min + idx - offset)
        end
        offset += (max - min + 1)
    end

    throw(error("Unknown index"))
end
