@testset "WriteBuffer" begin
    buf = BSONWriteBuffer()
    @test length(buf) == 0
    @test size(buf) == (0,)
    @test sizeof(buf) == 0
    push!(buf, 0x1)
    @test length(buf) == 1
    @test size(buf) == (1,)
    @test sizeof(buf) == 1
    @test GC.@preserve buf unsafe_load(pointer(buf)) == 0x1
    resize!(buf, 5)
    @test length(buf) == 5
    @test buf[1] == 0x1
    @test_throws BoundsError buf[6]
    empty!(buf)
    @test length(buf) == 0

    buf = BSONWriteBuffer()
    sizehint!(buf, 10)
    @test length(buf) == 0
    @test length(buf.data) == 10
    resize!(buf, 10)
    @test length(buf) == 10
    @test length(buf.data) == 10
    push!(buf, 0x2)
    @test length(buf) == 11
    @test length(buf.data) > 11
end