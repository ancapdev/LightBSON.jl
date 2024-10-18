@testset "Reader" begin

index = BSONIndex(128)

function single_field_doc_(type::UInt8, value, endian_convert = true)
    io = IOBuffer()
    write(io, htol(Int32(4 + 1 + 2 + sizeof(value) + 1)))
    write(io, type)
    write(io, UInt8('x'))
    write(io, 0x0)
    if isbits(value)
        unsafe_write(io, Ref(endian_convert ? htol(value) : value), sizeof(value))
    else
        write(io, value)
    end
    write(io, 0x0)
    take!(io)
end

@testset "double" for reader in [
    BSONReader(single_field_doc_(BSON_TYPE_DOUBLE, 1.25)),
    IndexedBSONReader(index, BSONReader(single_field_doc_(BSON_TYPE_DOUBLE, 1.25)))
]
    @test reader["x"][Float64] == 1.25
    @test reader["x"][Number] == 1.25
    @test reader["x"][AbstractFloat] == 1.25
    @test reader["x"][Any] == 1.25
    @test sizeof(reader["x"]) == 8
end

@testset "decimal" for reader in [
    BSONReader(single_field_doc_(BSON_TYPE_DECIMAL128, d128"1.25")),
    IndexedBSONReader(index, BSONReader(single_field_doc_(BSON_TYPE_DECIMAL128, d128"1.25"))),
]
    @test reader["x"][Dec128] == d128"1.25"
    @test reader["x"][Number] == d128"1.25"
    @test reader["x"][AbstractFloat] == d128"1.25"
    @test reader["x"][Any] == d128"1.25"
    @test sizeof(reader["x"]) == 16
end

@testset "int32" for reader in [
    BSONReader(single_field_doc_(BSON_TYPE_INT32, Int32(123))),
    IndexedBSONReader(index, BSONReader(single_field_doc_(BSON_TYPE_INT32, Int32(123)))),
]
    @test reader["x"][Int32] == 123
    @test reader["x"][Number] == 123
    @test reader["x"][Integer] == 123
    @test reader["x"][Any] == 123
    @test sizeof(reader["x"]) == 4
end

@testset "int64" for reader in [
    BSONReader(single_field_doc_(BSON_TYPE_INT64, Int64(123))),
    IndexedBSONReader(index, BSONReader(single_field_doc_(BSON_TYPE_INT64, Int64(123)))),
]
    @test reader["x"][Int64] == 123
    @test reader["x"][Number] == 123
    @test reader["x"][Integer] == 123
    @test reader["x"][Any] == 123
    @test sizeof(reader["x"]) == 8
end

@testset "bool" for reader in [
    BSONReader(single_field_doc_(BSON_TYPE_BOOL, 0x1)),
    IndexedBSONReader(index, BSONReader(single_field_doc_(BSON_TYPE_BOOL, 0x1))),
]
    @test reader["x"][Bool] == true
    @test reader["x"][Any] == true
    @test sizeof(reader["x"]) == 1
    reader = BSONReader(single_field_doc_(BSON_TYPE_BOOL, 0x0))
    @test reader["x"][Bool] == false
    @test reader["x"][Any] == false
end

@testset "date" begin
    d = Date(2021, 1, 2)
    v = trunc(Int64, datetime2unix(DateTime(d)) * 1000)
    reader = BSONReader(single_field_doc_(BSON_TYPE_DATETIME, v))
    @test reader["x"][Date] == d
    @test reader["x"][Any] == DateTime(d)
    @test sizeof(reader["x"]) == 8
end

@testset "datetime" begin
    t = DateTime(2021, 1, 2, 9, 30)
    v = trunc(Int64, datetime2unix(t) * 1000)
    reader = BSONReader(single_field_doc_(BSON_TYPE_DATETIME, v))
    @test reader["x"][DateTime] == t
    @test reader["x"][Any] == t
    @test sizeof(reader["x"]) == 8
end

@testset "timestamp" begin
    x = BSONTimestamp(1, 2)
    reader = BSONReader(single_field_doc_(BSON_TYPE_TIMESTAMP, x))
    @test reader["x"][BSONTimestamp] == x
    @test reader["x"][Any] == x
    @test sizeof(reader["x"]) == 8
end

@testset "ObjectId" begin
    x = BSONObjectId((
        0x1, 0x2, 0x3, 0x4,
        0x5, 0x6, 0x7, 0x8,
        0x9, 0xA, 0xB, 0xC,
    ))
    reader = BSONReader(single_field_doc_(BSON_TYPE_OBJECTID, x, false))
    @test reader["x"][BSONObjectId] == x
    @test reader["x"][Any] == x
    @test sizeof(reader["x"]) == 12
end

@testset "string" begin
    x = "test"
    io = IOBuffer()
    write(io, htol(Int32(length(x) + 1)))
    write(io, x)
    write(io, 0x0)
    buf = take!(io)
    reader = BSONReader(single_field_doc_(BSON_TYPE_STRING, buf))
    @test reader["x"][String] == x
    @test reader["x"][Any] == x
    @test sizeof(reader["x"]) == length(x) + 5
    reader = BSONReader(single_field_doc_(BSON_TYPE_CODE, buf))
    @test reader["x"][String] == x
    @test reader["x"][Any] == BSONCode(x)
    @test sizeof(reader["x"]) == length(x) + 5
end

