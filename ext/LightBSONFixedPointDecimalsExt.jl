module LightBSONFixedPointDecimalsExt

using LightBSON
using FixedPointDecimals
using DecFP

@inline LightBSON.bson_representation_type(::Type{FixedDecimal{T, f}}) where {T, f} = Dec128

@inline LightBSON.bson_representation_convert(::Type{Dec128}, x::FixedDecimal{T, f}) where {T, f} =
    Dec128(Int128(x.i), -f)

@inline LightBSON.bson_representation_convert(::Type{FixedDecimal{T, f}}, x::Dec128) where {T, f} =
    reinterpret(FixedDecimal{T, f}, T(x * Dec128(1, f)))

end
