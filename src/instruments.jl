export getinstruments

using MIDI: NoteOnEvent, NoteOffEvent, ProgramChangeEvent, ControlChangeEvent, PitchBendEvent, channelnumber
import MIDI: toabsolutetime!
using DataStructures: OrderedDict

Base.@kwdef struct Instrument
    program::Int = 0
    notes::Notes = Notes()
    pitch_bends::Vector{PitchBendEvent} = []
    control_changes::Vector{ControlChangeEvent} = []
end

function Base.show(io::IO, instrument::Instrument)
    N = length(instrument.notes)
    C = length(instrument.control_changes)
    P = length(instrument.pitch_bends)
    pn = instrument.program
    print(io, "Instrument(program = $pn) with $N Notes, $C ControlChange, $P PitchBend")
end

function toabsolutetime!(midi::MIDIFile)
    for track in midi.tracks
        toabsolutetime!(track)
    end
    midi
end

function torelativetime!(track::MIDITrack)
    time = 0
    for event in track.events
        event.dT -= time
        time += event.dT
    end
end

function torelativetime!(midi::MIDIFile)
    for track in midi.tracks
        torelativetime!(track)
    end
    midi
end

function channel(event::MIDIEvent)
    Int(channelnumber(event))
end

function getinstruments(midi::MIDIFile)
    # TODO: Work on a copy of the midi instead of modifying the midi file
    toabsolutetime!(midi)

    # Create an instrument map which maps:
    # (program, channel, track) => Instrument
    instrument_map = OrderedDict{Tuple{Int64, Int64, Int64}, Instrument}()

    for (track_num, track) in enumerate(midi.tracks)
        # Create a map of channel => program to map the channels to the current playing instrument
        # Initially all channels map to the default program (0)
        current_instrument = zeros(Int, 16)

        # Create a map of (channel, note) => (NoteOn position, velocity)
        note_map = Dict{Tuple{Int, Int}, Vector{Tuple{Int, Int}}}() # TODO: Use default dict instead

        for (idx, event) in enumerate(track.events)
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
                        newinstrument = Instrument(event.program, instrument.notes, instrument.pitch_bends, instrument.control_changes)
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
                    push!(instrument.control_changes, ControlChangeEvent(event.dT, event.status, event.controller, event.value))
                elseif event isa PitchBendEvent
                    push!(instrument.pitch_bends, PitchBendEvent(event.dT, event.status, event.pitch))
                end
            end
        end
    end
    
    # Convert midi back to relative time
    torelativetime!(midi)

    instruments = Vector{Instrument}()
    for instrument in values(instrument_map)
        push!(instruments, instrument)
    end
    return instruments
end