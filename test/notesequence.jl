using NoteSequences: temporalstretch!, transpose

@testset "Temporal stretch" begin
    @testset "Speed up" begin
        ns = NoteSequence()
        addnotes!(ns, 0, [(60, 100, 0, 220), (64, 100, 220, 440), (67, 100, 440, 660)])
        temporalstretch!(ns, 3)
        @test notes(ns, 0) == [(60, 100, 0, 660), (64, 100, 660, 1320), (67, 100, 1320, 1980)]
        @test ns.total_time == 1980
    end

    @testset "Slow down" begin
        ns = NoteSequence()
        addnotes!(ns, 0, [(60, 100, 0, 220), (64, 100, 220, 440), (67, 100, 440, 660)])
        temporalstretch!(ns, 0.25)
        @test notes(ns, 0) == [(60, 100, 0, 55), (64, 100, 55, 110), (67, 100, 110, 165)]
        @test ns.total_time == 165
    end
end

@testset "Transpose" begin
    @testset "Higher and lower transpositions" begin
        ns = NoteSequence()
        addnotes!(ns, 1, [(116, 4, 0, 1), (42, 75, 103, 635), (67, 100, 216, 773)])

        higher_ns, num_deleted = transpose(ns, 1, 0, 127)
        @test notes(higher_ns, 1) == [(117, 4, 0, 1), (43, 75, 103, 635), (68, 100, 216, 773)]
        @test num_deleted == 0

        lower_ns, num_deleted = transpose(ns, -3, 0, 127)
        @test notes(lower_ns, 1) == [(113, 4, 0, 1), (39, 75, 103, 635), (64, 100, 216, 773)]
        @test num_deleted == 0
    end

    @testset "Out of range transpositions" begin
        ns = NoteSequence()
        addnotes!(ns, 1, [(116, 4, 0, 1), (42, 75, 103, 635), (67, 100, 216, 773)])

        removed_ns, num_deleted = transpose(ns, -12, 20, 60)
        @test notes(removed_ns, 1) == [(30, 75, 103, 635), (55, 100, 216, 773)]
        @test num_deleted == 1

        removed_ns, num_deleted = transpose(ns, 4, 100, 120)
        @test notes(removed_ns, 1) == [(120, 4, 0, 1)]
        @test num_deleted == 2
    end
end