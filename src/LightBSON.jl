module LightBSON

using Dates
using DecFP
using Transducers

export BSONConversionError
export BSONReader
export BSONTimestamp, BSONObjectId

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

struct BSONTimestamp
    counter::UInt32
    time::UInt32
end

struct BSONObjectId
    data::NTuple{12, UInt8}
end

include("type.jl")
include("exceptions.jl")
include("reader.jl")

end
