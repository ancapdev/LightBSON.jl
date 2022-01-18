@inline function bson_representation_type(::Type{T}) where T
    if StructTypes.StructType(T) == StructTypes.StringType()
        String
    else
        T
    end
end

@inline bson_representation_convert(::Type{String}, x) = string(x)
@inline bson_representation_convert(::Type{T}, x) where T = StructTypes.construct(T, x)
