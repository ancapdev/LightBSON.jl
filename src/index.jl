struct BSONIndexKey
    name_p::Ptr{UInt8}
    name_len::Int32
    parent_offset::Int32
end

@inline BSONIndexKey(name::AbstractString, parent_offset::Integer) = BSONIndexKey(
    pointer(name),
    sizeof(name) % Int32,
    parent_offset % Int32
)

@inline BSONIndexKey(name::Symbol, parent_offset::Integer) = BSONIndexKey(
    Base.unsafe_convert(Ptr{UInt8}, name),
    ccall(:strlen, Csize_t, (Cstring,), Base.unsafe_convert(Ptr{UInt8}, name)) % Int32,
    parent_offset % Int32
)

@inline function Base.isequal(x::BSONIndexKey, y::BSONIndexKey)
    x.name_len == y.name_len &&
        x.parent_offset == y.parent_offset &&
        ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), x.name_p, y.name_p, x.name_len % Csize_t) == 0
end

struct BSONIndexValue
    offset::Int32
    type::UInt8
end

mutable struct BSONIndex
    entries::Vector{Tuple{BSONIndexKey, Int32, BSONIndexValue}}
    version::Int32
    size_mask::Int32
    include_arrays::Bool

    function BSONIndex(size::Integer; include_arrays::Bool = false)
        pow2size = nextpow(2, size)
        new(
            fill((BSONIndexKey(Ptr{UInt8}(0), 0, 0), 0, BSONIndexValue(0, 0)), pow2size),
            0,
            pow2size - 1,
            include_arrays
        )
    end
end

function build_index_(index::BSONIndex, reader::BSONReader, ::Val{include_arrays}) where include_arrays
    let parent_offset = reader.offset % Int32
        f = @inline x -> begin
            name = x.first
            field_reader = x.second
            key = BSONIndexKey(name.ptr, name.len % Int32, parent_offset)
            value = BSONIndexValue(field_reader.offset % Int32, field_reader.type)
            index[key] = value
            if field_reader.type == BSON_TYPE_DOCUMENT || (include_arrays && field_reader.type == BSON_TYPE_ARRAY)
                build_index_(index, field_reader, Val{include_arrays}())
            end
            nothing
        end
        foreach(f, Map(identity), reader)
    end
    nothing
end

@inline function index_(index::BSONIndex, key::BSONIndexKey)
    nh = fnv1a(UInt32, key.name_p, key.name_len)
    oh = reinterpret(UInt32, key.parent_offset) * 0x9e3779b1
    h = nh ⊻ (oh + 0x9e3779b9 + (nh << 6) + (nh >> 2))
    (h & index.size_mask) % Int + 1
end

@inline function Base.setindex!(index::BSONIndex, reader::BSONReader)
    index.version += Int32(1)
    if index.include_arrays
        build_index_(index, reader, Val{true}())
    else
        build_index_(index, reader, Val{false}())
    end
    nothing
end

@inline function Base.setindex!(index::BSONIndex, value::BSONIndexValue, key::BSONIndexKey)
    @inbounds index.entries[index_(index, key)] = (key, index.version, value)
    nothing
end

@inline function Base.getindex(index::BSONIndex, key::BSONIndexKey)
    @inbounds e_key, e_version, e_value = index.entries[index_(index, key)]
    (e_version == index.version && isequal(e_key, key)) ? e_value : nothing
end
