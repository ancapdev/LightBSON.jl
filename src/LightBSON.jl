module LightBSON

using Dates
using DecFP
using Transducers
using UnsafeArrays
using UUIDs

export BSONConversionError
export BSONReader
export BSONTimestamp, BSONObjectId, BSONBinary, UnsafeBSONBinary

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

export BSON_SUBTYPE_GENERIC,
    BSON_SUBTYPE_FUNCTION,
    BSON_SUBTYPE_BINARY_OLD,
    BSON_SUBTYPE_UUID_OLD,
    BSON_SUBTYPE_UUID,
    BSON_SUBTYPE_MD5,
    BSON_SUBTYPE_ENCRYPTED

struct BSONTimestamp
    counter::UInt32
    time::UInt32
end

struct BSONObjectId
    data::NTuple{12, UInt8}
end

struct BSONBinary
    data::Vector{UInt8}
    subtype::UInt8
end

struct UnsafeBSONBinary
    data::UnsafeArray{UInt8, 1}
    subtype::UInt8
end

include("type.jl")
include("exceptions.jl")
include("reader.jl")

end
