export NoteSequence, midi_to_notesequence, notesequence_to_midi

using MIDI
using MIDI: TimeSignatureEvent, KeySignatureEvent, SetTempoEvent
using Base.Iterators

"""
    SeqNote <: Any

Structure to hold the data in a [`MIDI.Note`](@ref) along with it's `program` and `instrument`.
"""
mutable struct SeqNote
    pitch::Int
    velocity::Int
    start_time::Int
    end_time::Int
    program::Int
    instrument::Int
end

"""
    Tempo <: Any

Structure to hold the `qpm` from a [`MIDI.SetTempoEvent`](@ref).
"""
mutable struct Tempo
    time::Int
    qpm::Float64
end

"""
    PitchBend <: Any

Structure to hold the data in a [`MIDI.PitchBendEvent`](@ref) along with it's `program` and `instrument`.
"""
mutable struct PitchBend
    time::Int
    bend::Int
    program::Int
    instrument::Int
end

"""
    ControlChange <: Any

Structure to hold the data in a [`MIDI.ControlChangeEvent`](@ref) along with it's `program` and `instrument`.
"""
mutable struct ControlChange
    time::Int
    controller::Int
    value::Int
    program::Int
    instrument::Int
end

Base.@kwdef mutable struct NoteSequence
    tpq::Int = 220
    isquantized::Bool = false
    sps::Int = -1
    total_time::Int = 0
    timesignatures::Vector{TimeSignatureEvent} = []
    keysignatures::Vector{KeySignatureEvent} = []
    tempos::Vector{Tempo} = []
    notes::Vector{SeqNote} = []
    pitchbends::Vector{PitchBend} = []
    controlchanges::Vector{ControlChange} = []
end

function NoteSequence(tpq::Int; isquantized::Bool = false, sps::Int = -1)
    if !isquantized && sps != -1
        throw(ArgumentError("`sps` must be not be given for an unquantized note sequence"))
    end

    if isquantized && sps <= 0
        throw(ArgumentError("`sps` must be greater than zero for a quantized note sequence"))
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

"""
    midi_to_notesequence(midi::MIDIFile)

Return [`NoteSequence`](@ref) from a `MIDIFile`.
"""
function midi_to_notesequence(midi::MIDIFile)
    ns = NoteSequence(Int(midi.tpq), isquantized=false)

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
            seqnote = SeqNote(note.pitch, note.velocity, note.position,
                              note.position + note.duration,
                              ins.program, ins_num)

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

"""
    getinstruments(ns::NoteSequence)

Extract [`Instrument`](@ref)s from the [`NoteSequence`](@ref).
"""
function getinstruments(ns::NoteSequence)
    # Create dicts that map (instrument_num, program) to their events
    instrument_notes = DefaultOrderedDict{Tuple{Int64, Int64}, Notes}(Notes)
    instrument_pb = DefaultOrderedDict{Tuple{Int64, Int64}, Vector{PitchBendEvent}}(Vector{PitchBendEvent})
    instrument_cc = DefaultOrderedDict{Tuple{Int64, Int64}, Vector{ControlChangeEvent}}(Vector{ControlChangeEvent})

    for note in ns.notes
        key = (note.instrument, note.program)
        push!(instrument_notes[key], Note(note.pitch, note.velocity, note.start_time, note.end_time - note.start_time))
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

    instruments
end

"""
    notesequence_to_midi(ns::NoteSequence)

Return a MIDIFile from a [`NoteSequence`](@ref)
"""
function notesequence_to_midi(ns::NoteSequence)
    midifile = MIDIFile(1, ns.tpq, MIDITrack[])
    metatrack = MIDITrack()

    isempty(ns.tempos) && push!(ns.tempos, Tempo(0, 120.0))
    for tempo in ns.tempos
        # Convert qpm to microseconds
        μs = Int(6e7 ÷ tempo.qpm)
        push!(metatrack.events, SetTempoEvent(tempo.time, μs))
    end

    # Add default time signature if time signatures are missing
    if isempty(ns.timesignatures)
        push!(ns.timesignatures, TimeSignatureEvent(0, 4, 4, 24, 8))
    end

    append!(metatrack.events, ns.timesignatures)
    append!(metatrack.events, ns.keysignatures)
    push!(midifile.tracks, metatrack)

    instruments = getinstruments(ns)
    instrument_tracks = getmiditracks(instruments)
    append!(midifile.tracks, instrument_tracks)

    midifile
