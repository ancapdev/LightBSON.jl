@testset "IndexedReader" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["x"] = Int64(1)
    writer["y"] = w -> begin
        w["x"] = Int64(2)
    end
    close(writer)
    reader = BSONReader(buf)
    ireader = IndexedBSONReader(BSONIndex(128), reader)
    @test ireader["x"][Int64] == 1
    @test ireader["y"]["x"][Int64] == 2
end