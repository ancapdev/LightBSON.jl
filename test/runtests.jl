using Dates
using DecFP
using LightBSON
using Test
using UUIDs

@testset "LightBSON.jl" begin
    include("reader_tests.jl")
    include("index_tests.jl")
    include("indexed_reader_tests.jl")
    include("write_buffer_tests.jl")
    include("writer_tests.jl")
    include("struct_tests.jl")
end
