abstract type BSONValidator end

struct UncheckedBSONValidator <: BSONValidator end
struct LightBSONValidator <: BSONValidator end
struct StrictBSONValidator <: BSONValidator end

@inline validate_field(
    ::BSONValidator,
    type::UInt8,
    p::Ptr{UInt8},
    field_length::Integer,
    available_length::Integer
) = nothing

@inline function validate_field(
    ::LightBSONValidator,
    type::UInt8,
    p::Ptr{UInt8},
    field_length::Integer,
    available::Integer
)
    field_length > available && throw(BSONValidationError("Field length too long, $field_length > $available"))
    nothing
end

@inline function validate_field(
    ::StrictBSONValidator,
    type::UInt8,
    p::Ptr{UInt8},
    field_length::Integer,
    available::Integer
)
    field_length > available && throw(BSONValidationError("Field length too long, $field_length > $available"))
    if type == BSON_TYPE_DOCUMENT || type == BSON_TYPE_ARRAY
        field_length < 5 && throw(BSONValidationError("Document or array under 5 bytes ($field_length)"))
        unsafe_load(p + field_length - 1) != 0 && throw(BSONValidationError("Document or array missing null terminator"))
    end
    nothing
end

@inline validate_root(::BSONValidator, src::DenseVector{UInt8}) = nothing

@inline function validate_root(validator::LightBSONValidator, src::DenseVector{UInt8})
    GC.@preserve src begin
        p = pointer(src)
        len = ltoh(unsafe_load(Ptr{Int32}(p)))
        validate_field(validator, BSON_TYPE_DOCUMENT, p, len, length(src))
    end
end

@inline function validate_root(validator::StrictBSONValidator, src::DenseVector{UInt8})
    GC.@preserve src begin
        p = pointer(src)
        len = ltoh(unsafe_load(Ptr{Int32}(p)))
        validate_field(validator, BSON_TYPE_DOCUMENT, p, len, length(src))
        len < length(src) && throw(BSONValidationError("Garbage after end of document"))
    end
end

@inline validate_bool(::BSONValidator, x::UInt8) = nothing

@inline function validate_bool(::StrictBSONValidator, x::UInt8)
    x == 0x0 || x == 0x1 || throw(BSONValidationError("Invalid bool value $x"))
    nothing
end

@inline validate_string(::BSONValidator, p::Ptr{UInt8}, len::Integer) = nothing

@inline function validate_string(::StrictBSONValidator, p::Ptr{UInt8}, len::Integer)
    unsafe_load(p + len) != 0 && throw(BSONValidationError("Code string missing null terminator"))
    s = unsafe_string(p, len)
    isvalid(s) || throw(BSONValidationError("Invalid UTF-8 string"))
    nothing
end

@inline validate_binary_subtype(::BSONValidator, p::Ptr{UInt8}, len::Integer, subtype::UInt8) = nothing

@inline function validate_binary_subtype(::StrictBSONValidator, p::Ptr{UInt8}, len::Integer, subtype::UInt8)
    if subtype == BSON_SUBTYPE_UUID || subtype == BSON_SUBTYPE_UUID_OLD || subtype == BSON_SUBTYPE_MD5
        len != 16 && throw(BSONValidationError("Subtype $subtype must be 16 bytes long"))
    elseif subtype == BSON_SUBTYPE_BINARY_OLD
        nested_len = ltoh(unsafe_load(Ptr{Int32}(p + 5)))
        nested_len != len - 4 && throw(
            BSONValidationError("Binary (Old) subtype invalid length $nested_len, expected $(len - 4)")
        )
    end
    nothing
end
