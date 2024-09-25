"""
    bson_read([T=Any], src::Union{IO, DenseVector{UInt8}})

Read an object from the BSON document encoded in `src`.
"""
bson_read(::Type{T}, bytes::DenseVector{UInt8}; kwargs...) where T = BSONReader(bytes; kwargs...)[T]

"""
    bson_read([T=Any], path::AbstractString)

Read an object from the BSON document at `path`.
"""
bson_read(::Type{T}, path::AbstractString; kwargs...) where T = bson_read(T, read(path); kwargs...)

function bson_read(::Type{T}, io::IO; kwargs...) where T
    buf = UInt8[]
    readbytes!(io, buf, typemax(Int))
    bson_read(T, buf; kwargs...)
end

bson_read(bytes::DenseVector{UInt8}; kwargs...) = bson_read(Any, bytes; kwargs...)
bson_read(path::AbstractString; kwargs...) = bson_read(Any, path; kwargs...)
bson_read(io::IO; kwargs...) = bson_read(Any, io; kwargs...)

"""
    bson_write(dst::Union{IO, DenseVector{UInt8}}, x)
    bson_write(dst::Union{IO, DenseVector{UInt8}}, xs::Pair...)

Encode `x` or each element of `xs` as a BSON document in `dst` and return `dst`.
"""
function bson_write(buf::DenseVector{UInt8}, x; kwargs...)
    writer = BSONWriter(buf; kwargs...)
    writer[] = x
    close(writer)
    buf
end

function bson_write(buf::DenseVector{UInt8}, xs::Pair...; kwargs...)
    writer = BSONWriter(buf; kwargs...)
    for (k, v) in xs
        writer[k] = v
    end
    close(writer)
    buf
end

function bson_write(io::IO, x...; kwargs...)
    buf = UInt8[]
    bson_write(buf, x...; kwargs...)
    write(io, buf)
    io
end

"""
    bson_write(path::AbstractString, x)
    bson_write(path::AbstractString, xs::Pair...)

Encode `x` or each element of `xs` as fields of a BSON document and write to `path`.
"""
function bson_write(path::AbstractString, x...; kwargs...)
    open(path, "w") do io
        bson_write(io, x...; kwargs...)
    end
    nothing
end
