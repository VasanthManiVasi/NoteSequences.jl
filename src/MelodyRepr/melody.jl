export Melody

using ..NoteSequences: DEFAULT_STEPS_PER_BAR, DEFAULT_STEPS_PER_QUARTER
using ..NoteSequences: DEFAULT_QPM, DEFAULT_TPQ
using MacroTools: @forward

mutable struct Melody
    events::Vector{Int}
    steps_per_bar::Int
    steps_per_quarter::Int
    startstep::Int
    endstep::Int

    function Melody(;events::Vector{Int}=Int[],
                     startstep::Int=0,
                     steps_per_bar::Int=DEFAULT_STEPS_PER_BAR,
                     steps_per_quarter::Int=DEFAULT_STEPS_PER_QUARTER)

        if !isempty(events)
            for event in events
                isoutofrange(event) &&
                    throw(error("Melody event is out of range"))
            end

            # Up to the first event, replace MELODY_NOTE_OFF with MELODY_NO_EVENT
            # to prevent unwanted note-offs.
            for (i, event) in enumerate(events)
                event ∉ [MELODY_NO_EVENT, MELODY_NOTE_OFF] && break
                events[i] = MELODY_NO_EVENT
            end
        end

        endstep = startstep + length(events)
        new(events, steps_per_bar, steps_per_quarter, startstep, endstep)
    end
end

@forward Melody.events Base.getindex, Base.length, Base.iterate, Base.lastindex

function Base.push!(melody::Melody, event::Int)
    isoutofrange(event) && throw(error("Melody event is out of range"))
    push!(melody.events, event)
    melody.endstep += 1
    melody
end

function Base.append!(melody::Melody, events::Vector{Int})
    append!(melody.events, events)
    melody.endstep += length(events)
    melody
end

Base.setindex!(m::Melody, event::Int, idx::Int) = setindex!(m.events, event, idx)

function setlength!(melody::Melody, steps::Int)
    oldlength = length(melody)

    if steps > length(melody)
        padding = fill(MELODY_NO_EVENT, (steps - length(melody)))
        append!(melody, padding)
    else
        melody.events = melody.events[1:steps]
    end

    melody.endstep = melody.startstep + steps

    if steps > oldlength
        for i = oldlength:-1:1
            if melody[i] == MELODY_NOTE_OFF
                break
            elseif melody[i] != MELODY_NO_EVENT
                melody[oldlength] = MELODY_NOTE_OFF
            end
        end
    end

    melody
end

function addnote!(melody::Melody, pitch::Int, startstep::Int, endstep::Int)
    startstep >= endstep && throw(error("End step must be greater than start step."))
    setlength!(melody, endstep)
    melody[startstep] = pitch
    melody[endstep] = MELODY_NOTE_OFF

    for i = (startstep + 1):endstep
        melody[i] = MELODY_NO_EVENT
    end

    melody
end

function last_onoff_events(melody::Melody)
    lastoff = length(melody)
    for i = (length(melody)-1):-1:-1
        if melody[i] == MELODY_NOTE_OFF
            lastoff = i
        end
        melody[i] >= MIN_MIDI_PITCH && return (i, lastoff)
    end
end

isoutofrange(event::Int) = !(MIN_MELODY_EVENT <= event <= MAX_MELODY_EVENT)