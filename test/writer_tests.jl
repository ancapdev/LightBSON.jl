@testset "Writer" begin

# NOTE: Not ideal to be testing with dependence on reader,
#       but reader is tested on expected byte representations so assuming reader is good this is a lot easier
@testset "single field $(typeof(x))" for x in [
    Int32(123),
    Int64(123),
    1.25,
    d128"1.25",
    true,
    nothing,
    Date(2021, 1, 2),
    DateTime(2021, 1, 2, 9, 30),
    BSONTimestamp(1, 2),
    BSONObjectId((
        0x1, 0x2, 0x3, 0x4,
        0x5, 0x6, 0x7, 0x8,
        0x9, 0xA, 0xB, 0xC,
    )),
    "test",
    BSONBinary([0x1, 0x2, 0x3]),
    uuid4(),
    BSONCode("f() = 1;"),
    BSONRegex("test", "abc"),
]
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = x
    close(writer)
    BSONReader(buf, StrictBSONValidator())["x"][typeof(x)] == x
end

@testset "single field UnsafeBSONString" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    str = "teststr"
    writer["x"] = UnsafeBSONString(pointer(str), length(str))
    close(writer)
    BSONReader(buf, StrictBSONValidator())["x"][String] == str
end

@testset "single field UnsafeBSONBinary" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    data = rand(UInt8, 10)
    writer["x"] = UnsafeBSONBinary(UnsafeArray(pointer(data), (length(data),)))
    close(writer)
    BSONReader(buf, StrictBSONValidator())["x"][UnsafeBSONBinary] == data
end

@testset "document" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = w -> begin
        w["a"] = 1
        w["b"] = 2
    end
    close(writer)
    reader = BSONReader(buf, StrictBSONValidator())
    @test reader["x"].type == BSON_TYPE_DOCUMENT
    @test reader["x"]["a"][Int] == 1
    @test reader["x"]["b"][Int] == 2
end

@testset "array" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = [1, 2, 3]
    close(writer)
    reader = BSONReader(buf, StrictBSONValidator())
    @test reader["x"].type == BSON_TYPE_ARRAY
    @test reader["x"][Vector{Int}] == [1, 2, 3]
end

@testset "array generator" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = (x * x for x in 1:3)
    close(writer)
    reader = BSONReader(buf, StrictBSONValidator())
    @test reader["x"].type == BSON_TYPE_ARRAY
    @test reader["x"][Vector{Int}] == [1, 4, 9]
end

@testset "array generator documents" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = (
        w -> begin
            w["a"] = x
            w["b"] = x * x
        end
        for x in 1:3
    )
    close(writer)
    reader = BSONReader(buf, StrictBSONValidator())
    @test reader["x"].type == BSON_TYPE_ARRAY
    @test reader["x"]["0"].type == BSON_TYPE_DOCUMENT
    @test reader["x"]["0"]["a"][Int] == 1
    @test reader["x"]["0"]["b"][Int] == 1
    @test reader["x"]["1"].type == BSON_TYPE_DOCUMENT
    @test reader["x"]["1"]["a"][Int] == 2
    @test reader["x"]["1"]["b"][Int] == 4
    @test reader["x"]["2"].type == BSON_TYPE_DOCUMENT
    @test reader["x"]["2"]["a"][Int] == 3
    @test reader["x"]["2"]["b"][Int] == 9
end

@testset "dict" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    x = Dict{String, Any}("x" => 1, "y" => Dict{String, Any}("a" => 1, "b" => 2))
    writer[] = x
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())[Any] == x
end

@testset "typed dict" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    x = Dict{String, Int}("x" => 1, "y" => 2)
    writer[] = x
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())[Any] == x
end

@testset "symbol name" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer[:x] = 123
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][Any] == 123
end

@testset "pair" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer[] = "x" => 123
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][Any] == 123
end

@testset "tuple of pairs" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer[] = ("x" => 123, "y" => 1.25)
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][Any] == 123
    @test BSONReader(buf, StrictBSONValidator())["y"][Any] == 1.25
end

@testset "empty struct" begin
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = EmptyStruct()
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][Any] == Dict{String, Any}()
    @test BSONReader(buf, StrictBSONValidator())["x"][EmptyStruct] == EmptyStruct()
end

@testset "from reader" begin
    doc1 = bson_write(UInt8[], (; x = 1, y = "foo"))
    doc2 = bson_write(UInt8[], (; z = false))
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["a"] = BSONReader(doc1)
    writer["b"] = BSONReader(doc2)
    writer["c"] = [BSONReader(doc1), BSONReader(doc2)]
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["a"][Any] == LittleDict("x" => 1, "y" => "foo")
    @test BSONReader(buf, StrictBSONValidator())["b"][Any] == LittleDict("z" => false)
    @test BSONReader(buf, StrictBSONValidator())["c"][Any] == [
        LittleDict("x" => 1, "y" => "foo"),
        LittleDict("z" => false)
    ]
end

end
