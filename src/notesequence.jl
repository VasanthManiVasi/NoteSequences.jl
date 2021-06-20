export NoteSequence, midi_to_notesequence, notesequence_to_midi

using MIDI
using MIDI: TimeSignatureEvent, KeySignatureEvent, SetTempoEvent

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
    # No need to convert midifile to absolute time since tempochanges returns absolute time automatically
    for (time, qpm) in tempochanges(midi)
        push!(ns.tempos, Tempo(time, qpm))
    end

    # Convert midifile to absolute time for the rest of the events
    toabsolutetime!(midi)
    for event in midi.tracks[1].events
        if event isa TimeSignatureEvent
            push!(ns.time_signatures, event)
        elseif event isa KeySignatureEvent
            push!(ns.key_signatures, event)
        end
    end

    instruments = getinstruments(midi, :absolute)
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

    # Convert midifile back to relative time
    torelativetime!(midi)
    return ns
end

function notesequence_to_midi(ns::NoteSequence)
    midifile = MIDIFile()
    midifile.tpq = ns.tpq

    metatrack = MIDITrack()

    if isempty(ns.tempos)
        push!(ns.tempos, Tempo(0, 120.0))
    end

    for tempo in ns.tempos
        # Convert qpm back to microseconds
        μs = Int(6e7 ÷ tempo.qpm)
        push!(metatrack.events, SetTempoEvent(tempo.time, μs))
    end
    append!(metatrack.events, ns.time_signatures)
    append!(metatrack.events, ns.key_signatures)
    push!(midifile.tracks, metatrack)

    # Create dicts that map (instrument_num, program) to their events
    instrument_notes = DefaultOrderedDict{Tuple{Int64, Int64}, Notes}(Notes)
    instrument_pb = DefaultOrderedDict{Tuple{Int64, Int64}, Vector{PitchBendEvent}}(Vector{PitchBendEvent})
    instrument_cc = DefaultOrderedDict{Tuple{Int64, Int64}, Vector{ControlChangeEvent}}(Vector{ControlChangeEvent})

    for note in ns.notes
        key = (note.instrument, note.program)
        push!(instrument_notes[key], Note(note.pitch, note.velocity, note.start_time, note.end_time))
    end

    for pb in ns.pitch_bends
        key = (pb.instrument, pb.program)
        push!(instrument_pb[key], PitchBendEvent(pb.time, pb.pitch))
    end

    for cc in ns.control_changes
        key = (cc.instrument, cc.program)
        push!(instrument_cc[key], ControlChangeEvent(cc.time, cc.controller, cc.value))
    end

    # Obtain unique keys from each of those dicts
    instrument_info = collect(union(keys.([instrument_notes, instrument_pb, instrument_cc])...))
    sort!(instrument_info)

    instruments = Vector{Instrument}()
    for (ins_num, program) in instrument_info
        ins = Instrument(program=program)
        key = (ins_num, program)
        append!(ins.notes, instrument_notes[key])
        append!(ins.pitch_bends, instrument_pb[key])
        append!(ins.control_changes, instrument_cc[key])
        push!(instruments, ins)
    end

    instrument_tracks = getmiditracks(instruments)
    append!(midifile.tracks, instrument_tracks)

    midifile
end