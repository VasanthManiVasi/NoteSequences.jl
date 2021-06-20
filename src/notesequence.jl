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
    isquantized::Bool
    sps::Int
    total_time::Int = 0
    timesignatures::Vector{TimeSignatureEvent} = []
    keysignatures::Vector{KeySignatureEvent} = []
    tempos::Vector{Tempo} = []
    notes::Vector{SeqNote} = []
    pitchbends::Vector{PitchBend} = []
    controlchanges::Vector{ControlChange} = []
end

function NoteSequence(tpq::Int = 220, isquantized::Bool = false, sps::Int = -1)
    if isquantized && sps <= 0
        throw(ArgumentError("`sps` must be greater than zero for a quantized sequence"))
    end
    NoteSequence(tpq=tpq, isquantized=isquantized, sps=sps)
end

function Base.show(io::IO, ns::NoteSequence)
    print(io, "NoteSequence(tpq=$(ns.tpq), isquantized=$(ns.isquantized), sps=$(ns.sps))\n")
    unit = (ns.isquantized) ? "steps" : "ticks"
    print(io, "  Total time = $(ns.total_time) $unit\n")
    T = length(ns.timesignatures)
    K = length(ns.keysignatures)
    Te = length(ns.tempos)
    print(io, "  $T TimeSignatures, $K KeySignatures, $Te Tempos\n")
    N = length(ns.notes)
    P = length(ns.pitchbends)
    C = length(ns.controlchanges)
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
            push!(ns.timesignatures, event)
        elseif event isa KeySignatureEvent
            push!(ns.keysignatures, event)
        end
    end

    instruments = getinstruments(midi, :absolute)
    for (ins_num, ins) in enumerate(instruments)
        for note in ins.notes
            seqnote = SeqNote(note.pitch, note.velocity, note.position, note.position + note.duration, ins.program, ins_num)
            push!(ns.notes, seqnote)
            if ns.total_time == -1 || seqnote.end_time > ns.total_time
                ns.total_time = seqnote.end_time
            end
        end

        for event in ins.pitchbends
            push!(ns.pitchbends, PitchBend(event.dT, event.pitch, ins_num, ins.program))
        end

        for event in ins.controlchanges
            push!(ns.controlchanges, ControlChange(event.dT, event.controller, event.value, ins_num, ins.program))
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
    append!(metatrack.events, ns.timesignatures)
    append!(metatrack.events, ns.keysignatures)
    push!(midifile.tracks, metatrack)

    # Create dicts that map (instrument_num, program) to their events
    instrument_notes = DefaultOrderedDict{Tuple{Int64, Int64}, Notes}(Notes)
    instrument_pb = DefaultOrderedDict{Tuple{Int64, Int64}, Vector{PitchBendEvent}}(Vector{PitchBendEvent})
    instrument_cc = DefaultOrderedDict{Tuple{Int64, Int64}, Vector{ControlChangeEvent}}(Vector{ControlChangeEvent})

    for note in ns.notes
        key = (note.instrument, note.program)
        push!(instrument_notes[key], Note(note.pitch, note.velocity, note.start_time, note.end_time))
    end

    for pb in ns.pitchbends
        key = (pb.instrument, pb.program)
        push!(instrument_pb[key], PitchBendEvent(pb.time, pb.pitch))
    end

    for cc in ns.controlchanges
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
        append!(ins.pitchbends, instrument_pb[key])
        append!(ins.controlchanges, instrument_cc[key])
        push!(instruments, ins)
    end

    instrument_tracks = getmiditracks(instruments)
    append!(midifile.tracks, instrument_tracks)

    midifile
end