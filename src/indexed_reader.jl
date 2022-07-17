struct IndexedBSONReader{R <: BSONReader} <: AbstractBSONReader
    index::BSONIndex
    reader::R

    @inline function IndexedBSONReader(index::BSONIndex, reader::R) where R
        index[] = reader
        new{R}(index, reader)
    end

    @inline function IndexedBSONReader(index::BSONIndex, reader::R, ::Val{:internal}) where R
        new{R}(index, reader)
    end    
end

@inline Base.sizeof(reader::IndexedBSONReader) = sizeof(reader.reader)
@inline Base.foreach(f, reader::IndexedBSONReader) = foreach(f, reader.reader)
@inline function Base.getproperty(reader::IndexedBSONReader, f::Symbol)
    f == :type && return reader.reader.type
    f == :conversions && return reader.reader.conversions
    getfield(reader, f)
end

@inline function Base.getindex(reader::IndexedBSONReader, name::Union{AbstractString, Symbol})
    src = reader.reader.src
    GC.@preserve src name begin
        key = BSONIndexKey(name, reader.reader.offset)
        value = reader.index[key]
        field_reader = if value !== nothing
            BSONReader(src, Int(value.offset), value.type, reader.reader.validator, reader.reader.conversions)
        else
            reader.reader[name]
        end
        IndexedBSONReader(reader.index, field_reader, Val{:internal}())
    end
end

function Base.getindex(reader::IndexedBSONReader, i::Integer)
    el = getindex(reader.reader, i)
    IndexedBSONReader(reader.index, el, Val{:internal}())
end

@inline Transducers.__foldl__(rf, val, reader::IndexedBSONReader) = Transducers.__foldl__(rf, val, reader.reader)
@inline read_field_(reader::IndexedBSONReader, ::Type{T}) where T <: ValueField = read_field_(reader.reader, T)
