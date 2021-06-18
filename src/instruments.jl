export getinstruments

using MIDI: NoteOnEvent, NoteOffEvent, ProgramChangeEvent, ControlChangeEvent, PitchBendEvent, toabsolutetime!
using DataStructures: OrderedDict

mutable struct Instrument
    notes::Notes
    program::Int
    control_changes::Vector{ControlChangeEvent}
    pitch_bends::Vector{PitchBendEvent}
end

function getinstruments(midi_::MIDIFile)
    MIDI.toabsolutetime!(midi_)

    # Create an instrument map which maps:
    # (program, channel, track) => Instrument
    instrument_map = OrderedDict{Tuple{Int64, Int64, Int64}, Instrument}()
    
    for (track_num, track) in enumerate(midi.tracks)
        # Create a map of channel => program to map the channels to the current playing instrument
        # Initially all channels map to the default program (0)
        current_instrument = zeros(16)

        # Create a map of (channel, note) => (NoteOn position, velocity)
        note_map = Dict{Tuple{Int, Int}, Tuple{Int, Int}}()

        for event in track
            if event isa NoteOnEvent && event.velocity > 0
                note_map[(event.channel, event.note)] = (event.dT, event.velocity)
            elseif event isa NoteOffEvent || (event isa NoteOnEvent && event.velocity == 0)
                k = (event.channel, event.note)
                if haskey(k, note_map)
                    end_pos = event.dT
                    notes_playing = note_map[k]
                    turnoff_notes = [(pos, vel) for (pos, vel) in notes_playing if pos != end_pos]
                    continue_notes = [(pos, vel) for (pos, vel) in notes_playing if pos == end_pos]

                    program = current_instrument[event.channel]
                    key = (program, event.channel, track_num)
                    if !haskey(key, instrument_map)
                        # Create an instrument with the default program number
                        instrument = instrument_map[(program, event.channel, track_num)]
                    else
                        instrument = instrument_map[key]
                    end
                    for (position, velocity) in turnoff_notes
                        note = Note(event.note, velocity, position, position + end_pos, event.channel)
                        push!(instrument.notes, note)
                    end

                    if length(turnoff_notes) > 0 && length(continue_notes) > 0
                        note_map[k] = continue_notes
                    else
                        delete!(note_map, k)
                    end
                end
            elseif event isa ProgramChangeEvent
                current_instrument[event.channel] = event.program
                # If the intrument map has an instrument at the default program with no notes,
                # Change it's program to the current program
                key = (0, event.channel, track_num)
                if haskey(key, instrument_map)
                    instrument = instrument_map[key]
                    if isempty(instrument.notes)
                        instrument.program = event.program
                        instrument_map[(event.program, event.channel, track_num)] = instrument
                        delete!(instrument_map, key)
                    end
                end
            elseif typeof(event) in [ControlChangeEvent, PitchBendEvent]
                program = current_instrument[event.channel]
                key = (program, event.channel, track_num)
                if !haskey(key, instrument_map)
                    # Create an instrument with the default program number
                    instrument = instrument_map[(0, event.channel, track_num)]
                else
                    instrument = instrument_map[key]
                end
                if event isa ControlChangeEvent
                    push!(instrument.control_changes, event)
                elseif event isa PitchBendEvent
                    push!(instrument.pitch_bends, event)
                end
            end
        end
    end
    instruments = Vector{Instrument}()
    for instrument in values(instrument_map)
        push!(instruments, instrument)
    end
    return instruments
end
        