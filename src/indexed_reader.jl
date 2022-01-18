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

@inline function Base.getproperty(reader::IndexedBSONReader, f::Symbol)
    f == :type && return reader.reader.type
    getfield(reader, f)
end

@inline function Base.getindex(reader::IndexedBSONReader, name::Union{AbstractString, Symbol})
    src = reader.reader.src
    GC.@preserve src name begin
        key = BSONIndexKey(name, reader.reader.offset)
        value = reader.index[key]
        field_reader = if value !== nothing
            BSONReader(src, Int(value.offset), value.type, reader.reader.validator)
        else
            reader.reader[name]
        end
        IndexedBSONReader(reader.index, field_reader, Val{:internal}())
    end
end

@inline Base.getindex(reader::IndexedBSONReader, ::Type{T}) where T <: ValueField = reader.reader[T]

@inline read_field_(reader::IndexedBSONReader, ::Type{T}) where T <: ValueField = read_field_(reader.reader, T)