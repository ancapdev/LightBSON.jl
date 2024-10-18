abstract type AbstractBSONReader end

struct BSONReader{S <: DenseVector{UInt8}, V <: BSONValidator, C <: BSONConversionRules} <: AbstractBSONReader
    src::S
    offset::Int
    type::UInt8
    validator::V
    conversions::C
end

@inline function BSONReader(
    src::DenseVector{UInt8};
    validator::BSONValidator = LightBSONValidator(),
    conversions::BSONConversionRules = DefaultBSONConversions(),
)
    validate_root(validator, src)
    BSONReader(src, 0, BSON_TYPE_DOCUMENT, validator, conversions)
end

# For back compat
@inline BSONReader(
    src::DenseVector{UInt8},
    validator::BSONValidator,
    conversions::BSONConversionRules
) =  BSONReader(src; validator, conversions)

# For back compat
@inline BSONReader(src::DenseVector{UInt8}, validator::BSONValidator) = BSONReader(
    src; validator
)

# For back compat
@inline BSONReader(src::DenseVector{UInt8}, conversions::BSONConversionRules) = BSONReader(
    src; conversions
)

@inline Base.pointer(reader::BSONReader) = pointer(reader.src) + reader.offset

const TYPE_SIZE_TABLE = fill(-1, 256)
TYPE_SIZE_TABLE[BSON_TYPE_DOUBLE] = 8
TYPE_SIZE_TABLE[BSON_TYPE_DATETIME] = 8
TYPE_SIZE_TABLE[BSON_TYPE_INT64] = 8
TYPE_SIZE_TABLE[BSON_TYPE_TIMESTAMP] = 8
TYPE_SIZE_TABLE[BSON_TYPE_INT32] = 4
TYPE_SIZE_TABLE[BSON_TYPE_BOOL] = 1
TYPE_SIZE_TABLE[BSON_TYPE_NULL] = 0
TYPE_SIZE_TABLE[BSON_TYPE_UNDEFINED] = 0
TYPE_SIZE_TABLE[BSON_TYPE_DECIMAL128] = 16
TYPE_SIZE_TABLE[BSON_TYPE_OBJECTID] = 12
TYPE_SIZE_TABLE[BSON_TYPE_MIN_KEY] = 0
TYPE_SIZE_TABLE[BSON_TYPE_MAX_KEY] = 0

function element_size_variable_(t::UInt8, p::Ptr{UInt8})
    if t == BSON_TYPE_DOCUMENT || t == BSON_TYPE_ARRAY || t == BSON_TYPE_CODE_WITH_SCOPE
        Int(ltoh(unsafe_load(Ptr{Int32}(p))))
    elseif t == BSON_TYPE_STRING || t == BSON_TYPE_CODE || t == BSON_TYPE_SYMBOL
        Int(ltoh(unsafe_load(Ptr{Int32}(p)))) + 4
    elseif t == BSON_TYPE_BINARY
        Int(ltoh(unsafe_load(Ptr{Int32}(p)))) + 5
    elseif t == BSON_TYPE_REGEX
        len1 = unsafe_trunc(Int, ccall(:strlen, Csize_t, (Cstring,), p)) + 1
        len2 = unsafe_trunc(Int, ccall(:strlen, Csize_t, (Cstring,), p + len1)) + 1
        len1 + len2
    elseif t == BSON_TYPE_DB_POINTER
        Int(ltoh(unsafe_load(Ptr{Int32}(p)))) + 16
    else
        error("Unsupported BSON type $t")
    end
end

@inline function element_size_(t::UInt8, p::Ptr{UInt8})
    @inbounds s = TYPE_SIZE_TABLE[t]
    s >= 0 ? s : element_size_variable_(t, p)
end

