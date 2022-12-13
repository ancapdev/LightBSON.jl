struct NestedSimple
    x::Int64
end

struct Simple
    x::String
    y::NestedSimple
end

struct WithOptional
    x::Union{Nothing, Int64}
end

struct StructType
    x::Int64
    y::Float64
end

StructTypes.StructType(::Type{StructType}) = StructTypes.Struct()

struct Evolved1
    x::Int64
end

LightBSON.bson_schema_version(::Type{Evolved1}) = Int32(1)

struct Evolved2
    x::Int64
    y::Int64
end

Evolved2(x::Evolved1) = Evolved2(x.x, 0)

LightBSON.bson_schema_version(::Type{Evolved2}) = Int32(2)

struct Evolved3
    x::Int64
    y::Float64
end

Evolved3(x::Evolved2) = Evolved3(x.x, x.y)

LightBSON.bson_schema_version(::Type{Evolved3}) = Int32(3)

function LightBSON.bson_read_versioned(::Type{Evolved3}, v::Int32, reader::AbstractBSONReader)
    if v == 1
        Evolved3(Evolved2(bson_read_unversioned(Evolved1, reader)))
    elseif v == 2
        Evolved3(bson_read_unversioned(Evolved2, reader))
    elseif v == 3
        bson_read_unversioned(Evolved3, reader)
    else
        error("Unsupported schema version $v")
    end
end

struct Evolved4
    y::Float64
end

LightBSON.bson_schema_version(::Type{Evolved4}) = Int32(4)

const Evolved = Evolved3

@testset "struct" begin

@testset "simple" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = Simple("test", NestedSimple(123))
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[Simple] == x
end

@testset "optional empty" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = WithOptional(nothing)
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[WithOptional] == x
end

@testset "optional set" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = WithOptional(123)
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[WithOptional] == x
end

@testset "StructType" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = StructType(123, 1.25)
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[StructType] == x
end

@testset "evolved prev" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer[] = Evolved2(123, 456)
    close(writer)
    reader = BSONReader(buf)
    @test reader[Evolved] == Evolved3(123, 456)
end

@testset "evolved prev prev" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer[] = Evolved1(123)
    close(writer)
    reader = BSONReader(buf)
    @test reader[Evolved] == Evolved3(123, 0)
end

@testset "evolved current" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer[] = Evolved3(123, 1.25)
    close(writer)
    reader = BSONReader(buf)
    @test reader[Evolved] == Evolved3(123, 1.25)
end

@testset "evolved next" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    writer[] = Evolved4(1.25)
    close(writer)
    reader = BSONReader(buf)
    @test_throws ErrorException reader[Evolved]
end

@testset "NamedTuple" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = (; x = 123, y = 456, z = (; a = 1.25, b = "test"))
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[typeof(x)] == x
end

struct Parametric{T}
    type_encoding::Int
    payload::T
end

@testset "AbstractBSONReader" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = (; type_encoding = 1, payload = "test")
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    p = reader[Parametric{AbstractBSONReader}]
    @test p.type_encoding == 1 
    @test p.payload isa AbstractBSONReader
    p.payload[String] == "test"

    p = reader[Parametric{typeof(reader)}]
    @test p.type_encoding == 1 
    @test p.payload isa AbstractBSONReader
    p.payload[String] == "test"
end

end