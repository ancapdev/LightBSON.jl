struct BSONWriter{D <: DenseVector{UInt8}, C <: BSONConversionRules}
    dst::D
    offset::Int
    conversions::C
    skipnull::Bool

    function BSONWriter(
        dst::D;
        conversions::C = DefaultBSONConversions(),
        skipnull::Bool = false,
    ) where {D <: DenseVector{UInt8}, C <: BSONConversionRules}
        offset = length(dst)
        resize!(dst, offset + 4)
        new{D, C}(dst, offset, conversions, skipnull)
    end
end

# For back compat
@inline BSONWriter(dst::DenseVector{UInt8}, conversions::BSONConversionRules) = BSONWriter(
    dst; conversions
)

function Base.close(writer::BSONWriter)
    dst = writer.dst
    push!(dst, 0x0)
    p = pointer(dst) + writer.offset
    GC.@preserve dst unsafe_store!(Ptr{Int32}(p), length(dst) - writer.offset)
    nothing
end

@inline wire_size_(::Type{T}) where T = missing
@inline wire_size_(::Type{T}) where T <: Union{
    Int32, Int64, Float64, Dec128, DateTime, BSONTimestamp, BSONObjectId
} = sizeof(T)
@inline wire_size_(::Type{T}) where T <: Union{Nothing, BSONMinKey, BSONMaxKey} = 0
@inline wire_size_(::Type{Bool}) = 1
@inline wire_size_(::Type{UUID}) = 21

@inline wire_size_(x) = sizeof(x)
@inline wire_size_(x::Nothing) = 0
@inline wire_size_(x::Union{String, UnsafeBSONString}) = sizeof(x) + 5
@inline wire_size_(x::BSONCode) = sizeof(x.code) + 5
@inline wire_size_(x::BSONSymbol) = sizeof(x.value) + 5
@inline wire_size_(x::UUID) = 21
@inline wire_size_(x::BSONUUIDOld) = 21
@inline wire_size_(x::Union{BSONBinary, UnsafeBSONBinary}) = 5 + length(x.data)
@inline wire_size_(x::BSONRegex) = 2 + sizeof(x.pattern) + sizeof(x.options)
@inline wire_size_(x::BSONMinKey) = 0
@inline wire_size_(x::BSONMaxKey) = 0
@inline wire_size_(x::BSONUndefined) = 0
@inline wire_size_(x::BSONDBPointer) = 17 + sizeof(x.collection)

@inline wire_store_(p::Ptr{UInt8}, x::T) where T = unsafe_store!(Ptr{T}(p), htol(x))
@inline wire_store_(::Ptr{UInt8}, ::Nothing) = nothing
@inline wire_store_(p::Ptr{UInt8}, x::Bool) = unsafe_store!(p, UInt8(x))
@inline wire_store_(p::Ptr{UInt8}, x::DateTime) = wire_store_(p, Dates.value(x) - Dates.UNIXEPOCH)
@inline wire_store_(p::Ptr{UInt8}, x::BSONTimestamp) = wire_store_(p, (x.counter % Int64) | ((x.time % Int64) << 32))
@inline wire_store_(p::Ptr{UInt8}, x::BSONObjectId) = unsafe_store!(Ptr{BSONObjectId}(p), x)
@inline wire_store_(::Ptr{UInt8}, ::BSONMinKey) = nothing
@inline wire_store_(::Ptr{UInt8}, ::BSONMaxKey) = nothing
@inline wire_store_(::Ptr{UInt8}, ::BSONUndefined) = nothing

@inline function wire_store_(p::Ptr{UInt8}, x::Union{String, UnsafeBSONString})
    unsafe_store!(Ptr{Int32}(p), (sizeof(x) + 1) % Int32)
    GC.@preserve x unsafe_copyto!(p + 4, pointer(x), sizeof(x))
    unsafe_store!(p + 4 + sizeof(x), 0x0)
end

@inline wire_store_(p::Ptr{UInt8}, x::BSONCode) = wire_store_(p, x.code)

@inline wire_store_(p::Ptr{UInt8}, x::BSONSymbol) = wire_store_(p, x.value)

