function fileio_save(f, x; kwargs...)
    get(kwargs, :plain, false) || error("Pass plain = true to select LigthBSON.jl over BSON.jl")
    bson_write(f.filename, x)
    nothing
end

function fileio_load(f)
    buf = read(f.filename)
    reader = BSONReader(buf)
    hastag = false
    hastype = false
    foreach(reader) do field
        hastag |= field.first == "tag"
        hastype |= field.first == "type"
        nothing
    end
    hastag && hastype && error("BSON.jl document detected, aborting LightBSON.jl load")
    reader[Any]
end