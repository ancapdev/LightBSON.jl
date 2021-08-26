@testset "WriteBuffer" begin
    buf = BSONWriteBuffer(100)
    @test length(buf) == 0
    push!(buf, 0x1)
    @test length(buf) == 1
    @test GC.@preserve buf unsafe_load(pointer(buf)) == 0x1
    resize!(buf, 5)
    @test length(buf) == 5
    @test buf[1] == 0x1
    @test_throws BoundsError buf[6]
end