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

function Base.setindex!(
    writer::BSONWriter, value::T, name::AbstractString
) where T <: Union{
    Float64,
    Int64,
    Int32,
    #Bool, -- needs conversion to UInt8
    #DateTime, -- needs conversion to Int64 millis since unix epoch
    Dec128,
    #UUID, -- needs to be written as binary with subtype uuid
    BSONTimestamp,
    BSONObjectId
}
    dst = writer.dst
    offset = length(dst)
    name_len = length(name)
    resize!(dst, offset + 2 + name_len + sizeof(value))
    GC.@preserve dst name begin
        p = pointer(dst) + offset
        unsafe_store!(p, bson_type(T))
        unsafe_copyto!(p + 1, Base.unsafe_convert(Ptr{UInt8}, name), name_len)
        unsafe_store!(p + 1 + name_len, 0x0)
        unsafe_store!(Ptr{T}(p + 2 + name_len), value)
    end
    nothing
end