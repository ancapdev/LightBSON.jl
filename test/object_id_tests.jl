@testset "ObjectId" begin

@testset "construct" begin
    x = BSONObjectId((0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc))
    @test BSONObjectId("0102030405060708090a0b0c") == x
    @test BSONObjectId("0102030405060708090A0B0C") == x
    @test BSONObjectId([UInt8(x) for x in 1:12]) == x
    @test_throws ArgumentError BSONObjectId("0102030405060708090a0b")
    @test_throws ArgumentError BSONObjectId("0102030405060708090a0b0c0d")
    @test_throws ArgumentError BSONObjectId("010203040506070809xxxx")
    @test_throws ArgumentError BSONObjectId([UInt8(x) for x in 1:11])
    @test_throws ArgumentError BSONObjectId([UInt8(x) for x in 1:13])
end

@testset "string" begin
    x = BSONObjectId((0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc))
    @test string(x) == "0102030405060708090a0b0c"
end

@testset "generate" begin
    x1 = BSONObjectId()
    x2 = BSONObjectId()
    x3 = BSONObjectId()
    @test x1 != x2
    @test x2 != x3
    @test now(UTC) - DateTime(x1) < Minute(5)
    @test time() - time(x1) < 5*60
end

@testset "generate range" begin
    x = collect(bson_object_id_range(3))
    @test length(x) == 3
    @test eltype(x) == BSONObjectId
    @test x[1] != x[2]
    @test x[1] != x[3]
    @test x[2] != x[3]
    @test DateTime(x[1]) == DateTime(x[2])
    @test DateTime(x[1]) == DateTime(x[3])
end

end