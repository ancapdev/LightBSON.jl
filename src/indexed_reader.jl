struct BSONIndexedReader{R <: BSONReader}
    index::BSONIndex
    reader::R

    @inline function BSONIndexedReader(index::BSONIndex, reader::R) where R
        index[] = reader
        new{R}(index, reader)
    end

    @inline function BSONIndexedReader(index::BSONIndex, reader::R, ::Val{:internal}) where R
        new{R}(index, reader)
    end    
end

@inline function Base.getindex(reader::BSONIndexedReader, name::AbstractString)
    src = reader.reader.src
    GC.@preserve src name begin
        key = BSONIndexKey(pointer(name), sizeof(name) % Int32, reader.reader.offset % Int32)
        value = reader.index[key]
        field_reader = if value !== nothing
            BSONReader(src, Int(value.offset), value.type)
        else
            reader.reader[name]
        end
        BSONIndexedReader(reader.index, field_reader, Val{:internal}())
    end
end

@inline Base.getindex(reader::BSONIndexedReader, ::Type{T}) where T = reader.reader[T]