export Melody

using ..NoteSequences: DEFAULT_STEPS_PER_BAR, DEFAULT_STEPS_PER_QUARTER
using ..NoteSequences: DEFAULT_QPM, DEFAULT_TPQ
using MacroTools: @forward

"""
    Melody <: Any

Melody is an intermediate representation for monophonic musical sequences.
Melody events are integers in the range [-2, 127].
The negative values are `MELODY_NO_EVENt`, `MELODY_NOTE_OFF` and they are special events.
Note on events are the non-negative values from [0, 127] and they represent a midi pitch.

A melody note starts at a midi pitch value (non-negative). The note is sustained through
the following `MELODY_NO_EVENT`s until another midi pitch is reached or a `MELODY_NOTE_OFF`
event is reached.

## Fields
* `events::Vector{Int}`: The monophonic melody events in the sequence.
* `steps_per_bar::Int`: Number of steps per bar of music.
* `steps_per_quarter::Int`: Number of steps per quarter note.
* `startstep::Int`: The first step of the melody in the sequence.
* `endstep::Int`: The last step of the melody in the sequence.
"""
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

"""
    Melody(qns::NoteSequence,
                search_start_step::Int=0,
                gapbars::Int=1,
                ignore_polyphony::Bool=false,
                pad_end::Bool=false,
                instrument::Int=1)

Convert the given quantized notesequence to a melody. The melody is extracted starting from
`search_start_step`. The melody extraction will be ended when there is a silence for more than
`gapbars` amount of bars in music.

If `ignore_polyphony` is true, only the highest pitch is kept when multiple pitches are encountered.
Otherwise, an error is thrown.

0 velocity notes are ignored when extracting the melody. If `pad_end` is true, the melody is padded with
`MELODY_NO_EVENt` until the end of the bar.
"""
function Melody(qns::NoteSequence,
                search_start_step::Int=0,
                gapbars::Int=1,
                ignore_polyphony::Bool=false,
                pad_end::Bool=false,
                instrument::Int=1)

    !qns.isquantized && throw(error("NoteSequence must be relative quantized."))

    quarters_per_beat = 4 / qns.timesignatures[1].denominator
    quarters_per_bar = quarters_per_beat * qns.timesignatures[1].numerator
    steps_per_bar = quarters_per_bar * qns.steps_per_quarter
    steps_per_bar % 1 != 0 && throw(error("Steps per bar must be an integer"))

    melody = Melody()
    melody.steps_per_bar = round(steps_per_bar)
    melody.steps_per_quarter = qns.steps_per_quarter

    notes = [note for note in qns.notes
             if note.instrument == instrument && note.start_time >= search_start_step]

    isempty(notes) && return

    sort!(notes, by=note -> (note.start_time, -note.pitch))

    initial_distance = (notes[1].start_time - search_start_step)
    melody_start_step = notes[1].start_time - initial_distance % melody.steps_per_bar

    for note in notes
        note.velocity == 0 && continue

        note_start_step = note.start_time - melody_start_step
        note_end_step = note.end_time - melody_start_step

        if isempty(melody.events)
            addnote!(melody, note.pitch, note_start_step, note_end_step)
            continue
        end

        laston, lastoff = last_onoff_events(melody)

        on_distance = note_start_step - laston
        off_distance = note_start_step - lastoff

        if on_distance == 0
            if ignore_polyphony
                continue # Keeps the highest note
            else
                throw(error("More than one note is found at the same time."))
            end
        elseif on_distance < 0
            throw(error("Notes not in ascending order. This is caused due to polyphonic melody."))
        end

        gapsteps = gapbars * melody.steps_per_bar

        # End the melody if there is a silence of `gap_bars` or More
        !isempty(melody) && off_distance >= gapsteps && break

        addnote!(melody, note.pitch, note_start_step, note_end_step)
    end

    isempty(melody) && return

    melody.startstep = melody_start_step
    melody[end] == MELODY_NOTE_OFF && pop!(melody.events)

    melodylength = length(melody)
    if pad_end
        melodylength += (-melodylength % melody.steps_per_bar)
    end
    setlength!(melody, melodylength)

    melody
end

"""
    getnotesequence(melody::Melody;
                    velocity::Int=100,
                    instrument::Int=1,
                    program::Int=0,
                    sequence_start_time::Int=0,
                    qpm::Float64=DEFAULT_QPM)

Convert the given melody to a `NoteSequence`. The notes events will have the same `velocity`,
`program` and `instrument`. The melody will start at `sequence_start_time` in the sequence
and will have a tempo of `qpm` (quarter notes per minute).
"""
function getnotesequence(melody::Melody;
                         velocity::Int=100,
                         instrument::Int=1,
                         program::Int=0,
                         sequence_start_time::Int=0,
                         qpm::Float64=DEFAULT_QPM)

    seconds_per_step = 60 / qpm / melody.steps_per_quarter
    ns = NoteSequence()
    push!(ns.tempos, NoteSequences.Tempo(0, qpm))
    ns.tpq = DEFAULT_TPQ

    sequence_start_time += melody.startstep * seconds_per_step
    note_is_playing = false
    local current_seqnote

    for (step, note) in enumerate(melody)
        seconds = step * seconds_per_step + sequence_start_time
        new_note_start_time = second2tick(seconds)

        if MIN_MIDI_PITCH <= note <= MAX_MIDI_PITCH
            if note_is_playing
                # End the sustained note
                current_seqnote.end_time = new_note_start_time
            end

            current_seqnote = NoteSequences.SeqNote(note, velocity,
                                                    new_note_start_time, 0,
                                                    instrument, program)

            push!(ns.notes, current_seqnote)
            note_is_playing = true

        elseif note == MELODY_NOTE_OFF
            if note_is_playing
                current_seqnote.end_time = new_note_start_time
                note_is_playing = false
            end
        end
    end

    if note_is_playing
        current_seqnote.end_time = second2tick(length(melody) * seconds_per_step + sequence_start_time)
    end

    if !isempty(ns.notes)
        ns.total_time = ns.notes[end].end_time
    end

    ns
end

"""
    setlength!(melody::Melody, steps::Int)

Set the length of the melody to `steps`. If the given `steps` is greater than
the length of the melody, the melody will be padded with `MELODY_NO_EVENT`s to the right.
If `steps` is smaller than the length of the melody, the melody will be truncated.
"""
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

"""
    addnote!(melody::Melody, pitch::Int, startstep::Int, endstep::Int)

Adds the given note to the melody at `startstep` and `endstep`.
The `endstep` will be set to a `MELODY_NOTE_OFF`.
"""
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

"""
    last_onoff_events(melody::Melody)

Return the indices of the last midi pitch and `MELODY_NOTE_OFF` in the sequence.
"""
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