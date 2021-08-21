struct BSONConversionError <: Exception
    src_type::UInt8
    dst_type::DataType
end
