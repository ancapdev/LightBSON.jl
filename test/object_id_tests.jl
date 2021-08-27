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
    @test string(x1) < string(x2)
    @test string(x2) < string(x3)
end

end