Base.sizeof(reader::BSONReader) = GC.@preserve reader element_size_(reader.type, pointer(reader))

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
        offset += 4
        while offset < doc_end
            el_type = unsafe_load(p, offset + 1)
            name_p = p + offset + 1
            name_len = name_len_(name_p)
            field_p = name_p + name_len
            value_len = element_size_(el_type, field_p)
            field_start = offset + 1 + name_len
            field_end = field_start + value_len
            validate_field(reader.validator, el_type, field_p, value_len, doc_end - field_start)
            field_reader = BSONReader(src, field_start, el_type, reader.validator, reader.conversions)
            val = Transducers.@next(rf, val, UnsafeBSONString(name_p, name_len - 1) => field_reader)
            offset = field_end
        end
        Transducers.complete(rf, val)
    end
end

@inline function Base.foreach(f, reader::BSONReader)
    foreach(f, Map(identity), reader)
end

@noinline Base.@constprop :none function find_field_(reader::BSONReader, target::String)
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
        offset += 4
        while offset < doc_end
            el_type = unsafe_load(p, offset + 1)
            name_p = p + offset + 1
            name_len, name_match = name_len_and_match_(name_p, target_p)
            field_p = name_p + name_len
            value_len = element_size_(el_type, field_p)
            field_start = offset + 1 + name_len
            field_end = field_start + value_len
            validate_field(reader.validator, el_type, field_p, value_len, doc_end - field_start)
            name_match && return BSONReader(reader.src, field_start, el_type, reader.validator, reader.conversions)
            offset = field_end
        end
    end
    BSONReader(reader.src, 0, BSON_TYPE_NULL, reader.validator, reader.conversions)
end

# @noinline Base.@constprop :none function Base.getindex(reader::BSONReader, target::Union{AbstractString, Symbol})
Base.getindex(reader::BSONReader, target::String) = find_field_(reader, target)

function Base.getindex(reader::BSONReader, i::Integer)
    i < 1 && throw(BoundsError(reader, i))
    el = foldl((_, x) -> reduced(x.second), Drop(i - 1), reader; init = nothing)
    el === nothing && throw(BoundsError(reader, i))
    el
end

@inline load_bits_(::Type{T}, p::Ptr{UInt8}) where T = ltoh(unsafe_load(Ptr{T}(p)))
@inline load_bits_(::Type{BSONTimestamp}, p::Ptr{UInt8}) = BSONTimestamp(load_bits_(UInt64, p))
@inline load_bits_(::Type{BSONObjectId}, p::Ptr{UInt8}) = unsafe_load(Ptr{BSONObjectId}(p))
@inline load_bits_(::Type{DateTime}, p::Ptr{UInt8}) = DateTime(
    Dates.UTM(Dates.UNIXEPOCH + load_bits_(Int64, p))
)

@inline function read_field_(reader::BSONReader, ::Type{T}) where T <: Union{
    Int64,
    Int32,
    Float64,
    Dec128,
    DateTime,
    BSONTimestamp,
    BSONObjectId
}
    reader.type == bson_type_(T) || throw(BSONConversionError(reader.type, T))
    GC.@preserve reader load_bits_(T, pointer(reader))
end

@inline function read_field_(reader::BSONReader, ::Type{Bool})
    reader.type == BSON_TYPE_BOOL || throw(BSONConversionError(reader.type, Bool))
    x = GC.@preserve reader unsafe_load(pointer(reader))
    validate_bool(reader.validator, x)
    x != 0x0
end

@inline function read_binary_(reader::BSONReader)
    GC.@preserve reader begin
        p = pointer(reader)
        len = load_bits_(Int32, p)
        subtype = unsafe_load(p + 4)
        validate_binary_subtype(reader.validator, p, len, subtype)
        UnsafeBSONBinary(
            UnsafeArray(p + 5, (Int(len),)),
            subtype
        )
    end
end

@inline function read_field_(reader::BSONReader, ::Type{UnsafeBSONBinary})
    reader.type == BSON_TYPE_BINARY || throw(BSONConversionError(reader.type, UnsafeBSONBinary))
    read_binary_(reader)
