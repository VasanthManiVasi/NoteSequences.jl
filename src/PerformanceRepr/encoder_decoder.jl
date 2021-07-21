export PerformanceOneHotEncoding

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

    function PerformanceOneHotEncoding(;num_velocitybins::Int=0, max_shift_steps=DEFAULT_MAX_SHIFT_STEPS)
        event_ranges = [
            (NOTE_ON, MIN_MIDI_PITCH, MAX_MIDI_PITCH)
            (NOTE_OFF, MIN_MIDI_PITCH, MAX_MIDI_PITCH)
            (TIME_SHIFT, 1, max_shift_steps)
        ]
        num_velocitybins > 0 && push!(event_ranges, (VELOCITY, 1, num_velocitybins))
        num_classes = sum([max - min + 1 for (type, min, max) in event_ranges])
        new(event_ranges, num_classes)
    end
end

function Base.getproperty(perfencoder::PerformanceOneHotEncoding, sym::Symbol)
    if sym === :labels
        return 0:(perfencoder.num_classes - 1)
    elseif sym === :defaultevent
        return PerformanceEvent(TIME_SHIFT, DEFAULT_MAX_SHIFT_STEPS)
    else
        getfield(perfencoder, sym)
    end
end

"""
    encodeindex(event::PerformanceEvent, performance::PerformanceOneHotEncoding)

Encodes a `PerformanceEvent` to its corresponding one hot index.
"""
function encodeindex(event::PerformanceEvent, performance::PerformanceOneHotEncoding)
    offset = 0
    for (type, min, max) in performance.event_ranges
        if event.event_type == type
            return offset + event.event_value - min
        end
        offset += (max - min + 1)
    end
end

"""
    decodeindex(idx::Int, performance::PerformanceOneHotEncoding)

Decodes a one hot index to its corresponding `PerformanceEvent`.
"""
function decodeindex(idx::Int, performance::PerformanceOneHotEncoding)
    offset = 0
    for (type, min, max) in performance.event_ranges
        if idx < offset + (max - min + 1)
            return PerformanceEvent(type, min + idx - offset)
        end
        offset += (max - min + 1)
    end
end
