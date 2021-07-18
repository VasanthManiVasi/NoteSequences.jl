using NoteSequences: SeqNote, ControlChange

function addnotes!(ns::NoteSequence,
                   instrument::Int,
                   notes::Vector{NTuple{4, Int}};
                   program::Int=0)

    for (pitch, velocity, start_time, end_time) in notes
        note = SeqNote(pitch, velocity, start_time, end_time, instrument, program)
        push!(ns.notes, note)
        if end_time > ns.total_time
            ns.total_time = end_time
        end
    end
end

function addcontrolchanges!(ns::NoteSequence,
                            instrument::Int,
                            controlchanges::Vector{NTuple{3, Int}};
                            program::Int=0)

    for (time, controller, value) in controlchanges
        cc = ControlChange(time, controller, value, instrument, program)
        push!(ns.controlchanges, cc)
    end
end