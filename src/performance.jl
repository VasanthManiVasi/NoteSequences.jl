export PerformanceEvent, Performance
export getnotesequence, encodeindex, decodeindex, set_length

const DEFAULT_MAX_SHIFT_STEPS = 100
const DEFAULT_PROGRAM = 0


"""     PerformanceEvent <: Any
Event-based performance representation from Oore et al.
In the performance representation, midi data is encoded as a 388-length one hot vector.
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

function getperfevents(
    quantizedns::NoteSequence,
    startstep::Int,
    velocity_bins::Int,
    max_shift_steps::Int,
    instrument::Int=-1)

    if !quantizedns.isquantized
        throw(ArgumentError("The `NoteSequence` is not quantized."))
    end

    notes = [note for note in quantizedns.notes if instrument == -1 || note.intrument == instrument]
    sort!(notes, by=note->(note.start_time, note.pitch))

    onsets = [(note.start_time, idx, false) for (idx, note) in enumerate(notes)]
    offets = [(note.end_time, idx, true) for (idx, note) in enumerate(notes)]
    noteevents = sort(vcat(onsets, offsets))

    currentstep = startstep
    currentvelocitybin = 0
    performanceevents = Vector{PerformanceEvent}()

    for (step, idx, isoffset) in noteevents
        if step > currentstep
            while step > currentstep + max_shift_steps
                push!(performanceevents, PerformanceEvent(TIME_SHIFT, max_shift_steps))
                currentstep += max_shift_steps
            end
            push!(performanceevents, PerformanceEvent(TIME_SHIFT, step - currentstep))
        end

        if velocity_bins > 0
            velocity = velocity2bin(notes[idx].velocity, velocity_bins)
            if !isoffset && velocity != currentvelocitybin
                currentvelocitybin = velocity
                push!(performanceevents, PerformanceEvent(VELOCITY, currentvelocitybin))
            end
        end

        push!(performanceevents, PerformanceEvent(ifelse(isoffset, NOTE_OFF, NOTE_ON), notes[idx].pitch))
    end

    performanceevents
end

"""     Performance <: Any
`Performance` is a vector of `PerformanceEvents` along with its context variables.
It stores a polyphonic music sequence as a stream of `PerformanceEvent`s.
## Fields
* `events::Vector{PerformanceEvent}` : The stream of `PerformanceEvent`s.
* `program::Int`          : Program to be used for this performance.
   If the program is -1, the default program is assigned when converting the `Performance` back to a `NoteSequence`.
* `startstep::Int`        : The beginning time step for this performance.
* `velocity_bins::Int`    : Number of bins for the velocity values.
* `steps_per_second::Int` : Number of steps per second for quantization.
* `num_classes::Int`      : Total number of event classes (`NOTE_ON` events + `NOTE_OFF` events +
                            `TIME_SHIFT` events + `VELOCITY` events)