@inline function wire_store_(p::Ptr{UInt8}, x::UUID)
    unsafe_store!(Ptr{Int32}(p), Int32(16))
    unsafe_store!(p + 4, BSON_SUBTYPE_UUID)
    unsafe_store!(Ptr{UInt128}(p + 5), hton(UInt128(x.value)))
end

@inline function wire_store_(p::Ptr{UInt8}, x::BSONUUIDOld)
    unsafe_store!(Ptr{Int32}(p), Int32(16))
    unsafe_store!(p + 4, BSON_SUBTYPE_UUID_OLD)
    unsafe_store!(Ptr{UInt128}(p + 5), hton(UInt128(x.value)))
end

@inline function wire_store_(p::Ptr{UInt8}, x::Union{BSONBinary, UnsafeBSONBinary})
    unsafe_store!(Ptr{Int32}(p), length(x.data) % Int32)
    unsafe_store!(p + 4, x.subtype)
    GC.@preserve x unsafe_copyto!(p + 5, pointer(x.data), length(x.data))
end

@inline function wire_store_(p::Ptr{UInt8}, x::BSONRegex)
    GC.@preserve x unsafe_copyto!(p, pointer(x.pattern), sizeof(x.pattern))
    unsafe_store!(p + sizeof(x.pattern), 0x0)
    GC.@preserve x unsafe_copyto!(p + sizeof(x.pattern) + 1, pointer(x.options), sizeof(x.options))
    unsafe_store!(p + sizeof(x.pattern) + sizeof(x.options) + 1 , 0x0)
end

@inline function wire_store_(p::Ptr{UInt8}, x::BSONDBPointer)
    wire_store_(p, x.collection)
    unsafe_store!(Ptr{BSONObjectId}(p + 5 + sizeof(x.collection)), x.ref)
end

@inline len_(x::AbstractString) = sizeof(x)
@inline len_(x::Symbol) = ccall(:strlen, Csize_t, (Cstring,), Base.unsafe_convert(Ptr{UInt8}, x)) % Int

@inline function write_header_(dst::DenseVector{UInt8}, t::UInt8, name::Union{String, Symbol}, value_size::Integer)
    name_len = len_(name)
    offset = length(dst)
    resize!(dst, offset + name_len + value_size + 2)
    GC.@preserve name dst begin
        p = pointer(dst) + offset
        unsafe_store!(p, t)
        ccall(
            :memcpy,
            Cvoid,
            (Ptr{UInt8}, Ptr{UInt8}, Csize_t),
            p + 1, Base.unsafe_convert(Ptr{UInt8}, name), name_len % Csize_t
        )
        unsafe_store!(p + name_len + 1, 0x0)
    end
    offset + name_len + 2
end

function write_field_(writer::BSONWriter, value::T, name::Union{String, Symbol}) where T <: ValueField
    dst = writer.dst
    offset = write_header_(dst, bson_type_(T), name, wire_size_(value))
    p = pointer(dst) + offset
    GC.@preserve dst wire_store_(p, value)
    nothing
end

function write_field_(writer::BSONWriter, value::BSONCodeWithScope, name::Union{String, Symbol})
    dst = writer.dst
    offset = write_header_(dst, BSON_TYPE_CODE_WITH_SCOPE, name, wire_size_(value.code) + 4)
    GC.@preserve dst begin
        p = pointer(dst) + offset
        wire_store_(p + 4, value.code)
        mappings_writer = BSONWriter(dst; writer.conversions, writer.skipnull)
        mappings_writer[] = value.mappings
        close(mappings_writer)
        p = pointer(dst) + offset
        unsafe_store!(Ptr{Int32}(p), length(dst) - offset)
    end
    nothing
end

function write_field_(writer::BSONWriter, generator::Function, name::Union{String, Symbol})
    dst = writer.dst
    write_header_(dst, BSON_TYPE_DOCUMENT, name, 0)
    element_writer = BSONWriter(dst; writer.conversions, writer.skipnull)
    generator(element_writer)
    close(element_writer)
end

const SMALL_INDEX_STRINGS = [string(i) for i in 0:99]

