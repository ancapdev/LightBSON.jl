using DataStructures
using Dates
using DecFP
using JSON3
using LightBSON
using Sockets
using StructTypes
using Test
using UUIDs
using UnsafeArrays

struct EmptyStruct end

@testset "LightBSON.jl" begin
    include("reader_tests.jl")
    include("index_tests.jl")
    include("indexed_reader_tests.jl")
    include("write_buffer_tests.jl")
    include("writer_tests.jl")
    include("dict_tests.jl")
    include("struct_tests.jl")
    include("corpus_tests.jl")
    include("object_id_tests.jl")
    include("convenience_tests.jl")
    include("representation_tests.jl")
end