end

function read_field_(reader::BSONReader, ::Type{BSONBinary})
    reader.type == BSON_TYPE_BINARY || throw(BSONConversionError(reader.type, BSONBinary))
    x = read_binary_(reader)
    GC.@preserve reader BSONBinary(copy(x.data), x.subtype)
end

@inline function read_field_(reader::BSONReader, ::Type{UUID})
    reader.type == BSON_TYPE_BINARY || throw(BSONConversionError(reader.type, UUID))
    GC.@preserve reader begin
        p = pointer(reader)
        subtype = unsafe_load(p + 4)
        subtype == BSON_SUBTYPE_UUID || subtype == BSON_SUBTYPE_UUID_OLD || throw(
            BSONConversionError(reader.type, subtype, UUID)
        )
        len = load_bits_(Int32, p)
        len != 16 && error("Unexpected UUID length $len")
        return UUID(ntoh(unsafe_load(Ptr{UInt128}(p + 5))))
    end
end

@inline function read_field_(reader::BSONReader, ::Type{BSONUUIDOld})
    reader.type == BSON_TYPE_BINARY || throw(BSONConversionError(reader.type, BSONUUIDOld))
    GC.@preserve reader begin
        p = pointer(reader)
        subtype = unsafe_load(p + 4)
        subtype == BSON_SUBTYPE_UUID_OLD || throw(BSONConversionError(reader.type, subtype, BSONUUIDOld))
        len = load_bits_(Int32, p)
        len != 16 && error("Unexpected UUID length $len")
        return BSONUUIDOld(UUID(ntoh(unsafe_load(Ptr{UInt128}(p + 5)))))
    end
end

@inline function read_string_(reader::BSONReader)
    GC.@preserve reader begin
        p = pointer(reader)
        len = Int(load_bits_(Int32, p))
        validate_string(reader.validator, p + 4, len - 1)
        UnsafeBSONString(p + 4, len - 1)
    end
end

@inline function read_field_(reader::BSONReader, ::Type{UnsafeBSONString})
    reader.type == BSON_TYPE_STRING || reader.type == BSON_TYPE_CODE || reader.type == BSON_TYPE_SYMBOL || throw(
        BSONConversionError(reader.type, UnsafeBSONString)
    )
    read_string_(reader)
end

function read_field_(reader::BSONReader, ::Type{String})
    reader.type == BSON_TYPE_STRING || reader.type == BSON_TYPE_CODE || reader.type == BSON_TYPE_SYMBOL || throw(
        BSONConversionError(reader.type, String)
    )
    GC.@preserve reader String(read_string_(reader))
end

function read_field_(reader::BSONReader, ::Type{BSONCode})
    reader.type == BSON_TYPE_CODE || throw(BSONConversionError(reader.type, BSONCode))
    GC.@preserve reader begin
        p = pointer(reader)
        len = Int(load_bits_(Int32, p))
        validate_string(reader.validator, p + 4, len - 1)
        BSONCode(unsafe_string(p + 4, len - 1))
    end
end

function read_field_(reader::BSONReader, ::Type{BSONSymbol})
    reader.type == BSON_TYPE_SYMBOL || throw(BSONConversionError(reader.type, BSONSymbol))
    BSONSymbol(reader[String])
end

function read_field_(reader::BSONReader, ::Type{BSONRegex})
    reader.type == BSON_TYPE_REGEX || throw(BSONConversionError(reader.type, BSONRegex))
    GC.@preserve reader begin
        p = pointer(reader)
        len1 = unsafe_trunc(Int, ccall(:strlen, Csize_t, (Cstring,), p))
        BSONRegex(
            unsafe_string(p, len1),
            unsafe_string(p + len1 + 1)
        )
    end
end

