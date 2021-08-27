struct BSONConversionError <: Exception
    src_type::UInt8
    src_subtype::Union{Nothing, UInt8}
    dst_type::DataType
end

BSONConversionError(src_type::UInt8, dst_type::DataType) = BSONConversionError(src_type, nothing, dst_type)

struct BSONValidationError <: Exception
    msg::String
end