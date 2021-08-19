export MelodyOneHotEncoding
import ..encode_event, ..decode_event

using ..NoteSequences: MIN_MIDI_PITCH, MAX_MIDI_PITCH

"""
    MelodyOneHotEncoding <: Any

One-Hot encoder for `Melody` events.

## Fields
* `minpitch::Int`: Minimum melody pitch to allow for encoding.
* `maxpitch::Int`: Maximum melody pitch to allow for encoding.
* `num_classes::Int`: Total number of event classes.
"""
struct MelodyOneHotEncoding
    minpitch::Int
    maxpitch::Int
    num_classes::Int

    function MelodyOneHotEncoding(minpitch::Int, maxpitch::Int)
        maxpitch <= minpitch &&
            throw(error("max pitch should be greater than min pitch"))
        minpitch < MIN_MIDI_PITCH &&
            throw(error("min pitch is lesser than 0 (minimum allowed midi pitch)"))
        maxpitch > MAX_MIDI_PITCH + 1 &&
            throw(error("max pitch is greater than 128"))

        num_classes = maxpitch - minpitch + NUM_SPECIAL_MELODY_EVENTS
        new(minpitch, maxpitch, num_classes)
    end
end

function Base.getproperty(encoder::MelodyOneHotEncoding, sym::Symbol)
    if sym === :labels
        return 1:encoder.num_classes
    elseif sym === :defaultevent
        return MELODY_NO_EVENT
    else
        getfield(encoder, sym)
    end
end

"""
    encode_event(event::Int, encoder::MelodyOneHotEncoding)

Encodes a `Melody` event to its corresponding one hot index.
"""
function encode_event(event::Int, encoder::MelodyOneHotEncoding)
    0 <= event < encoder.minpitch &&
        throw(error("Melody event is less than min melody pitch"))
    event >= encoder.maxpitch &&
        throw(error("Melody event is greater than max melody pitch"))
    event < -NUM_SPECIAL_MELODY_EVENTS &&
        throw(error("Invalid melody event"))

    if event < 0
        index = event + NUM_SPECIAL_MELODY_EVENTS
    else
        index = event - encoder.minpitch + NUM_SPECIAL_MELODY_EVENTS
    end

    # Add one to convert to 1-based indexing (starts at 1, ends at num_classes)
    index + 1
end

"""
    decode_event(index::Int, encoder::MelodyOneHotEncoding)

Decodes a one hot index to its corresponding `Melody` event.
"""
function decode_event(index::Int, encoder::MelodyOneHotEncoding)
    if index < NUM_SPECIAL_MELODY_EVENTS + 1
        event = index - NUM_SPECIAL_MELODY_EVENTS
    else
        event = index - NUM_SPECIAL_MELODY_EVENTS + encoder.minpitch
    end

    # Subtract one to convert from 1-based indexing
    event - 1
end
