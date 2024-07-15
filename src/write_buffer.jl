mutable struct BSONWriteBuffer <: DenseVector{UInt8}
    data::Vector{UInt8}
    len::Int

    BSONWriteBuffer() = new(UInt8[], 0)
end

function Base.sizehint!(buffer::BSONWriteBuffer, capacity::Integer)
    resize!(buffer.data, max(capacity, buffer.len))
    buffer
end

@inline function Base.empty!(buffer::BSONWriteBuffer)
    buffer.len = 0
    buffer
end

@inline Base.length(buffer::BSONWriteBuffer) = buffer.len

@inline Base.size(buffer::BSONWriteBuffer) = (buffer.len,)

@inline Base.sizeof(buffer::BSONWriteBuffer) = buffer.len

@inline Base.elsize(BSONWriteBuffer) = 1

@inline function Base.getindex(buffer::BSONWriteBuffer, i::Integer)
    @boundscheck (i > 0 && i <= buffer.len) || throw(BoundsError(buffer, i))
    @inbounds buffer.data[i]
end

@inline function Base.resize!(buffer::BSONWriteBuffer, len::Int)
    if length(buffer.data) < len
        resize!(buffer.data, len * 2)
    end
    buffer.len = len
    buffer
end

@inline Base.pointer(buffer::BSONWriteBuffer) = pointer(buffer.data)

@inline function Base.push!(buffer::BSONWriteBuffer, x::UInt8)
    if length(buffer.data) == buffer.len
        resize!(buffer.data, max(buffer.len * 2, 10))
    end
    buffer.len += 1
    @inbounds buffer.data[buffer.len] = x
    buffer
end
