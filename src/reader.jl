# TODO: endian conversion on big-endian arch
# TODO: wrapper types for datetime (to preserve precision and avoid conversion overhead) and timestamp values
struct BSONReader{S <: DenseVector{UInt8}}
    src::S
    offset::Int
    type::UInt8
end

BSONReader(src::DenseVector{UInt8}) = BSONReader(src, 0, BSON_TYPE_DOCUMENT)

const TYPE_SIZE_TABLE = fill(-1, 256)
TYPE_SIZE_TABLE[BSON_TYPE_DOUBLE] = 8
TYPE_SIZE_TABLE[BSON_TYPE_DATETIME] = 8
TYPE_SIZE_TABLE[BSON_TYPE_INT64] = 8
TYPE_SIZE_TABLE[BSON_TYPE_TIMESTAMP] = 8
TYPE_SIZE_TABLE[BSON_TYPE_INT32] = 4
TYPE_SIZE_TABLE[BSON_TYPE_BOOL] = 1
TYPE_SIZE_TABLE[BSON_TYPE_NULL] = 0
TYPE_SIZE_TABLE[BSON_TYPE_DECIMAL128] = 16
TYPE_SIZE_TABLE[BSON_TYPE_OBJECTID] = 12

function element_size_variable_(t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_DOCUMENT || t == BSON_TYPE_ARRAY
        Int(unsafe_load(Ptr{Int32}(p)))
    elseif t == BSON_TYPE_STRING || t == BSON_TYPE_CODE
        Int(unsafe_load(Ptr{Int32}(p))) + 4
    elseif t == BSON_TYPE_BINARY
        Int(unsafe_load(Ptr{Int32}(p))) + 5
    elseif t == BSON_TYPE_REGEX
        len1 = unsafe_trunc(Int, ccall(:strlen, Csize_t, (Cstring,), p)) + 1
        len2 = unsafe_trunc(Int, ccall(:strlen, Csize_t, (Cstring,), p + len1)) + 1
        len1 + len2
    else
        error("Unsupported BSON type $t")
    end
end

@inline function element_size_(t::UInt8, p::Ptr{UInt8})
    @inbounds s = TYPE_SIZE_TABLE[t]
    s >= 0 ? s : element_size_variable_(t, p)
end

"""
    name_len_and_match_(field, target)

Compare field name and target name, and calculate length of field name (including null terminator)

Returns (length(field)), field == target)

Performs byte wise comparison, optimized for short length field names
"""
@inline function name_len_and_match_(field::Ptr{UInt8}, target::Ptr{UInt8})
    len = 1
    cmp_acc = 0x0
    while true
        c = unsafe_load(field, len)
        c2 = unsafe_load(target, len)
        cmp_acc |= xor(c, c2)
        c == 0x0 && return (len, cmp_acc == 0)
        len += 1
        c2 == 0x0 && break
    end
    while true
        c = unsafe_load(field, len)
        c == 0x0 && break
        len += 1
    end
    (len, false)
end

function Base.getindex(reader::BSONReader, target::Union{AbstractString, Symbol})
    reader.type == BSON_TYPE_DOCUMENT || reader.type == BSON_TYPE_ARRAY || throw(
        ArgumentError("Field access only available on documents and arrays")
    )
    src = reader.src
    GC.@preserve src target begin
        target_p = Base.unsafe_convert(Ptr{UInt8}, target)
        p = pointer(reader.src)
        offset = reader.offset
        doc_len = Int(unsafe_load(Ptr{Int32}(p + offset)))
        doc_end = offset + doc_len - 1
        offset += 4
        while offset < doc_end
            el_type = unsafe_load(p, offset + 1)
            name_p = p + offset + 1
            name_len, name_match = name_len_and_match_(name_p, target_p)
            value_len = element_size_(el_type, name_p + name_len)
            name_match && return BSONReader(reader.src, offset + name_len + 1, el_type)
            offset += 1 + name_len + value_len
        end
    end
    throw(KeyError(target))
end

function Transducers.__foldl__(rf, val, reader::BSONReader)
    reader.type == BSON_TYPE_DOCUMENT || reader.type == BSON_TYPE_ARRAY || throw(
        ArgumentError("Field access only available on documents and arrays")
    )
    src = reader.src
    GC.@preserve src begin
        p = pointer(reader.src)
        offset = reader.offset
        doc_len = Int(unsafe_load(Ptr{Int32}(p + offset)))
        doc_end = offset + doc_len - 1
        offset += 4
        while offset < doc_end
            el_type = unsafe_load(p, offset + 1)
            name_p = p + offset + 1
            name_len = unsafe_trunc(Int, ccall(:strlen, Csize_t, (Cstring,), name_p)) + 1
            value_len = element_size_(el_type, name_p + name_len)
            field_reader = BSONReader(reader.src, offset + name_len + 1, el_type)
            val = Transducers.@next(rf, val, (name_p, name_len - 1, field_reader))
            offset += 1 + name_len + value_len
        end
        Transducers.complete(rf, val)
    end
end

@inline function try_load_field_(::Type{Int64}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_INT64 && return unsafe_load(Ptr{Int64}(p))
    t == BSON_TYPE_INT32 && return Int64(unsafe_load(Ptr{Int32}(p)))
    nothing
end

@inline function try_load_field_(::Type{Int32}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_INT32 ? unsafe_load(Ptr{Int32}(p)) : nothing
end

@inline function try_load_field_(::Type{Bool}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_BOOL ? unsafe_load(p) != 0x0 : nothing
end

@inline function try_load_field_(::Type{Float64}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_DOUBLE ? unsafe_load(Ptr{Float64}(p)) : nothing
end

@inline function try_load_field_(::Type{Dec128}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_DECIMAL128 ? unsafe_load(Ptr{Dec128}(p)) : nothing
end

function try_load_field_(::Type{Number}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_DOUBLE
        unsafe_load(Ptr{Float64}(p))
    elseif t == BSON_TYPE_INT64
        unsafe_load(Ptr{Int64}(p))
    elseif t == BSON_TYPE_INT32
        unsafe_load(Ptr{Int32}(p))
    elseif t == BSON_TYPE_DECIMAL128
        unsafe_load(Ptr{Dec128}(p))
    else
        nothing
    end
end

function try_load_field_(::Type{Integer}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_INT64
        unsafe_load(Ptr{Int64}(p))
    elseif t == BSON_TYPE_INT32
        unsafe_load(Ptr{Int32}(p))
    else
        nothing
    end
end

function try_load_field_(::Type{AbstractFloat}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_DOUBLE
        unsafe_load(Ptr{Float64}(p))
    elseif t == BSON_TYPE_DECIMAL128
        unsafe_load(Ptr{Dec128}(p))
    else
        nothing
    end
end

@inline function try_load_field_(::Type{DateTime}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_DATETIME ? DateTime(Dates.UTM(Dates.UNIXEPOCH + unsafe_load(Ptr{Int64}(p)))) : nothing
end

@inline function try_load_field_(::Type{BSONTimestamp}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_TIMESTAMP ? unsafe_load(Ptr{BSONTimestamp}(p)) : nothing
end

@inline function try_load_field_(::Type{BSONObjectId}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_OBJECTID ? unsafe_load(Ptr{BSONObjectId}(p)) : nothing
end

function try_load_field_(::Type{String}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_STRING || t == BSON_TYPE_CODE
        len = Int(unsafe_load(Ptr{Int32}(p)))
        unsafe_string(p + 4, len - 1)
    else
        nothing
    end
end

function Base.getindex(reader::BSONReader, ::Type{T}) where T
    src = reader.src
    GC.@preserve src begin
        x = try_load_field_(T, reader.type, pointer(src) + reader.offset)
        x === nothing && throw(BSONConversionError(reader.type, T))
        x
    end
end

function Base.getindex(reader::BSONReader, ::Type{Dict{String, Any}})
    foldxl(reader; init = Dict{String, Any}()) do state, (name_p, name_len, field_reader)
        state[unsafe_string(name_p, name_len)] = field_reader[Any]
        state
    end
end

function Base.getindex(reader::BSONReader, ::Type{Any})
    if reader.type == BSON_TYPE_DOUBLE
        reader[Float64]
    elseif reader.type == BSON_TYPE_STRING
        reader[String]
    elseif reader.type == BSON_TYPE_DOCUMENT
        reader[Dict{String, Any}]
    elseif reader.type == BSON_TYPE_ARRAY
        reader[Vector{Any}]
    elseif reader.type == BSON_TYPE_BINARY
        reader[Vector{UInt8}]
    elseif reader.type == BSON_TYPE_OBJECTID
        error("not implemented")
    elseif reader.type == BSON_TYPE_BOOL
        reader[Bool]
    elseif reader.type == BSON_TYPE_DATETIME
        reader[DateTime]
    elseif reader.type == BSON_TYPE_NULL
        nothing
    elseif reader.type == BSON_TYPE_REGEX
        error("not implemented")
    elseif reader.type == BSON_TYPE_DB_POINTER
        error("not implemented")
    elseif reader.type == BSON_TYPE_CODE
        reader[String]
    elseif reader.type == BSON_TYPE_INT32
        reader[Int32]
    elseif reader.type == BSON_TYPE_TIMESTAMP
        reader[BSONTimeStamp]
    elseif reader.type == BSON_TYPE_INT64
        reader[Int64]
    elseif reader.type == BSON_TYPE_DECIMAL128
        error("not implemented")
    else
        error("Unsupported BSON type $(reader.type)")
    end
end