@testset "binary" begin
    x = rand(UInt8, 10)
    io = IOBuffer()
    write(io, htol(Int32(length(x))))
    write(io, BSON_SUBTYPE_GENERIC_BINARY)
    write(io, x)
    reader = BSONReader(single_field_doc_(BSON_TYPE_BINARY, take!(io)))
    x2 = reader["x"][BSONBinary]
    @test x2.data == x
    @test x2.subtype == BSON_SUBTYPE_GENERIC_BINARY
    x2 = reader["x"][UnsafeBSONBinary]
    @test x2.data == x
    @test x2.subtype == BSON_SUBTYPE_GENERIC_BINARY
    x2 = reader["x"][Any]
    @test x2 isa BSONBinary
    @test x2.data == x
    @test x2.subtype == BSON_SUBTYPE_GENERIC_BINARY
    @test sizeof(reader["x"]) == length(x) + 5
end

@testset "uuid" begin
    x = uuid4()
    io = IOBuffer()
    write(io, htol(Int32(16)))
    write(io, BSON_SUBTYPE_UUID)
    unsafe_write(io, Ref(hton(UInt128(x))), 16)
    reader = BSONReader(single_field_doc_(BSON_TYPE_BINARY, take!(io)))
    @test reader["x"][UUID] == x
    @test reader["x"][Any] == x
    @test sizeof(reader["x"]) == 21
end

@testset "heterogenous array" begin
    io = IOBuffer()
    len = Int32(4 + 11 + 11 + 4 + 1)
    write(io, htol(len))
    write(io, BSON_TYPE_DOUBLE)
    write(io, UInt8('1'))
    write(io, 0x0)
    write(io, 1.25)
    write(io, BSON_TYPE_INT64)
    write(io, UInt8('2'))
    write(io, 0x0)
    write(io, Int64(123))
    write(io, BSON_TYPE_BOOL)
    write(io, UInt8('3'))
    write(io, 0x0)
    write(io, 0x1)
    write(io, 0x0)
    buf = take!(io)
    @assert len == length(buf)
    reader = BSONReader(single_field_doc_(BSON_TYPE_ARRAY, buf))
    @test reader["x"][Vector{Any}] == [1.25, Int64(123), true]
    @test reader["x"][Any] == [1.25, Int64(123), true]
    @test sizeof(reader["x"]) == len
end

@testset "homogenous array" begin
    io = IOBuffer()
    len = Int32(4 + 11 * 3 + 1)
    write(io, htol(len))
    write(io, BSON_TYPE_INT64)
    write(io, UInt8('1'))
    write(io, 0x0)
    write(io, Int64(1))
    write(io, BSON_TYPE_INT64)
    write(io, UInt8('2'))
    write(io, 0x0)
    write(io, Int64(2))
    write(io, BSON_TYPE_INT64)
    write(io, UInt8('3'))
    write(io, 0x0)
    write(io, Int64(3))
    write(io, 0x0)
    buf = take!(io)
    @assert len == length(buf)
    reader = BSONReader(single_field_doc_(BSON_TYPE_ARRAY, buf))
    @test reader["x"][Vector{Int64}] == Int64[1, 2, 3]
    @test reader["x"][1][Int64] == 1
    @test reader["x"][3][Int64] == 3
    @test sizeof(reader["x"]) == len
end

@testset "regex" begin
    io = IOBuffer()
    write(io, "test")
    write(io, 0x0)
    write(io, "abc")
    write(io, 0x0)
    reader = BSONReader(single_field_doc_(BSON_TYPE_REGEX, take!(io)))
    x = reader["x"][BSONRegex]
    @test x.pattern == "test"
    @test x.options == "abc"
    x = reader["x"][Any]
    @test x.pattern == "test"
    @test x.options == "abc"
    @test sizeof(reader["x"]) == 9
end

@testset "conversion error $T" for T in [
    Float64,
    Int64,
    Int32,
    Bool,
    DateTime,
    Dec128,
    UUID,
    String,
    Nothing,
    BSONTimestamp,
    BSONObjectId,
    BSONBinary,
    UnsafeBSONBinary,
    BSONRegex,
    BSONCode,
    BSONSymbol,
    BSONMinKey,
    BSONMaxKey,
    BSONUndefined,
    BSONDBPointer,
    BSONUUIDOld
]
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["x"] = T == Int64 ? 1.25 : Int64(123)
    close(writer)
    reader = BSONReader(buf)
    @test_throws BSONConversionError(T == Int64 ? BSON_TYPE_DOUBLE : BSON_TYPE_INT64, T) reader["x"][T]
end

@testset "long field name skip" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["some_very_long_field_name"] = 123
    writer["x"] = 456
    close(writer)
    reader = BSONReader(buf)
    @test reader["x"][Int] == 456
end

@testset "missing field" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["x"] = 123
    close(writer)
    reader = BSONReader(buf)
    reader["y"][Any] === nothing
end

@testset "foreach" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["x"] = 1
    writer["y"] = 2
    writer["z"] = 3
    close(writer)
    reader = BSONReader(buf)
    values = Pair{String, Int}[]
    foreach(x -> push!(values, x.first => x.second[Int]), reader)
    @test values == ["x" => 1, "y" => 2, "z" => 3]
end

@testset "optional" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["x"] = nothing
    writer["y"] = 123
    close(writer)
    reader = BSONReader(buf)
    @test reader["x"][Union{Nothing, Int}] === nothing
    @test reader["y"][Union{Nothing, Int}] === 123
    @test sizeof(reader["x"]) == 0
    @test sizeof(reader["y"]) == 8
    @test sizeof(reader) == 19
end

@testset "getindex AbstractBSONReader" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer["x"] = 123
    close(writer)
    reader = BSONReader(buf)
    @test reader["x"][AbstractBSONReader] == reader["x"]
    @test reader["x"][typeof(reader)] == reader["x"]
end

end