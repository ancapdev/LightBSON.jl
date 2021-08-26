@testset "Index" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["x"] = Int64(1)
    writer["y"] = w -> begin
        w["x"] = Int64(2)
    end
    close(writer)
    reader = BSONReader(buf)
    index = BSONIndex(128)
    index[] = reader
    entry = index[LightBSON.BSONIndexKey("x", 0)]
    @test entry !== nothing
    @test entry.type == BSON_TYPE_INT64
    @test entry.offset == 7
    entry = index[LightBSON.BSONIndexKey("y", 0)]
    @test entry !== nothing
    @test entry.type == BSON_TYPE_DOCUMENT
    @test entry.offset == 18
    entry = index[LightBSON.BSONIndexKey("x", 18)]
    @test entry !== nothing
    @test entry.type == BSON_TYPE_INT64
    @test entry.offset == 25
end