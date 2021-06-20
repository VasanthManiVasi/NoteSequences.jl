export NoteSequence, midi_to_notesequence

using MIDI
using MIDI: TimeSignatureEvent, KeySignatureEvent

struct SeqNote
    pitch::Int
    velocity::Int
    start_time::Int
    end_time::Int
    program::Int
    instrument::Int
end

struct Tempo
    time::Int
    qpm::Float64
end

struct PitchBend
    time::Int
    bend::Int
    instrument::Int
    program::Int
end

struct ControlChange
    time::Int
    controller::Int
    value::Int
    instrument::Int
    program::Int
end

Base.@kwdef mutable struct NoteSequence
    tpq::Int = 220
    is_quantized::Bool
    steps_per_second::Int
    time_signatures::Vector{TimeSignatureEvent} = []
    key_signatures::Vector{KeySignatureEvent} = []
    tempos::Vector{Tempo} = []
    notes::Vector{SeqNote} = []
    pitch_bends::Vector{PitchBend} = []
    control_changes::Vector{ControlChange} = []
end

function NoteSequence(tpq::Int = 220, is_quantized::Bool = false, steps_per_second::Int = -1)
    if is_quantized && steps_per_second <= 0
        throw(ArgumentError("`steps_per_second` must be greater than zero for a quantized sequence"))
    end
    NoteSequence(tpq=tpq, is_quantized=is_quantized, steps_per_second=steps_per_second)
end

function Base.show(io::IO, ns::NoteSequence)
    print(io, "NoteSequence(tpq=$(ns.tpq), is_quantized=$(ns.is_quantized), steps_per_second=$(ns.steps_per_second))\n")
    T = length(ns.time_signatures)
    K = length(ns.key_signatures)
    Te = length(ns.tempos)
    print(io, "  $T TimeSignatures, $K KeySignatures, $Te Tempos\n")
    N = length(ns.notes)
    P = length(ns.pitch_bends)
    C = length(ns.control_changes)
    print(io, "  $N Notes, $P PitchBends, $C ControlChanges\n")
end

function midi_to_notesequence(midi::MIDIFile)
    ns = NoteSequence(Int(midi.tpq), false)

    # Load meta info
    for event in midi.tracks[1].events
        if event isa TimeSignatureEvent
            push!(ns.time_signatures, event)
        elseif event isa KeySignatureEvent
            push!(ns.key_signatures, event)
        end
    end

    for (time, qpm) in tempochanges(midi)
        push!(ns.tempos, Tempo(time, qpm))
    end

    instruments = getinstruments(midi)
    for (ins_num, ins) in enumerate(instruments)
        for note in ins.notes
            push!(ns.notes, SeqNote(note.pitch, note.velocity, note.position, note.position + note.duration, ins.program, ins_num))
        end

        for event in ins.pitch_bends
            push!(ns.pitch_bends, PitchBend(event.dT, event.pitch, ins_num, ins.program))
        end

        for event in ins.control_changes
            push!(ns.control_changes, ControlChange(event.dT, event.controller, event.value, ins_num, ins.program))
        end
    end

    return ns
end