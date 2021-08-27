corpus_dir = joinpath(@__DIR__, "corpus", "tests")
corpus_files = filter(x -> splitext(x)[2] == ".json", readdir(corpus_dir))

@testset "corpus" begin

@testset "roundtrip $(splitext(file)[1])" for file in corpus_files
    doc = JSON3.read(read(joinpath(corpus_dir, file)))
    t = parse(UInt8, doc["bson_type"])
    if haskey(doc, "valid")
        @testset """roundtrip $file $(test_case["description"])""" for test_case in doc["valid"]
            src = hex2bytes(test_case["canonical_bson"])
            x = BSONReader(src)[Any]
            dst = UInt8[]
            writer = BSONWriter(dst)
            writer[] = x
            close(writer)
            @test dst == src
        end
    end
end

end