@inline bson_representation_type(::Type{T}) where T = T
@inline bson_representation_type(::Type{Symbol}) = String
@inline bson_representation_type(::Type{<:Enum}) = String

@inline bson_representation_convert(::Type{T}, x) where T = StructTypes.construct(T, x)
@inline bson_representation_convert(::Type{String}, x) = string(x)

@inline bson_representation_type(::Type{Vector{UInt8}}) = BSONBinary
@inline bson_representation_convert(::Type{Vector{UInt8}}, x::BSONBinary) = x.data
@inline bson_representation_convert(::Type{BSONBinary}, x::Vector{UInt8}) = BSONBinary(x)
