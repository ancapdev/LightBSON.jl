module LightBSON

using DataStructures
using Dates
using DecFP
using FNVHash
using Sockets
using StructTypes
using Transducers
using UnsafeArrays
using UUIDs
using WeakRefStrings

export BSONConversionError
export AbstractBSONReader, BSONReader, BSONWriter, BSONWriteBuffer
export BSONValidator, StrictBSONValidator, LightBSONValidator, UncheckedBSONValidator
export BSONConversionRules, DefaultBSONConversions, NumericBSONConversions
export BSONIndex, IndexedBSONReader
export BSONObjectId, BSONObjectIdGenerator
export BSONTimestamp
export BSONCode, BSONCodeWithScope, BSONSymbol
export BSONBinary, UnsafeBSONBinary
export BSONRegex, UnsafeBSONString
export BSONMinKey, BSONMaxKey
export BSONUndefined
export BSONUUIDOld
export BSONDBPointer

export BSON_TYPE_DOUBLE,
    BSON_TYPE_STRING,
    BSON_TYPE_DOCUMENT,
    BSON_TYPE_ARRAY,
    BSON_TYPE_BINARY,
    BSON_TYPE_UNDEFINED,
    BSON_TYPE_OBJECTID,
    BSON_TYPE_BOOL,
    BSON_TYPE_DATETIME,
    BSON_TYPE_NULL,
    BSON_TYPE_REGEX,
    BSON_TYPE_DB_POINTER,
    BSON_TYPE_CODE,
    BSON_TYPE_SYMBOL,
    BSON_TYPE_CODE_WITH_SCOPE,
    BSON_TYPE_INT32,
    BSON_TYPE_TIMESTAMP,
    BSON_TYPE_INT64,
    BSON_TYPE_DECIMAL128

export BSON_SUBTYPE_GENERIC_BINARY,
    BSON_SUBTYPE_FUNCTION,
    BSON_SUBTYPE_BINARY_OLD,
    BSON_SUBTYPE_UUID_OLD,
    BSON_SUBTYPE_UUID,
    BSON_SUBTYPE_MD5,
    BSON_SUBTYPE_ENCRYPTED

export bson_simple
export bson_read, bson_read_simple, bson_read_structtype, bson_read_unversioned, bson_read_versioned
export bson_write, bson_write_simple, bson_write_structtype
export bson_schema_version, bson_schema_version_field
export bson_object_id_range

bson_schema_version(::Type{T}) where T = nothing

bson_schema_version_field(::Type{T}) where T = "_v"

# bson_simple(::Type{T}) where T = StructTypes.StructType(T) == StructTypes.NoStructType()
# bson_simple(::Type{<:NamedTuple}) = true
bson_simple(::Type{T}) where T = true

include("object_id.jl")
include("types.jl")
include("representations.jl")
include("exceptions.jl")
include("validator.jl")
include("reader.jl")
include("index.jl")
include("indexed_reader.jl")
include("writer.jl")
include("write_buffer.jl")
include("convenience.jl")
include("fileio.jl")

function __init__()
    # Ensure object IDs start at a random point on each run
    # Without this the random starting point is burned in at precompile time
    global default_object_id_generator = BSONObjectIdGenerator()
end

end
