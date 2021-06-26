export getinstruments, getmiditracks

using MIDI: NoteOnEvent, NoteOffEvent, ProgramChangeEvent, ControlChangeEvent, PitchBendEvent, channelnumber
import MIDI: toabsolutetime!

"""
    Instrument <: Any

Data structure representing a musical instrument.

## Fields:
* `program::Int`: MIDI program of the instrument.
* `notes::Vector{Note}`: Musical notes for the instrument.
* `pitchbends::Vector{PitchBendEvent}`: Pitch bend events for the instrument.
* `controlchanges::Vector{ControlChangeEvent}`: Control change events for the instrument.
"""
Base.@kwdef struct Instrument
    program::Int = 0
    notes::Vector{Note} = []
    pitchbends::Vector{PitchBendEvent} = []
    controlchanges::Vector{ControlChangeEvent} = []
end

function Base.show(io::IO, instrument::Instrument)
    N = length(instrument.notes)
    C = length(instrument.controlchanges)
    P = length(instrument.pitchbends)
    pn = instrument.program
    print(io, "Instrument(program = $pn) with $N Notes, $C ControlChange, $P PitchBend")
end

"""
    getinstruments(midi::MIDIFile, time::Symbol=:relative)

Extract [`Instrument`](@ref)s from each [`MIDITrack`](@ref) of a [`MIDIFile`](@ref).
The argument `time` informs whether the `MIDIFile` is in `:absolute` or `:relative` time.
Internally, `getinstruments` converts relative time `MIDIFile`s to absolute time
for extracting the instruments.

If there are notes in a track that do not have a [`MIDI.ProgramChangeEvent`](@ref) 
preceding them, an `Instrument` with a default program number of zero is created.

See also: [`MIDI.getnotes`](@ref)
"""
function getinstruments(midi::MIDIFile, time::Symbol=:relative)
    # TODO: Work on a copy of the midi instead of modifying the midi file
    if time === :relative
        toabsolutetime!(midi)
    elseif time != :absolute
        throw(ArgumentError("`time` should be either :absolute or :relative"))
    end

    # Create an instrument map which maps:
    # (program, channel, track) => Instrument
    instrument_map = OrderedDict{Tuple{Int64, Int64, Int64}, Instrument}()

    for (track_num, track) in enumerate(midi.tracks)
        # Create a map of channel => program to map the channels to the current playing instrument
        # Initially all channels map to the default program (0)
        current_instrument = zeros(Int, 16)

        # Create a map of (channel, note) => (NoteOn position, velocity)
        note_map = Dict{Tuple{Int, Int}, Vector{Tuple{Int, Int}}}() # TODO: Use default dict instead

        for event in track.events
            if event isa NoteOnEvent && event.velocity > 0
                key = (channel(event), event.note)
                if haskey(note_map, key)
                    push!(note_map[key], (event.dT, event.velocity))
                else
                    note_map[key] = [(event.dT, event.velocity)]
                end
            elseif event isa NoteOffEvent || (event isa NoteOnEvent && event.velocity == 0)
                k = (channel(event), event.note)
                if haskey(note_map, k)
                    end_pos = event.dT
                    notes_playing = note_map[k]
                    turnoff_notes = [(pos, vel) for (pos, vel) in notes_playing if pos != end_pos]
                    continue_notes = [(pos, vel) for (pos, vel) in notes_playing if pos == end_pos]

                    program = current_instrument[channel(event) + 1]
                    key = (program, channel(event), track_num)
                    if !haskey(instrument_map, key)
                        # Create an instrument with the current program number
                        instrument = Instrument(program=program)
                        instrument_map[key] = instrument
                    else
                        instrument = instrument_map[key]
                    end
                    
                    for (position, velocity) in turnoff_notes
                        note = Note(event.note, velocity, position, end_pos - position, channel(event))
                        push!(instrument.notes, note)
                    end

                    if length(turnoff_notes) > 0 && length(continue_notes) > 0
                        note_map[k] = continue_notes
                    else
                        delete!(note_map, k)
                    end
                end
            elseif event isa ProgramChangeEvent
                current_instrument[channel(event) + 1] = event.program
                # If the intrument map has an instrument at the default program with no notes,
                # Change it's program to the current program
                key = (0, channel(event), track_num)
                if haskey(instrument_map, key) && event.program != 0
                    instrument = instrument_map[key]
                    if isempty(instrument.notes)
                        newinstrument = Instrument(event.program, instrument.notes, instrument.pitchbends, instrument.controlchanges)
                        instrument_map[(event.program, channel(event), track_num)] = newinstrument
                        delete!(instrument_map, key)
                    end
                end
            elseif typeof(event) in [ControlChangeEvent, PitchBendEvent]
                program = current_instrument[channel(event) + 1]
                key = (program, channel(event), track_num)
                if !haskey(instrument_map, key)
                    instrument = Instrument(program=program)
                    instrument_map[key] = instrument
                else
                    instrument = instrument_map[key]
                end

                # Store a copy of the events
                if event isa ControlChangeEvent
                    push!(instrument.controlchanges, ControlChangeEvent(event.dT, event.status, event.controller, event.value))
                elseif event isa PitchBendEvent
                    push!(instrument.pitchbends, PitchBendEvent(event.dT, event.status, event.pitch))
                end
            end
        end
    end
    
    if time === :relative
        # Convert midi back to relative time
        torelativetime!(midi)
    end

    instruments = Vector{Instrument}()
    for instrument in values(instrument_map)
        push!(instruments, instrument)
    end
    return instruments
