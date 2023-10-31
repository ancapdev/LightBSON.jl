# LightBSON

[![Build Status](https://github.com/ancapdev/LightBSON.jl/workflows/CI/badge.svg)](https://github.com/ancapdev/LightBSON.jl/actions)
[![codecov](https://codecov.io/gh/ancapdev/LightBSON.jl/branch/master/graph/badge.svg?token=9IEAWVLPCN)](https://codecov.io/gh/ancapdev/LightBSON.jl)

High performance encoding and decoding of [BSON](https://bsonspec.org/) data.

## What It Is
* Allocation free API for reading and writing BSON data.
* Natural mapping of Julia types to corresponding BSON types.
* Convenience API to read and write `Dict{String, Any}` or `LittleDict{String, Any}` (default, for roundtrip consistency) as BSON.
* Struct API tunable for tradeoffs between flexibility, performance, and evolution.
* Configurable validation levels.
* Light weight indexing for larger documents.
* [Transducers.jl](https://github.com/JuliaFolds/Transducers.jl) compatible.
* Tested for conformance against the [BSON corpus](https://github.com/mongodb/specifications/blob/master/source/bson-corpus/bson-corpus.rst).

## What It Is Not
* Generic serialization of all Julia types to BSON. See [BSON.jl](https://github.com/JuliaIO/BSON.jl) for that functionality. [LightBSON.jl](#LightBSON) aims for natural representations, suitable for interop with other languages and long term persistence.
* Integrated with [FileIO.jl](https://github.com/JuliaIO/FileIO.jl). [BSON.jl](https://github.com/JuliaIO/BSON.jl) already is, and adding another with different semantics would be confusing.
* A BSON mutation API. Reading and writing are entirely separate and only complete documents can be written.
* Conversion to and from [Extended JSON](https://docs.mongodb.com/manual/reference/mongodb-extended-json/). This may be added later.

## High Level API
Performance sensitive use cases are the focus of this package, but a high level API is available for where performance is less of a concern. The high level API will also perform optimally when reading simple types without strings, arrays, or other fields that require allocation.
* `bson_read([T=Any], src)` reads `T` from `src` where `src` is either a `DenseVector{UInt8}`, an `IO`
object, or a path to a file.
* `bson_write(dst, x)` writes `x` to `dst` where `x` is a type that maps to fields (dictionary, struct, named tuple), and `dst` is a `DenseVector{UInt8}`, an `IO`, or a path to a file.
* `bson_write(dst, xs...)` writes `xs` to `dst` where `xs` is a list of `Pair{String, T}` mapping names to field values, and `dst` is as above.
```Julia
# Write to a byte buffer and return the buffer
buf = bson_write(UInt8[], :x => Int64(1), :y => Int64(2))
# Read from a byte buffer as a LittleDict{String, Any}
bson_read(buf)
# Read from a byte buffer as a specific type
x = bson_read(@NamedTuple{x::Int64, y::Int64}, buf)
path = joinpath(homedir(), "test.bson")
# Write to a file
bson_write(path, x)
# Read from a file as an LittleDict{String Any}
bson_read(path)
```

## Low Level API
* Documents are read and written to and from byte arrays with [BSONReader](src/reader.jl) and [BSONWriter](src/writer.jl).
* [BSONReader](src/reader.jl) and [BSONWriter](src/writer.jl) are immutable struct types with no state. They can be instantiated without allocation.
* [BSONWriter](src.writer.jl) will append to the destination array. User is responsible for not writing duplicate fields.
* `reader["foo"]` or `reader[:foo]` finds `foo` and returns a new reader pointing to the field.
* `reader[T]` materializes a field to the type `T`.
* `writer["foo"] = x` or `writer[:foo] = x` appends a field with name `foo` and value `x`.
* `close(writer)` finalizes a document (writes the document length and terminating null byte).
* Prefer strings for field names. Symbols in Julia unfortunately do not have a constant time length API.

### Example
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int64(123)
close(writer)
reader = BSONReader(buf)
reader["x"][Int64] # 123
```

### Nested Documents
Nested documents are written by assigning a field with a function that takes a nested writer. Nested fields are read by index.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = nested_writer -> begin
    nested_writer["a"] = 1
    nested_writer["b"] = 2
end
close(writer)
reader = BSONReader(buf)
reader["x"]["a"][Int64] # 1
reader["x"]["b"][Int64] # 2
```

### Arrays
Arrays are written by assigning array values, or by generators. Arrays can be materialized to Julia arrays, or be accessed by index.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int64[1, 2, 3]
writer["y"] = (Int64(x * x) for x in 1:3)
close(writer)
reader = BSONReader(buf)
reader["x"][Vector{Int64}] # [1, 2, 3]
reader["y"][Vector{Int64}] # [1, 4, 9]
reader["x"][2][Int64] # 2
reader["y"][2][Int64] # 4
```

### Dict and Any
Where performance is not a concern, elements can be materialized to dictionaries (recursively) or to the most appropriate Julia type for leaf fields. Dictionaries can also be written directly.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer[] = LittleDict{String, Any}("x" => Int64(1), "y" => "foo")
close(writer)
reader = BSONReader(buf)
reader[Dict{String, Any}] # Dict{String, Any}("x" => 1, "y" => "foo")
reader[LittleDict{String, Any}] # LittleDict{String, Any}("x" => 1, "y" => "foo")
reader[Any] # LittleDict{String, Any}("x" => 1, "y" => "foo")
reader["x"][Any] # 1
reader["y"][Any] # "foo"
```

### Arrays With Nested Documents
Generators can be used to directly write nested documents in arrays.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = (
    nested_writer -> begin
        nested_writer["a"] = Int64(x)
        nested_writer["b"] = Int64(x * x)
    end
    for x in 1:3
)
close(writer)
reader = BSONReader(buf)
reader["x"][Vector{Any}] # Any[LittleDict{String, Any}("a" => 1, "b" => 1), LittleDict{String, Any}("a" => 2, "b" => 4), LittleDict{String, Any}("a" => 3, "b" => 9)]
reader["x"][3]["b"][Int64] # 9
```

### Read Abstract Types
The abstract types `Number`, `Integer`, and `AbstractFloat` can be used to materialize numeric fields to the most appropriate Julia type under the abstract type.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int32(123)
writer["y"] = 1.25
close(writer)
reader = BSONReader(buf)
reader["x"][Number] # 123
reader["x"][Integer] # 123
reader["y"][Number] # 1.25
reader["y"][AbstractFloat] # 1.25
```

### Unsafe String
String fields can be materialized as `WeakRefString{UInt8}`, aliased as `UnsafeBSONString`. This will create a string object with pointers to the underlying buffer without performing any allocations. User must take care of GC safety.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = "foo"
close(writer)
reader = BSONReader(buf)
s = reader["x"][UnsafeBSONString]
GC.@preserve buf s == "foo" # true
```

### Binary
Binary fields are represented with `BSONBinary`.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = BSONBinary([0x1, 0x2, 0x3], BSON_SUBTYPE_GENERIC_BINARY)
close(writer)
reader = BSONReader(buf)
x = reader["x"][BSONBinary]
x.data # [0x1, 0x2, 0x3]
x.subtype # BSON_SUBTYPE_GENERIC_BINARY
```

### Unsafe Binary
Binary fields can be materialized as `UnsafeBSONBinary` for zero alocations, where the `data` field is an `UnsafeArray{UInt8, 1}` with pointers into the underlying buffer. User must take care of GC safety.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = BSONBinary([0x1, 0x2, 0x3], BSON_SUBTYPE_GENERIC_BINARY)
close(writer)
reader = BSONReader(buf)
x = reader["x"][UnsafeBSONBinary]
GC.@preserve buf x.data == [0x1, 0x2, 0x3] # true
x.subtype # BSON_SUBTYPE_GENERIC_BINARY
```

### Iteration
Fields can be iterated with `foreach()` or using the [Transducers.jl](https://github.com/JuliaFolds/Transducers.jl) APIs. Fields are represented as `Pair{UnsafeBSONString, BSONReader}`.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int64(1)
writer["y"] = Int64(2)
writer["z"] = Int64(3)
close(writer)
reader = BSONReader(buf)
reader |> Map(x -> x.second[Int64]) |> sum # 6
foreach(x -> println(x.second[Int64]), reader) # 1\n2\n3\n
```

## Indexing
BSON field access involves a linear scan to find the matching field name. Depending on the size and structure of a document, and the fields being accessed, it migh be preferable to build an index over the fields first, to be re-used on every access.

[BSONIndex](src/index.jl) provides a very light weight partial (collisions evict previous entries) index over a document. It is designed to be re-used from document to document, by means of a constant time reset. [IndexedBSONReader](src/indexed_reader.jl) wraps a reader and an index to accelerate field access in a document. Index misses fall back to the wrapped reader.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int64(1)
writer["y"] = Int64(2)
writer["z"] = Int64(3)
close(writer)
index = BSONIndex(128)
# Index is built when IndexBSONReader is constructed
reader = IndexedBSONReader(index, BSONReader(buf))
reader["z"][Int64] # 3 -- accessed by index

empty!(buf)
writer = BSONWriter(buf)
writer["a"] = Int64(1)
writer["b"] = Int64(2)
writer["c"] = Int64(3)
close(writer)
# Index can be re-used
reader = IndexedBSONReader(index, BSONReader(buf))
reader["b"][Int64] # 2 -- accessed by index
reader["x"] # throws KeyError
```

## Validation
[BSONReader](src/reader.jl) can be configured with a validator to use during the processing of the input document; 3 are provided:
* [StrictBSONValidator](src/validator.jl) - Validates all error cases presented in the [BSON corpus](https://github.com/mongodb/specifications/blob/master/source/bson-corpus/bson-corpus.rst).
* [LightBSONValidator](src/validator.jl) - Validates field lengths against parent scope (document or buffer), to guard against invalid memory access. This is the default validator.
* [UncheckedBSONValidator](src/validator.jl) - Performs no validation.
```Julia
BSONReader(buf, StrictBSONValidator()) # Reader with strict validation
BSONReader(buf, LightBSONValidator())  # Reader with memory protected validation
BSONReader(buf, UncheckedBSONValidator()) # Reader with no validation
```

## Structs
Structs can be automatically translated to and from BSON, provided all their fields can be represented in BSON. Traits functions are used to select the mode of conversion, and these serve as an extension point for user defined types.
* `bson_simple(T)::Bool` - Set this to true if fields to be serialized are given by `fieldnames(T)` and `T` can be constructed by fields in order of declaration. Defaults to `StructTypes.StructType(T) == StructTypes.NoStructType()`.

### Generic
Provided `bson_simple(T)` is false, serialization will use the [StructTypes.jl](https://github.com/JuliaData/StructTypes.jl) API to iterate fields of `T` and to construct `T`. See [StructTypes.jl](https://github.com/JuliaData/StructTypes.jl) for more details.

### Simple
For simple types using the `bson_simple(T)` trait will generate faster serialization code. This needs only be explicitly set if `StructTypes.StructType(T)` is also defined.
```Julia
struct NestedSimple
    a::Int64
    b::Float64
end

struct Simple
    x::String
    y::NestedSimple
end

StructTypes.StructType(::Type{Simple}) = StructTypes.Struct()
LightBSON.bson_simple(::Type{Simple}) = true

buf = UInt8[]
writer = BSONWriter(buf)
writer["simple"] = Simple("foo", NestedSimple(123, 1.25))
close(writer)
reader = BSONReader(buf)
reader["simple"][Simple] # Simple("foo", NestedSimple(123, 1.25))

# Structs can also be written to the root of the document
buf = UInt8[]
writer = BSONWriter(buf)
writer[] = Simple("foo", NestedSimple(123, 1.25))
close(writer)
reader = BSONReader(buf)
reader[Simple] # Simple("foo", NestedSimple(123, 1.25))
```

### Schema Evolution
For long term persistence or long lived APIs, it may be advisable to encode information about schema versions in documents, and implement ways to evolve schemas through time. Specific strategies for schema evolution are beyond the scope of this package to advise or impose, rather extension points are provided for users to implement the mechanisms best fit to their use cases.
* `bson_schema_version(T)` -  The current schema version for `T`, can be any BSON compatible type, or `nothing` if `T` is unversioned. Defaults to `nothing`.
* `bson_schema_version_field(T)` - The field name to use in the BSON document for storing the schema version. Defaults to `"_v"`.
* `bson_read_versioned(T, v, reader)` - Handle version `v` with respect to current version of `T` and read `T` from `reader`. Defaults to error if the schema versions are mismatched, and otherwise read as-if unversioned.

```Julia
struct Evolving1
    x::Int64
end

LightBSON.bson_schema_version(::Type{Evolving1}) = Int32(1)

struct Evolving2
    x::Int64
    y::Float64
end

# Construct from old version, defaulting new fields
Evolving2(old::Evolving1) = Evolving2(old.x, NaN)

LightBSON.bson_schema_version(::Type{Evolving2}) = Int32(2)

function LightBSON.bson_read_versioned(::Type{Evolving2}, v::Int32, reader::AbstractBSONReader)
    if v == 1
        Evolving2(bson_read_unversioned(Evolving1, reader))
    elseif v == 2
        bson_read_unversioned(Evolving2, reader)
    else
        # Real world application may instead want a mechanism to allow forward compatibility,
        # e.g., by encoding breaking vs non-breaking change info in the version
        error("Unsupported schema version $v for Evolving")
    end
end

const Evolving = Evolving2

buf = UInt8[]
writer = BSONWriter(buf)
# Write old version
writer[] = Evolving1(123)
close(writer)
reader = BSONReader(buf)
# Read as new version
reader[Evolving] # Evolving2(123, NaN)
```

## Named Tuples
Named tuples can be read and written like any struct type.
```Julia
buf = UInt8[]
writer = BSONWriter(buf)
writer[] = (; x = "foo", y = 1.25, z = (; a = Int64(123), b = Int64(456)))
close(writer)
reader = BSONReader(buf)
reader[@NamedTuple{x::String, y::Float64, z::@NamedTuple{a::Int64, b::Int64}}] # (x = "foo", y = 1.25, z = (a = 123, b = 456))
```

## Faster Buffer
Since [BSONWriter](src/writer.jl) itself is immutable, it makes frequent calls to resize the underlying array to track the write head position. Unfortunately at present, this is not a well optimized operation in Julia, resolving to C-calls for manipulating the state of the array.

[BSONWriteBuffer](src/write_buffer.jl) wraps a `Vector{UInt8}` to track size purely in Julia and avoid most of these calls. It implements the minimum API necessary for use with [BSONReader](src/reader.jl) and [BSONWriter](src/writer.jl), and is not for use as a general `Array` implementation.
```Julia
buf = BSONWriteBuffer()
writer = BSONWriter(buf)
writer["x"] = Int64(123)
close(writer)
reader = BSONReader(buf)
reader["x"][Int64] # 123
buf.data # Underlying array, may be longer than length(buf)
```

## Performance
Performance naturally will depend very much on the nature of data being processed. The main overarching goal with this package is to enable the highest possible performance where the user requires it and is willing to sacrifice some convenience to achieve their target.

General advice for high performance BSON schema, such as short field names, avoiding long arrays or documents, and using nesting to reduce search complexity, all apply.

For [LightBSON.jl](#LightBSON) specifically, prefer strings over symbols for field names, use unsafe variants rather than allocating strings and buffers where possible, reuse buffers and indexes, use [BSONWriteBuffer](src/write_buffer.jl) rather than plain `Vector{UInt8}`, and enable `bson_simple(T)` for all applicable types.

Here's an example benchmark, reading and writing a named tuple with nesting (run on a Ryzen 5950X).
```Julia
x = (;
    f1 = 1.25,
    f2 = Int64(123),
    f3 = now(UTC),
    f4 = true,
    f5 = Int32(456),
    f6 = d128"1.2",
    f7 = (; x = uuid4(), y = 2.5)
)

@btime begin
    buf = $(UInt8[])
    empty!(buf)
    writer = BSONWriter(buf)
    writer[] = $x
    close(writer)
end # 78.730 ns (0 allocations: 0 bytes)

@btime begin
    buf = $(BSONWriteBuffer())
    empty!(buf)
    writer = BSONWriter(buf)
    writer[] = $x
    close(writer)
end # 58.303 ns (0 allocations: 0 bytes)

buf = UInt8[]
writer = BSONWriter(buf)
writer[] = x
close(writer)
@btime BSONReader($buf)[$(typeof(x))] # 103.825 ns (0 allocations: 0 bytes)
@btime BSONReader($buf, UncheckedBSONValidator())[$(typeof(x))] # 102.549 ns (0 allocations: 0 bytes)
@btime IndexedBSONReader($(BSONIndex(128)), BSONReader($buf))[$(typeof(x))] # 86.876 ns (0 allocations: 0 bytes)
@btime IndexedBSONReader($(BSONIndex(128)), BSONReader($buf, UncheckedBSONValidator()))[$(typeof(x))] # 84.987 ns (0 allocations: 0 bytes)
@btime IndexedBSONReader($(BSONIndex(128)), BSONReader($buf)) # 47.896 ns (0 allocations: 0 bytes)
@btime $(IndexedBSONReader(BSONIndex(128), BSONReader(buf)))[$(typeof(x))] # 41.434 ns (0 allocations: 0 bytes)
```
We can observe [BSONWriteBuffer](src/write_buffer.jl) makes a material difference to write performance, while indexing, in this case, has a reasonable effect on read performance even for this small document. In the final two lines we can see that indexing and reading the indexed document breaks down roughly half/half. Using the unchecked validator has a smaller impact, and must be used with caution.

## ObjectId
[BSONObjectId](src/object_id.jl) implements the BSON ObjectId type in accordance with the [spec](https://github.com/mongodb/specifications/blob/master/source/objectid.rst). New IDs for the process can be generated by construction, or using `bson_object_id_range(n)` for more efficient batch generation.

```Julia
id1 = BSONObjectId()
DateTime(id1) # The UTC timestamp for when id1 was generated, truncated to seconds
id2 = BSONObjectId()
id1 != id2 # true, IDs are unique
collect(bson_object_id_range(5)) # 5 IDs with equal timestamp and different sequence field
```

## Related Packages
* [BSON.jl](https://github.com/JuliaIO/BSON.jl) - Generic serialization of all Julia types to and from BSON.
* [Mongoc.jl](https://github.com/felipenoris/Mongoc.jl) - Julia MongoDB client.
* [DecFP.jl](https://github.com/JuliaMath/DecFP.jl) - Provides the `Dec128` type used for BSON `decimal128` fields.
* [Transducers.jl](https://github.com/JuliaFolds/Transducers.jl) - Data iteration and transformation API.
* [WeakRefStrings.jl](https://github.com/JuliaData/WeakRefStrings.jl) - Pointer based strings.
* [UnsafeArrays.jl](https://github.com/JuliaArrays/UnsafeArrays.jl) - Pointer based arrays.
* [StructTypes.jl](https://github.com/JuliaData/StructTypes.jl) - Serialization traits and utilities for user defined structures.
