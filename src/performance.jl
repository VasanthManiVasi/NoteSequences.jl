export PerformanceEvent, Performance
export encodeindex, decodeindex, set_length

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

"""     Performance <: Any
`Performance` is a vector of `PerformanceEvents` along with its context variables
## Fields
* `events::Vector{PerformanceEvent}` : The actual performance vector.
* `velocity_bins::Int`    : Number of bins for velocity values.
* `steps_per_second::Int` : Number of steps per second for quantization.
* `num_classes::Int`      : Total number of event classes (`NOTE_ON` events + `NOTE_OFF` events +
                            `TIME_SHIFT` events + `VELOCITY` events)
* `max_shift_steps::Int`  : Maximum number of shift steps in a `TIME_SHIFT`.
* `event_ranges::Vector{Tuple{Int, Int, Int}}` : Stores the min and max values of each event type.
"""
mutable struct Performance
    events::Vector{PerformanceEvent}
    velocity_bins::Int
    steps_per_second::Int
    num_classes::Int
    max_shift_steps::Int
    event_ranges::Vector{Tuple{Int, Int ,Int}} # Stores the range of each event type

    function Performance(;
            velocity_bins::Int = 32,
            steps_per_second::Int = 100,
            max_shift_steps::Int = 100,
            events::Vector{PerformanceEvent}=Vector{PerformanceEvent}())
        event_ranges = [
            (NOTE_ON, MIN_MIDI_PITCH, MAX_MIDI_PITCH)
            (NOTE_OFF, MIN_MIDI_PITCH, MAX_MIDI_PITCH)
            (TIME_SHIFT, 1, max_shift_steps)
        ]
        velocity_bins > 0 && push!(event_ranges, (VELOCITY, 1, velocity_bins))
        num_classes = sum(map(range -> range[3] - range[2] + 1, event_ranges))
        new(events, velocity_bins, steps_per_second, num_classes, max_shift_steps, event_ranges)
    end
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

"""     bin2velocity(bin, velocity_bins)
Returns a velocity value given a bin and the total number of velocity bins.
"""
bin2velocity(bin, velocity_bins) = MIN_MIDI_VELOCITY + (bin - 1) * binsize(velocity_bins)

"""     second_to_tick(second, qpm, tqp)
Returns a MIDI tick corresponding to the given time in seconds,
quarter notes per minute and the amount of ticks per quarter note.
"""
second_to_tick(second, qpm, tpq) = second / (1e-3 * ms_per_tick(qpm, tpq))