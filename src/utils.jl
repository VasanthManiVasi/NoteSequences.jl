export musescore_export, second2tick

using FileIO
# using MusicVisualizations: MUSESCORE, MUSESCORE_EXISTS, test_musescore

# Temporary fix until PR to MusicVisualizations is merged
const MUSESCORE = @static if Sys.iswindows() "MuseScore3" elseif Sys.islinux() "musescore" else "mscore" end
const MUSESCORE_EXISTS = [false]

function test_musescore()
    if !MUSESCORE_EXISTS[1]
        r = try
            r = run(`$(MUSESCORE) -v`)
        catch
            false
        end
        if r == false || ((typeof(r) == Base.Process) && r.exitcode != 0)
            throw(SystemError(
            """
            The command `$(MUSESCORE) -v` did not run, which probably means that
            MuseScore is not accessible from the command line.
			Please first install MuseScore
            on your computer and then add it to your PATH."""
            ))
        end
    end
    global MUSESCORE_EXISTS[1] = true
end


"""
    musescore_export(midifilename::String)
    musescore_export(midi::MIDIFile, cleanup=true)

Use MuseScore to convert the given midifile to MP3.
If cleanup is true, the temporary midifile is deleted.
"""
function musescore_export(midifilename::String)
    MUSESCORE_EXISTS[1] || test_musescore()

    name = midifilename[1:findfirst('.', midifilename)]
    audioname = name*"mp3"

    run(`$MUSESCORE $midifilename -o $audioname`)
    @info "Exported to $audioname"

    audioname
end

function musescore_export(midi::MIDIFile, cleanup=true)
    name = tempname()
    midiname = name*".mid"
    save(midiname, midi)
    musescore_export(midiname)
    cleanup && rm(midiname)
end

"""
    musescore_export(ns::NoteSequence, cleanup=true)

Use MuseScore to convert the given `NoteSequence` to MP3.
If cleanup is true, the temporary midifile is deleted.
"""
function musescore_export(ns::NoteSequence, cleanup=true)
    midi = midifile(ns)
    musescore_export(midi, cleanup)
end

"""
    second2tick(seconds::Real, tpq::Int=DEFAULT_TPQ,  qpm::Float64=DEFAULT_QPM)

Returns a MIDI tick corresponding to the given time in seconds,
quarter notes per minute and the amount of ticks per quarter note.
"""
function second2tick(seconds::Real, tpq::Int=DEFAULT_TPQ,  qpm::Float64=DEFAULT_QPM)
    round(seconds * 1e3 / ms_per_tick(tpq, qpm))
end
