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
bson_type_(::Type{BSONRegex}) = BSON_TYPE_REGEX
bson_type_(::Type{BSONCode}) = BSON_TYPE_CODE

@inline wire_size_(x) = sizeof(x)
@inline wire_size_(x::Nothing) = 0
@inline wire_size_(x::String) = sizeof(x) + 5
@inline wire_size_(x::BSONCode) = sizeof(x.code) + 5
@inline wire_size_(x::UUID) = 21
@inline wire_size_(x::Union{BSONBinary, BSONUnsafeBinary}) = 5 + sizeof(x.data)
@inline wire_size_(x::BSONRegex) = 2 + sizeof(x.pattern) + sizeof(x.options)

@inline wire_store_(p::Ptr{UInt8}, x::T) where T = unsafe_store!(Ptr{T}(p), htol(x))
@inline wire_store_(::Ptr{UInt8}, ::Nothing) = nothing
@inline wire_store_(p::Ptr{UInt8}, x::Bool) = unsafe_store!(p, UInt8(x))
@inline wire_store_(p::Ptr{UInt8}, x::DateTime) = wire_store_(p, Dates.value(x) - Dates.UNIXEPOCH)
@inline wire_store_(p::Ptr{UInt8}, x::BSONTimestamp) = wire_store_(p, (x.counter % Int64) | ((x.time % Int64) << 32))
@inline wire_store_(p::Ptr{UInt8}, x::BSONObjectId) = unsafe_store!(Ptr{BSONObjectId}(p), x)

@inline function wire_store_(p::Ptr{UInt8}, x::String)
    unsafe_store!(Ptr{Int32}(p), (sizeof(x) + 1) % Int32)
    GC.@preserve x unsafe_copyto!(p + 4, pointer(x), sizeof(x))
    unsafe_store!(p + 5 + sizeof(x), 0x0)
end

@inline wire_store_(p::Ptr{UInt8}, x::BSONCode) = wire_store_(p, x.code)

@inline function wire_store_(p::Ptr{UInt8}, x::UUID)
    unsafe_store!(Ptr{Int32}(p), Int32(16))
    unsafe_store!(p + 4, BSON_SUBTYPE_UUID)
    unsafe_store!(Ptr{UUID}(p + 5), x)
end

@inline function wire_store_(p::Ptr{UInt8}, x::Union{BSONBinary, BSONUnsafeBinary})
    unsafe_store!(Ptr{Int32}(p), sizeof(x.data) % Int32)
    unsafe_store!(p + 4, x.subtype)
    GC.@preserve x unsafe_copyto!(p + 5, pointer(x.data), sizeof(x.data))
end

@inline function wire_store_(p::Ptr{UInt8}, x::BSONRegex)
    GC.@preserve x unsafe_copyto!(p, pointer(x.pattern), sizeof(x.pattern))
    unsafe_store!(p + sizeof(x.pattern), 0x0)
    GC.@preserve x unsafe_copyto!(p + sizeof(x.pattern) + 1, pointer(x.options), sizeof(x.options))
    unsafe_store!(p + sizeof(x.pattern) + sizeof(x.options) + 1 , 0x0)
end

function Base.setindex!(
    writer::BSONWriter, value::T, name::String
) where T <: Union{
    Float64,
    Int64,
    Int32,
    Bool,
    DateTime,
    Dec128,
    UUID,
    String,
    Nothing,
    BSONTimestamp,
    BSONObjectId,
    BSONBinary,
    BSONUnsafeBinary,
    BSONRegex,
    BSONCode
}
    dst = writer.dst
    offset = length(dst)
    name_len = sizeof(name)
    value_len = wire_size_(value)
    resize!(dst, offset + 2 + name_len + value_len)
    GC.@preserve dst name begin
        p = pointer(dst) + offset
        unsafe_store!(p, bson_type_(T))
        unsafe_copyto!(p + 1, pointer(name), name_len)
        unsafe_store!(p + 1 + name_len, 0x0)
        wire_store_(p + 2 + name_len, value)
    end
    nothing
end

function Base.setindex!(writer::BSONWriter, generator::Function, name::String)
    dst = writer.dst
    offset = length(dst)
    name_len = sizeof(name)
    resize!(dst, offset + 2 + name_len)
    GC.@preserve dst name begin
        p = pointer(dst) + offset
        unsafe_store!(p, BSON_TYPE_DOCUMENT)
        unsafe_copyto!(p + 1, pointer(name), name_len)
        unsafe_store!(p + 1 + name_len, 0x0)
        element_writer = BSONWriter(dst)
        generator(element_writer)
        close(element_writer)
    end
    nothing
end

const SMALL_INDEX_STRINGS = [string(i) for i in 0:99]

function Base.setindex!(writer::BSONWriter, values::Union{AbstractVector, Base.Generator}, name::String)
    dst = writer.dst
    offset = length(dst)
    name_len = sizeof(name)
    resize!(dst, offset + 2 + name_len)
    GC.@preserve dst name begin
        p = pointer(dst) + offset
        unsafe_store!(p, BSON_TYPE_ARRAY)
        unsafe_copyto!(p + 1, pointer(name), name_len)
        unsafe_store!(p + 1 + name_len, 0x0)
        element_writer = BSONWriter(dst)
        for (i, x) in enumerate(values)
            is = i <= length(SMALL_INDEX_STRINGS) ? SMALL_INDEX_STRINGS[i] : string(i - 1)
            element_writer[is] = x
        end
        close(element_writer)
    end
    nothing
end