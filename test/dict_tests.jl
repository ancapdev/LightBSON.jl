@testset "dict" begin

@testset "string -> any" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = Dict{String, Any}("a" => 1, "b" => "b")
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[Dict{String, Any}] == x
end

@testset "string -> int" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = Dict{String, Int32}("a" => 1, "b" => 2)
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[Dict{String, Int32}] == x
end

@testset "symbol -> any" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = Dict{Symbol, Any}(:a => 1, :b => "b")
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[Dict{Symbol, Any}] == x
end

@testset "symbol -> int" begin
    buf = UInt8[]
    writer = BSONWriter(buf)
    x = Dict{Symbol, Int32}(:a => 1, :b => 2)
    writer[] = x
    close(writer)
    reader = BSONReader(buf)
    @test reader[Dict{Symbol, Int32}] == x
end

end