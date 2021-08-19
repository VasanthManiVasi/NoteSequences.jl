using NoteSequences.MelodyRepr
using NoteSequences.MelodyRepr: MELODY_NOTE_OFF, MELODY_NO_EVENT

@testset "MelodyOneHotEncoding" begin
    @testset "Encoding/Decoding" begin
        encoder = MelodyOneHotEncoding(43, 81)

        # (Melody event, one-hot index) pairs
        pairs = [
            (MELODY_NO_EVENT, 1),
            (MELODY_NOTE_OFF, 2),
            (43, 3),
            (80, 40),
            (79, 39),
            (50, 10),
        ]

        for (event, index) in pairs
            @test index == encode_event(event, encoder)
            @test event == decode_event(index, encoder)
        end
    end

    @testset "Out of range initialization" begin
        @test_throws ErrorException MelodyOneHotEncoding(0, 129)
        @test_throws ErrorException MelodyOneHotEncoding(-1, 100)
        @test_throws ErrorException MelodyOneHotEncoding(50, 25)
        @test_throws ErrorException MelodyOneHotEncoding(10, 10)
    end

    @testset "Test labels" begin
        @test MelodyOneHotEncoding(0, 128).labels == 1:130
        @test MelodyOneHotEncoding(43, 81).labels == 1:40
        @test MelodyOneHotEncoding(0, 1).labels == 1:3
    end
end