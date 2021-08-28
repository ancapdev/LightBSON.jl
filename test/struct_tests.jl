struct SuperSimple
    x::Int64
    y::Float64
end

LightBSON.bson_supersimple(::Type{SuperSimple}) = true

struct NestedSimple
    x::Int64
end

LightBSON.bson_supersimple(::Type{NestedSimple}) = true

struct Simple
    x::String
    y::NestedSimple
end

LightBSON.bson_simple(::Type{Simple}) = true

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

@testset "supersimple" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = SuperSimple(123, 1.25)
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[SuperSimple] == x
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

end