end

"""
    quantizedstep(ticks::Int, tpq::Int, qpm::Float64, sps::Int, cutoff=QUANTIZE_CUTOFF)

Quantizes `ticks` to the nearest steps, given the steps per second (`sps`).
The ticks are converted to seconds using the ticks per quarter (`tpq`)
and quarter notes per minute (`qpm`).
The seconds are then further converted to steps before being quantized.

Notes above the cutoff are rounded up to the closest step
and notes below the cutoff are rounded down to the closest step.
For example,
if 1.0 <= event <= 1.75, it will be quantized to step 1
if 1.75 < event <= 2.0, it will be quantized to step 2
"""
function quantizedstep(ticks::Int, tpq::Int, qpm::Float64, sps::Int, cutoff=QUANTIZE_CUTOFF)
    seconds = ticks * ms_per_tick(tpq, qpm) / 1e3
    steps = seconds * sps

    floor(Int, steps + (1 - cutoff))
end

"""
    absolutequantize!(ns::NoteSequence, sps::Int)

Quantize a NoteSequence to absolute time based on the given steps per second (`sps`).
"""
function absolutequantize!(ns::NoteSequence, sps::Int)
    ns.isquantized && throw(error("The NoteSequence is already quantized"))

    for tempo in ns.tempos[2:end]
        if tempo.qpm != ns.tempos[1].qpm
            throw(error("The NoteSequence has multiple tempo changes"))
        end
    end
    qpm = ns.tempos[1].qpm

    ns.total_time = quantizedstep(ns.total_time, ns.tpq, qpm, sps)

    for note in ns.notes
        note.start_time = quantizedstep(note.start_time, ns.tpq, qpm, sps)
        note.end_time = quantizedstep(note.end_time, ns.tpq, qpm, sps)

        if ns.total_time == -1 || note.end_time > ns.total_time
            ns.total_time = note.end_time
        end

        if note.start_time < 0 || note.end_time < 0
            throw(error("Note has negative time"))
        end
    end

    for cc in ns.controlchanges
        cc.time = quantizedstep(cc.time, ns.tpq, qpm, sps)
        if cc.time < 0
            throw(error("Control change event has negative time"))
        end
    end

    ns.isquantized = true
    ns.sps = sps

    ns
end

"""
    temporalstretch!(ns::NoteSequence, factor::Real)

Apply a constant temporal stretch to a NoteSequence.
`factor` is the amount of stretch to be applied.
If the `factor` is greater than 1.0, it increases the length, which makes the sequence slower.
If the `factor` is lower than 1.0, it decreases the length, which makes the sequence faster.
"""
function temporalstretch!(ns::NoteSequence, factor::Real)
    ns.isquantized && throw(error("Can only stretch unquantized NoteSequence"))

    factor == 1.0 && return ns

    # Stretch notes and total time of the NoteSequence
    for note in ns.notes
        note.start_time *= factor
        note.end_time *= factor
    end
    ns.total_time *= factor

    # Stretch tempos
    for tempo in ns.tempos
        tempo.qpm /= factor
    end

    # Stretch event times for all other events
    for event in flatten((ns.timesignatures, ns.keysignatures))
        event.dT *= factor
    end

    for event in flatten((ns.tempos, ns.pitchbends, ns.controlchanges))
        event.time *= factor
    end

    ns
end

"""
    transpose(ns::NoteSequence, amount::Int, minpitch::Int, maxpitch::Int)

Transpose the NoteSequence by `amount` half-steps
and return the transposed sequence along with the number of deleted notes.
The allowed range of values for a pitch is defined by `minpitch` and `maxpitch`.
If the transposed pitch goes out of range, the note is removed.
"""
function transpose(ns::NoteSequence, amount::Int, minpitch::Int, maxpitch::Int)
    new_notes = Vector{SeqNote}()
    num_deleted = 0
    end_time = 0

    for note in ns.notes
        note.pitch += amount
        if minpitch <= note.pitch <= maxpitch
            # Keep track of note ending times
            end_time = max(end_time, note.end_time)
            push!(new_notes, note)
        else
            # Don't include this pitch since it's out of range
            num_deleted += 1
        end
    end

    if num_deleted > 0
        ns.notes = new_notes
        # Update total time, since some notes were removed
        ns.total_time = end_time
    end

    # TODO: transpose key signatures

    ns, num_deleted
end
