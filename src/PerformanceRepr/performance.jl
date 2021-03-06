export PerformanceEvent, Performance
export getnotesequence, setlength!

using ..NoteSequences: SeqNote, DEFAULT_QPM, DEFAULT_TPQ
using ..NoteSequences: MIN_MIDI_VELOCITY, MAX_MIDI_VELOCITY, MIN_MIDI_PITCH, MAX_MIDI_PITCH
using MacroTools: @forward

"""
    PerformanceEvent <: Any

Event-based performance representation of music data from Oore et al.
In this representation, midi data is encoded as a 388-length one hot vector.
It corresponds to NOTE_ON, NOTE_OFF events for each of the 128 midi pitches,
32 bins for the 128 midi velocities and 100 TIME_SHIFT events
(it can represent a time shift from 10 ms up to 1 second).
`PerformanceEvent` is the base representation.

## Fields
* `event_type::Int`  :  Type of the event. One of {NOTE_ON, NOTE_OFF, TIME_SHIFT, VELOCITY}.
* `event_value::Int` :  Value of the event corresponding to its type.
"""
struct PerformanceEvent
    event_type::Int
    event_value::Int

    function PerformanceEvent(type::Int, value::Int)
        if (type == NOTE_ON || type == NOTE_OFF)
            if !(MIN_MIDI_PITCH <= value <= MAX_MIDI_PITCH)
                error("The event has an invalid pitch value")
            end
        elseif type == TIME_SHIFT
            if !(value >= 0)
                error("The event has an invalid time shift value")
            end
        elseif type == VELOCITY
            if !(MIN_MIDI_VELOCITY <= value <= MAX_MIDI_VELOCITY)
                error("The event has an invalid velocity value")
            end
        else
            error("PerformanceEvent has invalid type")
        end

        new(type, value)
    end
end

function Base.show(io::IO, a::PerformanceEvent)
    if a.event_type == NOTE_ON
        s = "NOTE-ON"
    elseif a.event_type == NOTE_OFF
        s = "NOTE-OFF"
    elseif a.event_type == TIME_SHIFT
        s = "TIME-SHIFT"
    elseif a.event_type == VELOCITY
        s = "VELOCITY"
    else
        error("PerformanceEvent has invalid type")
    end

    s *= " $(a.event_value)"
    print(io, s)
end

"""
    Performance <: Any

`Performance` represents a polyphonic sequence
as a stream of `PerformanceEvent`s.

See [`PerformanceEvent`](@ref)

## Fields
* `events::Vector{PerformanceEvent}`: The performance in a vector of `PerformanceEvent`s.
* `program::Int`: MIDI program number for this `Performance`
* `startstep::Int`: The start step of the performance relative to the source sequence.
* `velocity_bins::Int`: Number of bins for velocity values.
* `steps_per_second::Int`: Number of steps per second for quantization.
* `max_shift_steps::Int`: Maximum number of steps in a `TIME_SHIFT` event.
"""
mutable struct Performance
    events::Vector{PerformanceEvent}
    program::Int
    startstep::Int
    velocity_bins::Int
    steps_per_second::Int
    max_shift_steps::Int

    function Performance(startstep::Int,
                         velocity_bins::Int,
                         steps_per_second::Int,
                         max_shift_steps::Int;
                         program::Int=-1,
                         events::Vector{PerformanceEvent}=Vector{PerformanceEvent}())

        new(events,
            program,
            startstep,
            velocity_bins,
            steps_per_second,
            max_shift_steps)
    end
end

function Performance(quantizedns::NoteSequence;
                     startstep::Int = 0,
                     velocity_bins::Int = 0,
                     max_shift_steps::Int = DEFAULT_MAX_SHIFT_STEPS,
                     instrument::Int = -1)

    if !quantizedns.isquantized
        throw(ArgumentError("The `NoteSequence` must be quantized."))
    end

    steps_per_second = quantizedns.sps
    events = getperfevents(quantizedns, startstep, velocity_bins, max_shift_steps, instrument)

    Performance(startstep, velocity_bins, steps_per_second, max_shift_steps, events=events)
end

function Performance(steps_per_second::Int;
                     startstep::Int = 0,
                     velocity_bins::Int = 0,
                     max_shift_steps::Int = DEFAULT_MAX_SHIFT_STEPS,
                     program::Int = -1)

    Performance(startstep, velocity_bins, steps_per_second, max_shift_steps, program=program)
end

function Base.getproperty(performance::Performance, sym::Symbol)
    if sym === :numsteps
        steps = 0
        for event in performance
            if event.event_type == TIME_SHIFT
                steps += event.event_value
            end
        end
        return steps
    else
        getfield(performance, sym)
    end
