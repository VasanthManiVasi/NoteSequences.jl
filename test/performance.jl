@testset "PerformanceEvent encoding/decoding" begin
    pe = PerformanceEvent
    perf = Performance(100, velocity_bins=16)
    pairs = [
        (pe(NOTE_ON, 60), 60),
        (pe(NOTE_ON, 0), 0),
        (pe(NOTE_ON, 22), 22),
        (pe(NOTE_ON, 127), 127),
        (pe(NOTE_OFF, 72), 200),
        (pe(NOTE_OFF, 0), 128),
        (pe(NOTE_OFF, 22), 150),
        (pe(NOTE_OFF, 127), 255),
        (pe(TIME_SHIFT, 10), 265),
        (pe(TIME_SHIFT, 1), 256),
        (pe(TIME_SHIFT, 72), 327),
        (pe(TIME_SHIFT, 100), 355),
        (pe(VELOCITY, 5), 360),
        (pe(VELOCITY, 1), 356),
        (pe(VELOCITY, 16), 371)
    ]

    for (event, index) in pairs
        @test index == encodeindex(event, perf)
        @test event == decodeindex(index, perf)
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