function read_field_(reader::BSONReader, ::Type{BSONDBPointer})
    reader.type == BSON_TYPE_DB_POINTER || throw(BSONConversionError(reader.type, BSONDBPointer))
    GC.@preserve reader begin
        p = pointer(reader)
        len = Int(load_bits_(Int32, p))
        validate_string(reader.validator, p + 4, len - 1)
        collection = unsafe_string(p + 4, len - 1)
        ref = unsafe_load(Ptr{BSONObjectId}(p + 4 + len))
        BSONDBPointer(collection, ref)
    end
end

@inline function read_field_(reader::BSONReader, ::Type{BSONMinKey})
    reader.type == BSON_TYPE_MIN_KEY || throw(BSONConversionError(reader.type, BSONMinKey))
    BSONMinKey()
end

@inline function read_field_(reader::BSONReader, ::Type{BSONMaxKey})
    reader.type == BSON_TYPE_MAX_KEY || throw(BSONConversionError(reader.type, BSONMaxKey))
    BSONMaxKey()
end

@inline function read_field_(reader::BSONReader, ::Type{BSONUndefined})
    reader.type == BSON_TYPE_UNDEFINED || throw(BSONConversionError(reader.type, BSONUndefined))
    BSONUndefined()
end

@inline function read_field_(reader::BSONReader, ::Type{Nothing})
    reader.type == BSON_TYPE_NULL || throw(BSONConversionError(reader.type, Nothing))
    nothing
end

function read_field_(reader::AbstractBSONReader, ::Type{Number})
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

function read_field_(reader::AbstractBSONReader, ::Type{Integer})
    t = reader.type
    if t == BSON_TYPE_INT64
        reader[Int64]
    elseif t == BSON_TYPE_INT32
        reader[Int32]
    else
        throw(BSONConversionError(t, Number))
    end
end

function read_field_(reader::AbstractBSONReader, ::Type{AbstractFloat})
    t = reader.type
    if t == BSON_TYPE_DOUBLE
        reader[Float64]
    elseif t == BSON_TYPE_DECIMAL128
        reader[Dec128]
    else
        throw(BSONConversionError(t, Number))
    end
end

@inline function read_field_(reader::AbstractBSONReader, ::Type{Union{Nothing, T}}) where T
    reader.type == BSON_TYPE_NULL ? nothing : reader[T]
end

function read_field_(reader::BSONReader, ::Type{BSONCodeWithScope})
    reader.type == BSON_TYPE_CODE_WITH_SCOPE || throw(BSONConversionError(reader.type, BSONCodeWithScope))
    src = reader.src
    GC.@preserve src begin
        offset = reader.offset
        p = pointer(reader.src) + offset
        code_len = Int(load_bits_(Int32, p + 4))
        doc_offset = offset + code_len + 8
        validate_field(reader.validator, BSON_TYPE_CODE, p + 8, code_len, Int(load_bits_(Int32, p)) - 11)
        validate_string(reader.validator, p + 8, code_len - 1)
        BSONCodeWithScope(
            unsafe_string(p + 8, code_len - 1),
            BSONReader(src, doc_offset, BSON_TYPE_DOCUMENT, reader.validator, reader.conversions)[Dict{String, Any}]
        )
    end
end

function read_field_(reader::AbstractBSONReader, ::Type{T}) where {X, T <: AbstractDict{String, X}}
    foldxl(reader; init = T()) do state, x
        state[String(x.first)] = x.second[X]
        state
    end
end

function read_field_(reader::AbstractBSONReader, ::Type{T}) where {X, T <: AbstractDict{Symbol, X}}
    foldxl(reader; init = T()) do state, x
        state[Symbol(x.first)] = x.second[X]
        state
    end
end

function read_field_(reader::AbstractBSONReader, ::Type{Vector{T}}) where T
    dst = T[]
    copy!(dst, reader)
end

function read_field_(reader::T, ::Type{<:Union{T, AbstractBSONReader}}) where {T <: AbstractBSONReader}
    reader
