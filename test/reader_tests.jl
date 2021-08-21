@testset "Reader" begin

function single_field_doc_(type::UInt8, value)
    io = IOBuffer()
    write(io, Int32(4 + 1 + 2 + sizeof(value) + 1))
    write(io, type)
    write(io, UInt8('x'))
    write(io, 0x0)
    if isbits(value)
        unsafe_write(io, Ref(value), sizeof(value))
    else
        write(io, value)
    end
    write(io, 0x0)
    take!(io)
end

@testset "double" begin
    reader = BSONReader(single_field_doc_(BSON_TYPE_DOUBLE, 1.25))
    @test reader["x"][Float64] == 1.25
    @test reader["x"][Number] == 1.25
    @test reader["x"][AbstractFloat] == 1.25
    @test reader["x"][Any] == 1.25
end

@testset "double" begin
    reader = BSONReader(single_field_doc_(BSON_TYPE_DECIMAL128, d128"1.25"))
    @test reader["x"][Dec128] == d128"1.25"
    @test reader["x"][Number] == d128"1.25"
    @test reader["x"][AbstractFloat] == d128"1.25"
    @test reader["x"][Any] == d128"1.25"
end

@testset "int32" begin
    reader = BSONReader(single_field_doc_(BSON_TYPE_INT32, Int32(123)))
    @test reader["x"][Int32] == 123
    @test reader["x"][Int64] == 123
    @test reader["x"][Number] == 123
    @test reader["x"][Integer] == 123
    @test reader["x"][Any] == 123
end

@testset "int64" begin
    reader = BSONReader(single_field_doc_(BSON_TYPE_INT64, Int64(123)))
    @test reader["x"][Int64] == 123
    @test reader["x"][Number] == 123
    @test reader["x"][Integer] == 123
    @test reader["x"][Any] == 123
end

@testset "bool" begin
    reader = BSONReader(single_field_doc_(BSON_TYPE_BOOL, 0x1))
    @test reader["x"][Bool] == true
    @test reader["x"][Any] == true
    reader = BSONReader(single_field_doc_(BSON_TYPE_BOOL, 0x0))
    @test reader["x"][Bool] == false
    @test reader["x"][Any] == false
end

@testset "datetime" begin
    t = DateTime(2021, 1, 2, 9, 30)
    v = trunc(Int64, datetime2unix(t) * 1000)
    reader = BSONReader(single_field_doc_(BSON_TYPE_DATETIME, v))
    @test reader["x"][DateTime] == t
    @test reader["x"][Any] == t
end

@testset "timestamp" begin
    x = BSONTimestamp(1, 2)
    reader = BSONReader(single_field_doc_(BSON_TYPE_TIMESTAMP, x))
    @test reader["x"][BSONTimestamp] == x
    @test reader["x"][Any] == x
end

@testset "ObjectId" begin
    x = BSONObjectId((
        0x1, 0x2, 0x3, 0x4,
        0x5, 0x6, 0x7, 0x8,
        0x9, 0xA, 0xB, 0xC,
    ))
    reader = BSONReader(single_field_doc_(BSON_TYPE_OBJECTID, x))
    @test reader["x"][BSONObjectId] == x
    @test reader["x"][Any] == x
end

@testset "string" begin
    x = "test"
    io = IOBuffer()
    write(io, Int32(length(x) + 1))
    write(io, x)
    write(io, 0x0)
    buf = take!(io)
    reader = BSONReader(single_field_doc_(BSON_TYPE_STRING, buf))
    @test reader["x"][String] == x
    @test reader["x"][Any] == x
    reader = BSONReader(single_field_doc_(BSON_TYPE_CODE, buf))
    @test reader["x"][String] == x
    @test reader["x"][Any] == x
end

@testset "binary" begin
    x = rand(UInt8, 10)
    io = IOBuffer()
    write(io, Int32(length(x)))
    write(io, BSON_SUBTYPE_GENERIC)
    write(io, x)
    reader = BSONReader(single_field_doc_(BSON_TYPE_BINARY, take!(io)))
    x2 = reader["x"][BSONBinary]
    @test x2.data == x
    @test x2.subtype == BSON_SUBTYPE_GENERIC
    x2 = reader["x"][UnsafeBSONBinary]
    @test x2.data == x
    @test x2.subtype == BSON_SUBTYPE_GENERIC
    x2 = reader["x"][Any]
    @test x2 isa BSONBinary
    @test x2.data == x
    @test x2.subtype == BSON_SUBTYPE_GENERIC
end

@testset "uuid" begin
    x = uuid4()
    io = IOBuffer()
    write(io, Int32(16))
    write(io, BSON_SUBTYPE_UUID)
    unsafe_write(io, Ref(x), 16)
    reader = BSONReader(single_field_doc_(BSON_TYPE_BINARY, take!(io)))
    @test reader["x"][UUID] == x
    @test reader["x"][Any] == x
end

end