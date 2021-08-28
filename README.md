# LightBSON

[![Build Status](https://github.com/ancapdev/LightBSON.jl/workflows/CI/badge.svg)](https://github.com/ancapdev/LightBSON.jl/actions)
[![codecov](https://codecov.io/gh/ancapdev/LightBSON.jl/branch/master/graph/badge.svg?token=9IEAWVLPCN)](https://codecov.io/gh/ancapdev/LightBSON.jl)

High performance encoding and decoding of [BSON](https://bsonspec.org/) data.

## What It Is
* Allocation free API for reading and writing BSON data.
* Natural mapping of Julia types to corresponding BSON types.
* Convenience API to read and write `Dict{String, Any}` as BSON.
* Struct API tunable for tradeoffs between flexibility, performance, and evolution.
* Configurable validation levels.
* Light weight indexing for larger documents.
* Tested for conformance against the [BSON corpus](https://github.com/mongodb/specifications/blob/master/source/bson-corpus/bson-corpus.rst).

## What It Is Not
* Generic serialization of all Julia types to BSON. See [BSON.jl](https://github.com/JuliaIO/BSON.jl). `LightBSON` aims for natural representations, suitable for interop with other languages and long term persistence.
* Integrated with [FileIO.jl](https://github.com/JuliaIO/FileIO.jl). [BSON.jl](https://github.com/JuliaIO/BSON.jl) already is, and adding another with different semantics would be confusing.
* Conversion to and from [Extended JSON](https://docs.mongodb.com/manual/reference/mongodb-extended-json/). This may be added later.

## Reading
### Indexing
### Validation
## Writing
### Faster Buffer
## Structs
### Generic
### Simple
### Super Simple
### Schema Evolution
## Named Tuples
## Performance
## Related Packages
* [BSON.jl](https://github.com/JuliaIO/BSON.jl) - Generic serialization of all Julia types to and from BSON.
* [Mongoc.jl](https://github.com/felipenoris/Mongoc.jl) - Julia MongoDB client.
