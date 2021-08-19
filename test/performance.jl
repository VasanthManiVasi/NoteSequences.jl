using NoteSequences.PerformanceRepr

const pe = PerformanceEvent

@testset "PerformanceEvent encoding/decoding" begin
    perfencoder = PerformanceOneHotEncoding(num_velocitybins=16)
    pairs = [
        (pe(NOTE_ON, 60), 61),
        (pe(NOTE_ON, 0), 1),
        (pe(NOTE_ON, 22), 23),
        (pe(NOTE_ON, 127), 128),
        (pe(NOTE_OFF, 72), 201),
        (pe(NOTE_OFF, 0), 129),
        (pe(NOTE_OFF, 22), 151),
        (pe(NOTE_OFF, 127), 256),
        (pe(TIME_SHIFT, 10), 266),
        (pe(TIME_SHIFT, 1), 257),
        (pe(TIME_SHIFT, 72), 328),
        (pe(TIME_SHIFT, 100), 356),
        (pe(VELOCITY, 5), 361),
        (pe(VELOCITY, 1), 357),
        (pe(VELOCITY, 16), 372)
    ]

    for (event, index) in pairs
        @test index == encode_event(event, perfencoder)
        @test event == decode_event(index, perfencoder)
    end
end

@testset "Performance steps and setlength!" begin
    @testset "Add length" begin
        perf = Performance(100)
        setlength!(perf, 42)
        @test perf.numsteps == 42
        @test perf.events == [pe(TIME_SHIFT, 42)]

        setlength!(perf, 142)
        @test perf.numsteps == 142
        @test perf.events == [pe(TIME_SHIFT, 100), pe(TIME_SHIFT, 42)]

        setlength!(perf, 200)
        @test perf.numsteps == 200
        @test perf.events == [pe(TIME_SHIFT, 100), pe(TIME_SHIFT, 100)]
    end

    @testset "Remove length" begin
        perf = Performance(100)
        events = [
            pe(NOTE_ON, 60),
            pe(TIME_SHIFT, 100),
            pe(NOTE_OFF, 60),
            pe(NOTE_ON, 64),
            pe(TIME_SHIFT, 100),
            pe(NOTE_OFF, 64),
            pe(NOTE_ON, 67),
            pe(TIME_SHIFT, 100),
            pe(NOTE_OFF, 67)
        ]
        append!(perf, events)
        setlength!(perf, 200)
        result_events = [
            pe(NOTE_ON, 60),
            pe(TIME_SHIFT, 100),
            pe(NOTE_OFF, 60),
            pe(NOTE_ON, 64),
            pe(TIME_SHIFT, 100),
            pe(NOTE_OFF, 64),
            pe(NOTE_ON, 67)
        ]

        @test perf.events == result_events

        setlength!(perf, 50)
        result_events = [
            pe(NOTE_ON, 60),
            pe(TIME_SHIFT, 50)
        ]

        @test perf.events == result_events
    end

    @testset "numsteps" begin
        perf = Performance(100)
        events = [
            pe(VELOCITY, 32),
            pe(NOTE_ON, 60),
            pe(TIME_SHIFT, 100),
            pe(NOTE_OFF, 60)
        ]
        append!(perf, events)

        @test perf.numsteps == 100
    end
end