end

function Base.copy!(dst::AbstractArray{T}, reader::AbstractBSONReader) where T
    copy!(Map(x -> x.second[T]), dst, reader)
end

function read_field_(reader::AbstractBSONReader, ::Type{Any})
    if reader.type == BSON_TYPE_DOUBLE
        reader[Float64]
    elseif reader.type == BSON_TYPE_STRING
        reader[String]
    elseif reader.type == BSON_TYPE_DOCUMENT
        reader[LittleDict{String, Any}]
    elseif reader.type == BSON_TYPE_ARRAY
        reader[Vector{Any}]
    elseif reader.type == BSON_TYPE_BINARY
        x = reader[BSONBinary]
        data = x.data
        if x.subtype == BSON_SUBTYPE_UUID && length(data) == 16
            GC.@preserve data UUID(ntoh(unsafe_load(Ptr{UInt128}(pointer(data)))))
        elseif x.subtype == BSON_SUBTYPE_UUID_OLD && length(data) == 16
            GC.@preserve data BSONUUIDOld(UUID(ntoh(unsafe_load(Ptr{UInt128}(pointer(data))))))
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
    elseif reader.type == BSON_TYPE_SYMBOL
        reader[BSONSymbol]
    elseif reader.type == BSON_TYPE_INT32
        reader[Int32]
    elseif reader.type == BSON_TYPE_TIMESTAMP
        reader[BSONTimestamp]
    elseif reader.type == BSON_TYPE_INT64
        reader[Int64]
    elseif reader.type == BSON_TYPE_DECIMAL128
        reader[Dec128]
    elseif reader.type == BSON_TYPE_MIN_KEY
        reader[BSONMinKey]
    elseif reader.type == BSON_TYPE_MAX_KEY
        reader[BSONMaxKey]
    elseif reader.type == BSON_TYPE_UNDEFINED
        reader[BSONUndefined]
    elseif reader.type == BSON_TYPE_CODE_WITH_SCOPE
        reader[BSONCodeWithScope]
    elseif reader.type == BSON_TYPE_DB_POINTER
        reader[BSONDBPointer]
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

@inline function bson_read_unversioned(::Type{T}, reader::AbstractBSONReader) where T
    if bson_simple(T)
        bson_read_simple(T, reader)
    else
        bson_read_structtype(T, reader)
    end
end

@inline function bson_read_versioned(::Type{T}, v::V, reader::AbstractBSONReader) where {T, V}
    target = bson_schema_version(T)
    v != target && error("Mismatched schema version, read: $v, target: $target")
    bson_read_unversioned(T, reader)
end

@inline function bson_read(::Type{T}, reader::AbstractBSONReader) where T
    target_v = bson_schema_version(T)
    if target_v !== nothing
        v = reader[bson_schema_version_field(T)][typeof(target_v)]
        bson_read_versioned(T, v, reader)
    else
        bson_read_unversioned(T, reader)
    end
end

@inline function read_field_(reader::AbstractBSONReader, ::Type{T}) where T
    # If T is a struct or not concrete (abstract or union), assume it has an implementation to read as object
    if isstructtype(T) || !isconcretetype(T)
        bson_read(T, reader)
    else
        throw(ArgumentError("Unsupported type $T"))
    end
end

@inline function Base.getindex(reader::AbstractBSONReader, ::Type{T}) where T
    RT = bson_representation_type(reader.conversions, T)
    if RT != T
        bson_representation_convert(reader.conversions, T, read_field_(reader, RT))
    else
        read_field_(reader, T)
    end
end

@inline @generated function Base.getindex(reader::AbstractBSONReader, ::Type{T}) where T <: NamedTuple
    field_readers = map(zip(fieldnames(T), fieldtypes(T))) do (fn, ft)
        fns = string(fn)
        :(reader[$fns][$ft])
    end
    :($T(($(field_readers...),)))
end
