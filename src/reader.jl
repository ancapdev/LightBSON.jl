abstract type AbstractBSONReader end

struct BSONReader{S <: DenseVector{UInt8}} <: AbstractBSONReader
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
        Int(ltoh(unsafe_load(Ptr{Int32}(p))))
    elseif t == BSON_TYPE_STRING || t == BSON_TYPE_CODE
        Int(ltoh(unsafe_load(Ptr{Int32}(p)))) + 4
    elseif t == BSON_TYPE_BINARY
        Int(ltoh(unsafe_load(Ptr{Int32}(p)))) + 5
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

@inline function name_len_(field::Ptr{UInt8})
    len = 1
    while true
        unsafe_load(field, len) == 0x0 && break
        len += 1
    end
    len
end

@inline function Transducers.__foldl__(rf, val, reader::BSONReader)
    reader.type == BSON_TYPE_DOCUMENT || reader.type == BSON_TYPE_ARRAY || throw(
        ArgumentError("Field access only available on documents and arrays")
    )
    src = reader.src
    GC.@preserve src begin
        p = pointer(reader.src)
        offset = reader.offset
        doc_len = Int(ltoh(unsafe_load(Ptr{Int32}(p + offset))))
        doc_end = offset + doc_len - 1
        doc_end > sizeof(src) && error("Invalid document")
        offset += 4
        while offset < doc_end
            el_type = unsafe_load(p, offset + 1)
            name_p = p + offset + 1
            name_len = name_len_(name_p)
            value_len = element_size_(el_type, name_p + name_len)
            field_reader = BSONReader(src, offset + name_len + 1, el_type)
            val = Transducers.@next(rf, val, UnsafeBSONString(name_p, name_len - 1) => field_reader)
            offset += 1 + name_len + value_len
        end
        Transducers.complete(rf, val)
    end
end

@inline function Base.foreach(f, reader::BSONReader)
    foreach(f, Map(identity), reader)
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
        doc_len = Int(ltoh(unsafe_load(Ptr{Int32}(p + offset))))
        doc_end = offset + doc_len - 1
        doc_end > sizeof(src) && error("Invalid document")
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

function Base.getindex(reader::BSONReader, i::Integer)
    i < 1 && throw(BoundsError(reader, i))
    el = foldl((_, x) -> reduced(x.second), Drop(i - 1), reader; init = nothing)
    el === nothing && throw(BoundsError(reader, i))
    el
end

