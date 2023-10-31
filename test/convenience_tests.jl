@testset "convenience" begin
    x = LittleDict{String, Any}("x" => 1, "y" => 2)
    buf = bson_write(UInt8[], x)
    @test bson_read(buf) == x
    io = IOBuffer()
    bson_write(io, x)
    seekstart(io)
    @test bson_read(io) == x
    path, io = mktemp()
    bson_write(path, x)
    @test bson_read(path) == x
end