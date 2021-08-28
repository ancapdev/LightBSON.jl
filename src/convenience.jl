"""
    bson_read([T=Any], src::Union{IO, DenseVector{UInt8}})

Read an object from the BSON document encoded in `src`.
"""
bson_read(::Type{T}, bytes::DenseVector{UInt8}) where T = BSONReader(bytes)[T]

"""
    bson_read([T=Any], path::AbstractString)

Read an object from the BSON document at `path`.
"""
bson_read(::Type{T}, path::AbstractString) where T = bson_read(T, read(path))

function bson_read(::Type{T}, io::IO) where T
    buf = UInt8[]
    readbytes!(io, buf, typemax(Int))
    bson_read(T, buf)
end

bson_read(bytes::DenseVector{UInt8}) = bson_read(Any, bytes)
bson_read(path::AbstractString) = bson_read(Any, path)
bson_read(io::IO) = bson_read(Any, io)

"""
    bson_write(dst::Union{IO, DenseVector{UInt8}}, x)
    bson_write(dst::Union{IO, DenseVector{UInt8}}, xs::Pair...)

Encode `x` or each element of `xs` as a BSON document in `dst` and return `dst`.
"""
function bson_write(buf::DenseVector{UInt8}, x)
    writer = BSONWriter(buf)
    writer[] = x
    close(writer)
    buf
end

function bson_write(buf::DenseVector{UInt8}, xs::Pair...)
    writer = BSONWriter(buf)
    for (k, v) in xs
        writer[k] = v
    end
    close(writer)
    buf
end

function bson_write(io::IO, x...)
    buf = UInt8[]
    bson_write(buf, x...)
    write(io, buf)
    io
end

"""
    bson_write(path::AbstractString, x)
    bson_write(path::AbstractString, xs::Pair...)

Encode `x` or each element of `xs` as fields of a BSON document and write to `path`.
"""
function bson_write(path::AbstractString, x...)
    open(path, "w") do io
        bson_write(io, x...)
    end
    nothing
end