@inline function try_load_field_(::Type{Int64}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_INT64 && return ltoh(unsafe_load(Ptr{Int64}(p)))
    t == BSON_TYPE_INT32 && return Int64(ltoh(unsafe_load(Ptr{Int32}(p))))
    nothing
end

@inline function try_load_field_(::Type{Int32}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_INT32 ? ltoh(unsafe_load(Ptr{Int32}(p))) : nothing
end

@inline function try_load_field_(::Type{Bool}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_BOOL ? unsafe_load(p) != 0x0 : nothing
end

@inline function try_load_field_(::Type{Float64}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_DOUBLE ? ltoh(unsafe_load(Ptr{Float64}(p))) : nothing
end

@inline function try_load_field_(::Type{Dec128}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_DECIMAL128 ? ltoh(unsafe_load(Ptr{Dec128}(p))) : nothing
end

@inline function try_load_field_(::Type{DateTime}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_DATETIME ? DateTime(Dates.UTM(Dates.UNIXEPOCH + ltoh(unsafe_load(Ptr{Int64}(p))))) : nothing
end

@inline function try_load_field_(::Type{BSONTimestamp}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_TIMESTAMP ? BSONTimestamp(ltoh(unsafe_load(Ptr{UInt64}(p)))) : nothing
end

@inline function try_load_field_(::Type{BSONObjectId}, t::UInt8, p::Ptr{UInt8})
    t == BSON_TYPE_OBJECTID ? unsafe_load(Ptr{BSONObjectId}(p)) : nothing
end

function try_load_field_(::Type{BSONBinary}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_BINARY
        len = ltoh(unsafe_load(Ptr{Int32}(p)))
        subtype = unsafe_load(p + 4)
        dst = Vector{UInt8}(undef, len)
        GC.@preserve dst unsafe_copyto!(pointer(dst), p + 5, len)
        BSONBinary(dst, subtype)
    else
        nothing
    end
end

function try_load_field_(::Type{UnsafeBSONBinary}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_BINARY
        len = ltoh(unsafe_load(Ptr{Int32}(p)))
        UnsafeBSONBinary(
            UnsafeArray(p + 5, (Int(len),)),
            unsafe_load(p + 4)
        )
    else
        nothing
    end
end

function try_load_field_(::Type{UUID}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_BINARY
        subtype = unsafe_load(p + 4)
        if subtype == BSON_SUBTYPE_UUID || subtype == BSON_SUBTYPE_UUID_OLD
            len = ltoh(unsafe_load(Ptr{Int32}(p)))
            len != 16 && error("Unexpected UUID length $len")
            return unsafe_load(Ptr{UUID}(p + 5))
        end
    end
    nothing
end

function try_load_field_(::Type{String}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_STRING || t == BSON_TYPE_CODE
        len = Int(ltoh(unsafe_load(Ptr{Int32}(p))))
        unsafe_string(p + 4, len - 1)
    else
        nothing
    end
end

@inline function try_load_field_(::Type{UnsafeBSONString}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_STRING || t == BSON_TYPE_CODE
        len = Int(ltoh(unsafe_load(Ptr{Int32}(p))))
        UnsafeBSONString(p + 4, len - 1)
    else
        nothing
    end
end

function try_load_field_(::Type{BSONCode}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_CODE
        len = Int(ltoh(unsafe_load(Ptr{Int32}(p))))
        BSONCode(unsafe_string(p + 4, len - 1))
    else
        nothing
    end
end

function try_load_field_(::Type{BSONRegex}, t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_REGEX
        len1 = unsafe_trunc(Int, ccall(:strlen, Csize_t, (Cstring,), p))
        BSONRegex(
            unsafe_string(p, len1),
            unsafe_string(p + len1 + 1)
        )
    else
        nothing
    end
end

@inline function Base.getindex(reader::BSONReader, ::Type{T}) where T <: ValueField
    src = reader.src
    GC.@preserve src begin
        x = try_load_field_(T, reader.type, pointer(src) + reader.offset)
        x === nothing && throw(BSONConversionError(reader.type, T))
        x
    end
end

function Base.getindex(reader::AbstractBSONReader, ::Type{Number})
    t = reader.type
    if t == BSON_TYPE_DOUBLE
        reader[Float64]
    elseif t == BSON_TYPE_INT64
        reader[Int64]
    elseif t == BSON_TYPE_INT32
        reader[Int32]
    elseif t == BSON_TYPE_DECIMAL128
        reader[Dec128]
    else
        throw(BSONConversionError(t, Number))
    end
end

function Base.getindex(reader::AbstractBSONReader, ::Type{Integer})
    t = reader.type
    if t == BSON_TYPE_INT64
        reader[Int64]
    elseif t == BSON_TYPE_INT32
        reader[Int32]
    else
        throw(BSONConversionError(t, Number))
    end
end

function Base.getindex(reader::AbstractBSONReader, ::Type{AbstractFloat})
    t = reader.type
    if t == BSON_TYPE_DOUBLE
        reader[Float64]
    elseif t == BSON_TYPE_DECIMAL128
        reader[Dec128]
    else
        throw(BSONConversionError(t, Number))
    end
end

@inline function Base.getindex(reader::AbstractBSONReader, ::Type{Tuple{Nothing, T}}) where T
    reader.type == BSON_TYPE_NULL ? nothing : reader[T] 
end

function Base.getindex(reader::AbstractBSONReader, ::Type{Dict{String, Any}})
    foldxl(reader; init = Dict{String, Any}()) do state, x
        state[String(x.first)] = x.second[Any]
        state
    end
end

function Base.getindex(reader::AbstractBSONReader, ::Type{Vector{T}}) where T
    dst = T[]
    copy!(dst, reader)
end

function Base.copy!(dst::AbstractArray{T}, reader::AbstractBSONReader) where T
    copy!(Map(x -> x.second[T]), dst, reader)
end

function Base.getindex(reader::AbstractBSONReader, ::Type{Any})
    if reader.type == BSON_TYPE_DOUBLE
        reader[Float64]
    elseif reader.type == BSON_TYPE_STRING
        reader[String]
    elseif reader.type == BSON_TYPE_DOCUMENT
        reader[Dict{String, Any}]
    elseif reader.type == BSON_TYPE_ARRAY
        reader[Vector{Any}]
    elseif reader.type == BSON_TYPE_BINARY
        x = reader[BSONBinary]
        data = x.data
        if x.subtype == BSON_SUBTYPE_UUID || x.subtype == BSON_SUBTYPE_UUID_OLD && length(data) == 16
            GC.@preserve data unsafe_load(Ptr{UUID}(pointer(data)))
        else
            x
        end
    elseif reader.type == BSON_TYPE_OBJECTID
        reader[BSONObjectId]
    elseif reader.type == BSON_TYPE_BOOL
        reader[Bool]
    elseif reader.type == BSON_TYPE_DATETIME
        reader[DateTime]
    elseif reader.type == BSON_TYPE_NULL
        nothing
    elseif reader.type == BSON_TYPE_REGEX
        reader[BSONRegex]
    elseif reader.type == BSON_TYPE_CODE
        reader[BSONCode]
    elseif reader.type == BSON_TYPE_INT32
        reader[Int32]
    elseif reader.type == BSON_TYPE_TIMESTAMP
        reader[BSONTimestamp]
    elseif reader.type == BSON_TYPE_INT64
        reader[Int64]
    elseif reader.type == BSON_TYPE_DECIMAL128
        reader[Dec128]
    else
        error("Unsupported BSON type $(reader.type)")
    end
end

@inline @generated function bson_read_simple(::Type{T}, reader::AbstractBSONReader) where T
    field_readers = map(zip(fieldnames(T), fieldtypes(T))) do (fn, ft)
        fns = string(fn)
        :(reader[$fns][$ft])
    end
    :($T($(field_readers...)))
end

@inline function bson_read_structtype(::Type{T}, reader::AbstractBSONReader) where T
    StructTypes.construct((i, name, FT) -> reader[name][FT], T)
end

@inline function bson_read(::Type{T}, reader::AbstractBSONReader) where T
    v = bson_schema_version(T)
    if v !== nothing
        read_v = reader["_v"][typeof(v)]
        read_v != v && error("Mismatched schema version, read: $(read_v), target: $v")
    end
    if bons_supersimple(T) || bson_simple(T)
        bson_read_simple(T, reader)
    else
        bson_read_structtype(T, reader)
    end
end

@inline function Base.getindex(reader::AbstractBSONReader, ::Type{T}) where T
    bson_read(T, reader)
end