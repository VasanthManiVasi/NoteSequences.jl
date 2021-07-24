using NoteSequences.PerformanceRepr

@testset "PerformanceEvent encoding/decoding" begin
    pe = PerformanceEvent
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
        @test index == encodeindex(event, perfencoder)
        @test event == decodeindex(index, perfencoder)
    end
end

@testset "Performance steps and set_length" begin
    @testset "Add length" begin
        perf = Performance(100)
        pe = PerformanceEvent
        set_length(perf, 42)
        @test perf.numsteps == 42
        @test perf.events == [pe(TIME_SHIFT, 42)]

        set_length(perf, 142)
        @test perf.numsteps == 142
        @test perf.events == [pe(TIME_SHIFT, 100), pe(TIME_SHIFT, 42)]

        set_length(perf, 200)
        @test perf.numsteps == 200
        @test perf.events == [pe(TIME_SHIFT, 100), pe(TIME_SHIFT, 100)]
    end

    @testset "Remove length" begin
        perf = Performance(100)
        pe = PerformanceEvent
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
        set_length(perf, 200)
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

        set_length(perf, 50)
        result_events = [
            pe(NOTE_ON, 60),
            pe(TIME_SHIFT, 50)
        ]

        @test perf.events == result_events
    end

    @testset "numsteps" begin
        perf = Performance(100)
        pe = PerformanceEvent
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