end

@forward Performance.events Base.length, Base.getindex, Base.lastindex, Base.pop!

Base.setindex!(p::Performance, event::PerformanceEvent, idx::Int) = setindex!(p.events, event, idx)
Base.iterate(p::Performance, state=1) = iterate(p.events, state)
Base.push!(p::Performance, event::PerformanceEvent) = push!(p.events, event)
Base.append!(p::Performance, events::Vector{PerformanceEvent}) = append!(p.events, events)

function Base.append!(p1::Performance, p2::Performance)
    append!(p1, p2.events)
end

function Base.copy(p::Performance)
    Performance(
        copy(p.events),
        p.program,
        p.startstep,
        p.velocity_bins,
        p.steps_per_second,
        p.max_shift_steps)
end

"""
    getperfevents(quantizedns::NoteSequence, startstep::Int, velocity_bins::Int,
                  max_shift_steps::Int, instrument::Int=-1)

Extract performance events from a quantized [`NoteSequence`](@ref).

The extraction starts from `startstep`. The number of velocity bins to use
is given by `velocity_bins`. If it's 0, velocity events will not be included.
`max_shift_steps` is the maximum number of steps for a single `TIME_SHIFT` event.

If `instrument` is -1, performance events will be extracted for all instruments in the `NoteSequence`
Otherwise, performance events will be extracted only for the given instrument.
"""
function getperfevents(quantizedns::NoteSequence,
                       startstep::Int,
                       velocity_bins::Int,
                       max_shift_steps::Int,
                       instrument::Int = -1)

    if !quantizedns.isquantized
        throw(ArgumentError("The `NoteSequence` is not quantized."))
    end

    notes = [note for note in quantizedns.notes
             if note.start_time >= startstep &&
             (instrument == -1 || note.instrument == instrument)]

    sort!(notes, by=note->(note.start_time, note.pitch))

    onsets = [(note.start_time, idx, false) for (idx, note) in enumerate(notes)]
    offsets = [(note.end_time, idx, true) for (idx, note) in enumerate(notes)]
    noteevents = sort(vcat(onsets, offsets))

    currentstep = startstep
    currentvelocitybin = 0
    perfevents = Vector{PerformanceEvent}()

    for (step, idx, isoffset) in noteevents
        if step > currentstep
            while step > (currentstep + max_shift_steps)
                push!(perfevents, PerformanceEvent(TIME_SHIFT, max_shift_steps))
                currentstep += max_shift_steps
            end
            push!(perfevents, PerformanceEvent(TIME_SHIFT, step - currentstep))
            currentstep = step
        end

        if velocity_bins > 0
            velocity = velocity2bin(notes[idx].velocity, velocity_bins)
            if !isoffset && velocity != currentvelocitybin
                currentvelocitybin = velocity
                push!(perfevents, PerformanceEvent(VELOCITY, currentvelocitybin))
            end
        end

        push!(perfevents, PerformanceEvent(ifelse(isoffset, NOTE_OFF, NOTE_ON), notes[idx].pitch))
    end

    perfevents
end

"""
    getnotesequence(performance::Performance, velocity::Int=100, instrument::Int=1, program::Int=-1)

Return a `NoteSequence` from the `Performance`.

All of the notes in the `NoteSequence` will have the same `velocity`, `program` number
and `instrument` number.
"""
function getnotesequence(performance::Performance,
                         velocity::Int = 100,
                         instrument::Int = 1,
                         program::Int = -1)

    ticks_per_step = second2tick(1) / performance.steps_per_second
    ns = tosequence(performance, ticks_per_step, velocity, instrument, program)
    push!(ns.tempos, NoteSequences.Tempo(0, 120.0))
    push!(ns.timesignatures, MIDI.TimeSignatureEvent(0, 4, 4, 24, 8))

    ns
end

