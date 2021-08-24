struct BSONWriter
    dst::Vector{UInt8}
    offset::Int

    function BSONWriter(dst::Vector{UInt8})
        offset = length(dst)
        resize!(dst, offset + 4)
        new(dst, offset)
    end
end

function Base.close(writer::BSONWriter)
    dst = writer.dst
    push!(dst, 0x0)
    p = pointer(dst) + writer.offset
    GC.@preserve dst unsafe_store!(Ptr{Int32}(p), length(dst) - writer.offset)
    nothing
end

bson_type_(::Type{Float64}) = BSON_TYPE_DOUBLE
bson_type_(::Type{Int64}) = BSON_TYPE_INT64
bson_type_(::Type{Int32}) = BSON_TYPE_INT32
bson_type_(::Type{Bool}) = BSON_TYPE_BOOL
bson_type_(::Type{Dec128}) = BSON_TYPE_DECIMAL128
bson_type_(::Type{UUID}) = BSON_TYPE_BINARY
bson_type_(::Type{DateTime}) = BSON_TYPE_DATETIME
bson_type_(::Type{Nothing}) = BSON_TYPE_NULL
bson_type_(::Type{String}) = BSON_TYPE_STRING
bson_type_(::Type{BSONTimestamp}) = BSON_TYPE_TIMESTAMP
bson_type_(::Type{BSONBinary}) = BSON_TYPE_BINARY

wire_value_(x) = htol(x)
wire_value_(x::Bool) = UInt8(x)
wire_value_(x::DateTime) = htol(Dates.value(x) - Dates.UNIXEPOCH)
wire_value_(x::BSONTimestamp) = htol(UInt64(x.counter) | (UInt64(x.time) << 32))
wire_value_(x::BSONObjectId) = x

function Base.setindex!(
    writer::BSONWriter, value::T, name::String
) where T <: Union{
    Float64,
    Int64,
    Int32,
    Bool,
    DateTime,
    Dec128,
    #UUID, -- needs to be written as binary with subtype uuid
    BSONTimestamp,
    BSONObjectId,
    #Nothing, -- needs to write a zero length value
}
    dst = writer.dst
    offset = length(dst)
    name_len = sizeof(name)
    wvalue = wire_value_(value)
    resize!(dst, offset + 2 + name_len + sizeof(wvalue))
    GC.@preserve dst name begin
        p = pointer(dst) + offset
        unsafe_store!(p, bson_type_(T))
        unsafe_copyto!(p + 1, pointer(name), name_len)
        unsafe_store!(p + 1 + name_len, 0x0)
        unsafe_store!(Ptr{typeof(wvalue)}(p + 2 + name_len), wvalue)
    end
    nothing
end