* `max_shift_steps::Int`  : Maximum number of steps shifted by a `TIME_SHIFT event`.
* `event_ranges::Vector{Tuple{Int, Int, Int}}` : Stores the min and max values of each event type.
"""
mutable struct Performance
    events::Vector{PerformanceEvent}
    program::Int
    startstep::Int
    velocity_bins::Int
    steps_per_second::Int
    num_classes::Int
    max_shift_steps::Int
    event_ranges::Vector{Tuple{Int, Int ,Int}} # Stores the range of each event type

    function Performance(
            startstep::Int,
            velocity_bins::Int,
            steps_per_second::Int,
            max_shift_steps::Int
            ;events::Vector{PerformanceEvent}=Vector{PerformanceEvent}(),
            program::Int = -1)
        event_ranges = [
            (NOTE_ON, MIN_MIDI_PITCH, MAX_MIDI_PITCH)
            (NOTE_OFF, MIN_MIDI_PITCH, MAX_MIDI_PITCH)
            (TIME_SHIFT, 1, max_shift_steps)
        ]
        velocity_bins > 0 && push!(event_ranges, (VELOCITY, 1, velocity_bins))
        num_classes = sum(map(range -> range[3] - range[2] + 1, event_ranges))
        new(events, program, startstep, velocity_bins, steps_per_second, num_classes, max_shift_steps, event_ranges)
    end
end

function Performance(quantizedns::NoteSequence;
        startstep::Int = 0,
        velocity_bins::Int = 0,
        max_shift_steps::Int = DEFAULT_MAX_SHIFT_STEPS,
        instrument::Int = -1)

    if !quantizedns.isquantized
        throw(ArgumentError("The `NoteSequence` is not quantized."))
    end

    steps_per_second = ns.sps
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
    if sym === :labels
        return 0:(performance.num_classes - 1)
    elseif sym === :numsteps
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

Base.length(p::Performance) = length(p.events)
Base.getindex(p::Performance, idx::Int) = p.events[idx]
Base.getindex(p::Performance, range) = p.events[range]
Base.lastindex(p::Performance) = lastindex(p.events)
Base.firstindex(p::Performance) = firstindex(p.events)
Base.setindex!(p::Performance, event::PerformanceEvent, idx::Int) = setindex!(p.events, event, idx)
Base.iterate(p::Performance, state=1) = iterate(p.events, state)
Base.view(p::Performance, range) = view(p.events, range)
Base.push!(p::Performance, event::PerformanceEvent) = push!(p.events, event)
Base.pop!(p::Performance) = pop!(p.events)
Base.append!(p::Performance, events::Vector{PerformanceEvent}) = append!(p.events, events)

function Base.append!(p1::Performance, p2::Performance)
    p1.event_ranges == p2.event_ranges || throw(
        ArgumentError("The performances do not have the same event ranges."))
    p1.num_classes == p2.num_classes || throw(
        ArgumentError("The performances do not have the same number of classes."))
    append!(p1, p2.events)
end

function Base.copy(p::Performance)
    Performance(copy(p.events),
        p.velocity_bins,
        p.steps_per_second,
        p.num_classes,
        p.max_shift_steps,
        p.event_ranges)
end

function tosequence(performance::Performance, ticks_per_step::Float64, velocity::Int, instrument::Int, program::Int)
    sequence = NoteSequence(DEFAULT_TPQ, false)
    seqstart_time = performance.startstep * ticks_per_step

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
                note = SeqNote(event.event_value, pitchvelocity, start_time, end_time, program, instrument)
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
            # End after 5 seconds?
            # end_time = start_time + round(ticks_per_step * 5 * performance.steps_per_second)
            note = SeqNote(pitch, pitchvelocity, start_time, end_time, program, instrument)
            push!(sequence.notes, note)
            if note.end_time > sequence.total_time
                sequence.total_time = note.end_time
            end
        end
    end

    sequence
end

function getnotesequence(performance::Performance, velocity::Int = 100, instrument::Int = 1, program::Int = -1)
    ticks_per_step = second_to_tick(1, DEFAULT_QPM, DEFAULT_TPQ) / performance.steps_per_second
    tosequence(performance, ticks_per_step, velocity, instrument, program)
end

"""     truncate(performance::Performance, numevents)
Truncate the performance to exactly `numevents` events.
"""
function Base.truncate(performance::Performance, numevents)
    performance.events = performance.events[1:numevents]
end

function append_steps(performance::Performance, numsteps)
    max_shift_steps = performance.max_shift_steps # For readability
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

function trim_steps(performance::Performance, numsteps)
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

function set_length(performance, steps)
    if performance.numsteps < steps
        append_steps(performance, steps - performance.numsteps)
    elseif performance.numsteps > steps
        trim_steps(performance, performance.numsteps - steps)
    end

    @assert performance.numsteps == steps
end

"""     encodeindex(event::PerformanceEvent, performance::Performance)
Encodes a `PerformanceEvent` to its corresponding one hot index.
"""
function encodeindex(event::PerformanceEvent, performance::Performance)
    offset = 0
    for (type, min, max) in performance.event_ranges
        if event.event_type == type
            return offset + event.event_value - min
        end
        offset += (max - min + 1)
    end
end

"""     decodeindex(idx::Int, performance::Performance)
Decodes a one hot index to its corresponding `PerformanceEvent`.
"""
function decodeindex(idx::Int, performance::Performance)
    offset = 0
    for (type, min, max) in performance.event_ranges
        if idx < offset + (max - min + 1)
            return PerformanceEvent(type, min + idx - offset)
        end
        offset += (max - min + 1)
    end
end

"""     binsize(velocity_bins)
Returns the size of a bin given the total number of bins.
"""
binsize(velocity_bins) = Int(ceil(
        (MAX_MIDI_VELOCITY - MIN_MIDI_VELOCITY + 1) / velocity_bins))

velocity2bin(velocity, velocity_bins) = ((velocity - MIN_MIDI_VELOCITY) ÷ binsize(velocity_bins)) + 1

"""     bin2velocity(bin, velocity_bins)
Returns a velocity value given a bin and the total number of velocity bins.
"""
bin2velocity(bin, velocity_bins) = MIN_MIDI_VELOCITY + (bin - 1) * binsize(velocity_bins)

"""     second_to_tick(second, qpm, tqp)
Returns a MIDI tick corresponding to the given time in seconds,
quarter notes per minute and the amount of ticks per quarter note.
"""
second_to_tick(second, qpm, tpq) = second / (1e-3 * ms_per_tick(qpm, tpq))
