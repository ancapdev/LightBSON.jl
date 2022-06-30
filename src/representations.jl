@inline bson_representation_type(::Type{T}) where T = T
@inline bson_representation_type(::Type{Symbol}) = String
@inline bson_representation_type(::Type{<:Enum}) = String

@inline bson_representation_type(::Type{<:Tuple}) = Vector{Any}
@inline bson_representation_convert(::Type{Vector{Any}}, x::Tuple) = collect(x)
@inline bson_representation_convert(::Type{T}, x::Vector{Any}) where T <: Tuple = T(x)

@inline bson_representation_convert(::Type{T}, x) where T = StructTypes.construct(T, x)
@inline bson_representation_convert(::Type{String}, x) = string(x)

@inline bson_representation_type(::Type{Vector{UInt8}}) = BSONBinary
@inline bson_representation_convert(::Type{Vector{UInt8}}, x::BSONBinary) = x.data
@inline bson_representation_convert(::Type{BSONBinary}, x::Vector{UInt8}) = BSONBinary(x)

@inline bson_representation_type(::Type{<:IPAddr}) = String
@inline bson_representation_type(::Type{<:Sockets.InetAddr}) = String

bson_representation_convert(::Type{String}, x::Sockets.InetAddr{IPv4}) = "$(x.host):$(x.port)"

function bson_representation_convert(::Type{Sockets.InetAddr{IPv4}}, x::String)
    m = match(r"^(.*):(\d+)$", x)
    m === nothing && throw(ArgumentError("Invalid IPv4 inet address: $x"))
    Sockets.InetAddr(IPv4(m.captures[1]), parse(Int, m.captures[2]))
end

bson_representation_convert(::Type{String}, x::Sockets.InetAddr{IPv6}) = "[$(x.host)]:$(x.port)"

function bson_representation_convert(::Type{Sockets.InetAddr{IPv6}}, x::String)
    m = match(r"^\[(.*)\]:(\d+)$", x)
    m === nothing && throw(ArgumentError("Invalid IPv6 inet address: $x"))
    Sockets.InetAddr(IPv6(m.captures[1]), parse(Int, m.captures[2]))
end

@inline bson_representation_type(::Type{Date}) = DateTime
bson_representation_convert(::Type{Date}, x::DateTime) = Date(x)
bson_representation_convert(::Type{DateTime}, x::Date) = DateTime(x)
