using FixedPointDecimals

@testset "FixedDecimal" begin

@testset "FixedDecimal{Int64, $f} roundtrip" for (f, v) in [(0, 125), (2, 1.25), (4, 1.25)]
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    x = FixedDecimal{Int64, f}(v)
    writer["x"] = x
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][Dec128] == Dec128(x.i, -f)
    @test BSONReader(buf, StrictBSONValidator())["x"][FixedDecimal{Int64, f}] == x
end

@testset "FixedDecimal precise conversion" begin
    x = FixedDecimal{Int64, 2}(1.23)
    @test Dec128(x.i, -2) == d128"1.23"
    buf = empty!(fill(0xff, 1000))
    writer = BSONWriter(buf)
    writer["x"] = x
    close(writer)
    @test BSONReader(buf, StrictBSONValidator())["x"][Dec128] == d128"1.23"
    @test BSONReader(buf, StrictBSONValidator())["x"][FixedDecimal{Int64, 2}] == x
end

end
