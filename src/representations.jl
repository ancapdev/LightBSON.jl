abstract type BSONConversionRules end

struct DefaultBSONConversions <: BSONConversionRules end

@inline bson_representation_type(::DefaultBSONConversions, ::Type{T}) where T = bson_representation_type(T)
@inline bson_representation_convert(::DefaultBSONConversions, ::Type{T}, x) where T = bson_representation_convert(T, x)

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

struct NumericBSONConversions <: BSONConversionRules end

@inline function bson_representation_type(::NumericBSONConversions, ::Type{T}) where T
    bson_representation_type(DefaultBSONConversions(), T)
end

@inline function bson_representation_convert(::NumericBSONConversions, ::Type{T}, x) where T
    bson_representation_convert(DefaultBSONConversions(), T, x)
end

@inline bson_representation_type(::NumericBSONConversions, ::Type{UInt32}) = Int32
@inline bson_representation_type(::NumericBSONConversions, ::Type{UInt64}) = Int64
@inline bson_representation_type(::NumericBSONConversions, ::Type{Float32}) = Float64

@inline bson_representation_convert(::NumericBSONConversions, ::Type{Float64}, x::Float32) = Float64(x)
@inline bson_representation_convert(::NumericBSONConversions, ::Type{Float32}, x::Float64) = Float32(x)
@inline bson_representation_convert(::NumericBSONConversions, ::Type{Int32}, x::UInt32) = reinterpret(Int32, x)
@inline bson_representation_convert(::NumericBSONConversions, ::Type{UInt32}, x::Int32) = reinterpret(UInt32, x)
@inline bson_representation_convert(::NumericBSONConversions, ::Type{Int64}, x::UInt64) = reinterpret(Int64, x)
@inline bson_representation_convert(::NumericBSONConversions, ::Type{UInt64}, x::Int64) = reinterpret(UInt64, x)
