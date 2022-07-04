@testset "IndexedReader" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["x"] = Int64(1)
    writer["y"] = w -> begin
        w["x"] = Int64(2)
    end
    v = [1, 2, 3]
    writer["v"] = v
    close(writer)
    reader = BSONReader(buf)
    ireader = IndexedBSONReader(BSONIndex(128), reader)
    @test ireader["x"][Int64] == 1
    @test ireader["y"]["x"][Int64] == 2
    @test ireader["v"][Vector{Int64}] == [1, 2, 3]
    for (i, x) in enumerate(v)
        @test ireader["v"][i][Int64] == x
    end
end