function write_field_(writer::BSONWriter, values::Union{AbstractVector, Base.Generator}, name::Union{String, Symbol})
    dst = writer.dst
    write_header_(dst, BSON_TYPE_ARRAY, name, 0)
    element_writer = BSONWriter(dst; writer.conversions, writer.skipnull)
    element_writer[] = values
    close(element_writer)
end

function Base.setindex!(writer::BSONWriter, values::Union{AbstractVector, Base.Generator})
    for (i, x) in enumerate(values)
        is = i <= length(SMALL_INDEX_STRINGS) ? SMALL_INDEX_STRINGS[i] : string(i - 1)
        writer[is] = x
    end
    nothing
end

@inline function write_field_(writer::BSONWriter, value::T, name::Union{String, Symbol}) where T
    if isstructtype(T)
        write_field_(writer, field_writer -> field_writer[] = value, name)
    else
        throw(ArgumentError("Unsupported type $T"))
    end
end

@inline function Base.setindex!(writer::BSONWriter, value::T, name::Union{String, Symbol}) where T
    value === nothing && writer.skipnull && return nothing
    RT = bson_representation_type(writer.conversions, T)
    if RT != T
        write_field_(writer, bson_representation_convert(writer.conversions, RT, value), name)
    else
        write_field_(writer, value, name)
    end
end

@inline function Base.setindex!(writer::BSONWriter, reader::BSONReader, name::Union{String, Symbol})
    len = sizeof(reader)
    offset = write_header_(writer.dst, reader.type, name, len)
    GC.@preserve reader writer unsafe_copyto!(pointer(writer.dst) + offset, pointer(reader), len)
    nothing
end

function Base.setindex!(writer::BSONWriter, fields::AbstractDict{<:Union{String, Symbol}})
    for (key, value) in fields
        writer[key] = value
    end
    nothing
end

@inline function Base.setindex!(writer::BSONWriter, field::Pair{String})
    writer[field.first] = field.second
    nothing
end

function Base.setindex!(writer::BSONWriter, fields::Tuple{Vararg{Pair{String, T} where T}})
    for (key, value) in fields
        writer[key] = value
    end
    nothing
end

@inline @generated function bson_write_simple(writer::BSONWriter, value::T) where T
    fieldcount(T) == 0 && return nothing
    totalsize = sum(wire_size_, fieldtypes(T)) + sum(sizeof, fieldnames(T)) + fieldcount(T) * 2
    if ismissing(totalsize)
        e = Expr(:block)
        for fn in fieldnames(T)
            fns = string(fn)
            push!(e.args, :(writer[$fns] = value.$fn))
        end
        e
    else
        e = Expr(:block)
        curoffset = 0
        for (ft, fn) in zip(fieldtypes(T), fieldnames(T))
            push!(e.args, :(unsafe_store!(p + $curoffset, $(bson_type_(ft)))))
            curoffset += 1
            fns = string(fn)
            fnl = sizeof(fns)
            push!(e.args, :(ccall(:memcpy, Cvoid, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), p + $curoffset, pointer($fns), $fnl)))
            curoffset += fnl
            push!(e.args, :(unsafe_store!(p + $curoffset, 0x0)))
            curoffset += 1
            push!(e.args, :(wire_store_(p + $curoffset, value.$fn)))
            curoffset += wire_size_(ft)
        end
        quote
            dst = writer.dst
            offset = length(dst)
            resize!(dst, offset + $totalsize)
            GC.@preserve dst begin
                p = pointer(dst) + offset
                $e
            end
        end
    end
end

@inline function bson_write_structtype(writer::BSONWriter, value)
    StructTypes.foreachfield(value) do i, name, FT, value
        writer[name] = value
    end
end

@inline function bson_write(writer::BSONWriter, value::T) where T
    v = bson_schema_version(T)
    if v !== nothing
        writer[bson_schema_version_field(T)] = v
    end
    if bson_simple(T)
        bson_write_simple(writer, value)
    else
        bson_write_structtype(writer, value)
    end
end

@inline function Base.setindex!(writer::BSONWriter, value::T) where T
    bson_write(writer::BSONWriter, value)
end
