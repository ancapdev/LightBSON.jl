@enum StringEnum SE_FOO SE_BAR
@enum IntEnum IE_FOO IE_BAR

LightBSON.bson_representation_type(::Type{IntEnum}) = Int32

@testset "representations" begin

@testset "string enum" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = SE_BAR
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][Any] == "SE_BAR"
    @test BSONReader(buf, StrictBSONValidator())["x"][String] == "SE_BAR"
    @test BSONReader(buf, StrictBSONValidator())["x"][StringEnum] == SE_BAR
end

@testset "int enum" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = IE_BAR
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][Any] == Int32(IE_BAR)
    @test BSONReader(buf, StrictBSONValidator())["x"][Int32] == Int32(IE_BAR)
    @test BSONReader(buf, StrictBSONValidator())["x"][IntEnum] == IE_BAR
end

@testset "byte vector" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    x = rand(UInt8, 10)
    writer["x"] = x
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][BSONBinary].data == x
    @test BSONReader(buf, StrictBSONValidator())["x"][Vector{UInt8}] == x
    @test IndexedBSONReader(BSONIndex(10), BSONReader(buf, StrictBSONValidator()))["x"][BSONBinary].data == x
    @test IndexedBSONReader(BSONIndex(10), BSONReader(buf, StrictBSONValidator()))["x"][Vector{UInt8}] == x
end

@testset "IPv4" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    x = ip"127.0.0.0"
    y = Sockets.InetAddr(x, 1234)
    writer["x"] = x
    writer["y"] = y
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][String] == "127.0.0.0"
    @test BSONReader(buf, StrictBSONValidator())["x"][IPv4] == x
    @test BSONReader(buf, StrictBSONValidator())["y"][String] == "127.0.0.0:1234"
    @test BSONReader(buf, StrictBSONValidator())["y"][Sockets.InetAddr{IPv4}] == y
end

@testset "IPv6" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    x = ip"::c01e:fc9a"
    y = Sockets.InetAddr(x, 1234)
    writer["x"] = x
    writer["y"] = y
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][String] == "::c01e:fc9a"
    @test BSONReader(buf, StrictBSONValidator())["x"][IPv6] == x
    @test BSONReader(buf, StrictBSONValidator())["y"][String] == "[::c01e:fc9a]:1234"
    @test BSONReader(buf, StrictBSONValidator())["y"][Sockets.InetAddr{IPv6}] == y
end

end