function tosequence(performance::Performance,
                    ticks_per_step::Float64,
                    velocity::Int,
                    instrument::Int,
                    program::Int)

    sequence = NoteSequence(DEFAULT_TPQ, isquantized=false)
    seqstart_time = performance.startstep * ticks_per_step

    DEFAULT_PROGRAM = 0
    if program == -1
        program = ifelse(performance.program != -1, performance.program, DEFAULT_PROGRAM)
    end

    # Map the pitch of a note to a list of start steps and velocities
    # (since may be active multiple times)
    pitchmap = DefaultDict{Int, Vector{Tuple{Int, Int}}}(Vector{Tuple{Int, Int}})
    step = 0

    for event in performance
        if event.event_type == NOTE_ON
            push!(pitchmap[event.event_value], (step, velocity))
        elseif event.event_type == NOTE_OFF
            if event.event_value in keys(pitchmap)
                pitchstartstep, pitchvelocity = popfirst!(pitchmap[event.event_value])

                if isempty(pitchmap[event.event_value])
                    delete!(pitchmap, event.event_value)
                end

                # If start step and end step are the same, ignore
                if step == pitchstartstep
                    continue
                end

                start_time = round(ticks_per_step * pitchstartstep) + seqstart_time
                end_time = round(ticks_per_step * step) + seqstart_time
                note = SeqNote(event.event_value, pitchvelocity, start_time, end_time, instrument, program)
                push!(sequence.notes, note)
                if note.end_time > sequence.total_time
                    sequence.total_time = note.end_time
                end
            end
        elseif event.event_type == TIME_SHIFT
            step += event.event_value
        elseif event.event_type == VELOCITY
            if event.event_value != velocity
                velocity = bin2velocity(event.event_value, performance.velocity_bins)
            end
        else
            throw(error("Unkown event type $(event.event_type)"))
        end
    end

    # End all the notes that weren't ended
    for pitch in keys(pitchmap)
        for (pitchstartstep, pitchvelocity) in pitchmap[pitch]
            if step == pitchstartstep
                continue
            end

            start_time = round(ticks_per_step * pitchstartstep) + seqstart_time
            end_time = round(ticks_per_step * step) + seqstart_time
            # Maybe end after 5 seconds?
            # end_time = start_time + round(ticks_per_step * 5 * performance.steps_per_second)
            note = SeqNote(pitch, pitchvelocity, start_time, end_time, instrument, program)
            push!(sequence.notes, note)
            if note.end_time > sequence.total_time
                sequence.total_time = note.end_time
            end
        end
    end

    sequence
end

"""
    truncate(performance::Performance, numevents::Int)

Truncate the performance to exactly `numevents` events.
"""
function Base.truncate(performance::Performance, numevents::Int)
    performance.events = performance.events[1:numevents]
end

function append_steps(performance::Performance, numsteps::Int)
    max_shift_steps = performance.max_shift_steps
    if (!isempty(performance) &&
        performance[end].event_type == TIME_SHIFT &&
        performance[end].event_value < max_shift_steps)

        steps = min(numsteps, max_shift_steps - performance[end].event_value)
        performance[end] = PerformanceEvent(TIME_SHIFT, performance[end].event_value + steps)
        numsteps -= steps
    end

    while numsteps >= max_shift_steps
        push!(performance, PerformanceEvent(TIME_SHIFT, max_shift_steps))
        numsteps -= max_shift_steps
    end

    if numsteps > 0
        push!(performance, PerformanceEvent(TIME_SHIFT, numsteps))
    end
end

function trim_steps(performance::Performance, numsteps::Int)
    trimmed = 0
    while !isempty(performance) && trimmed < numsteps
        if performance[end].event_type == TIME_SHIFT
            if trimmed + performance[end].event_value > numsteps
                performance[end] = PerformanceEvent(TIME_SHIFT, performance[end].event_value - numsteps + trimmed)
                trimmed = numsteps
            else
                trimmed += performance[end].event_value
                pop!(performance)
            end
        else
            pop!(performance)
        end
    end
end

"""
    setlength!(performance::Performance, steps::Int)

Sets the total length of the `Performance` based on the length given by `steps`.

If the length of the performance is greater than the given steps, it is trimmed.
Otherwise, the performance is padded with `TIME_SHIFT`s.
"""
function setlength!(performance::Performance, steps::Int)
    if performance.numsteps < steps
        append_steps(performance, steps - performance.numsteps)
    elseif performance.numsteps > steps
        trim_steps(performance, performance.numsteps - steps)
    end

    @assert performance.numsteps == steps
end

"""     binsize(velocity_bins)
Returns the size of a bin given the total number of bins.
"""
binsize(velocity_bins::Int) = Int(ceil(
        (MAX_MIDI_VELOCITY - MIN_MIDI_VELOCITY + 1) / velocity_bins))

velocity2bin(velocity::Int, velocity_bins::Int) = ((velocity - MIN_MIDI_VELOCITY) ?? binsize(velocity_bins)) + 1

"""     bin2velocity(bin, velocity_bins)
Returns a velocity value given a bin and the total number of velocity bins.
"""
bin2velocity(bin::Int, velocity_bins::Int) = MIN_MIDI_VELOCITY + (bin - 1) * binsize(velocity_bins)