end


"""
    getmiditracks(instruments::Vector{Instrument})

Return [`MIDITrack`](@ref)s from the [`Instrument`](@ref)s.
"""
function getmiditracks(instruments::Vector{Instrument})
    tracks = MIDITrack[]
    for (ins_num, ins) in enumerate(instruments)
        track = MIDITrack()
        # Get the channel number for the current instrument
        ins_channel = (ins_num - 1) % 16

        # Add a program change event at the beginning
        push!(track.events, ProgramChangeEvent(0, ins.program, channel = ins_channel))

        # Add control change events
        for event in ins.controlchanges
            push!(track.events, ControlChangeEvent(event.dT, event.controller, event.value, channel = ins_channel))
        end

        # Add pitch bend events
        for event in ins.pitchbends
            push!(track.events, PitchBendEvent(event.dT, event.pitch, channel = ins_channel))
        end

        # Sort the events by time and convert them to relative time
        sort!(track.events, by=event->event.dT)
        torelativetime!(track)

        # Alter the channel for each note
        for note in ins.notes
            note.channel = ins_channel
        end
        addnotes!(track, Notes(ins.notes))

        push!(tracks, track)
    end

    tracks
end

# TODO: Send a PR with the below 3 functions to MIDI.jl

"""
    toabsolutetime!(midi::MIDIFile)

Convert a midi file from relative time to absolute time.

See also: [`MIDI.toabsolutetime!`](@ref), [`torelativetime!`](@ref)
"""
function toabsolutetime!(midi::MIDIFile)
    for track in midi.tracks
        toabsolutetime!(track)
    end
    midi
end

"""
    torelativetime!(midi::MIDITrack)

Convert a midi track from absolute time to relative time.

See also: [`MIDI.toabsolutetime!`](@ref)
"""
function torelativetime!(track::MIDITrack)
    time = 0
    for event in track.events
        event.dT -= time
        time += event.dT
    end
end

"""
    torelativetime!(midi::MIDIFile)

Convert a midi file from absolute time to relative time.

See also: [`MIDI.toabsolutetime!`](@ref)
"""
function torelativetime!(midi::MIDIFile)
    for track in midi.tracks
        torelativetime!(track)
    end
    midi
end

channel(event::MIDIEvent) = Int(channelnumber(event))