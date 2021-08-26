struct BSONObjectId
    data::NTuple{12, UInt8}
end

function nibble_to_int_(x::Char)
    if x >= '0' && x <= '9'
        x - '0'
    elseif x >= 'a' && x <= 'f'
        x - 'a' + 10
    elseif x >= 'A' && x <= 'F'
        x - 'A' + 10
    else
        throw(ArgumentError("Invalid hex digit $x"))
    end
end

function BSONObjectId(s::AbstractString)
    length(s) == 24 || throw(ArgumentError("ObjectId hex string must be 24 characters"))
    dst = Vector{UInt8}(undef, 12)
    for i in 1:12
        hi = nibble_to_int_(s[i*2 - 1]) % UInt8
        lo = nibble_to_int_(s[i*2]) % UInt8
        dst[i] = (hi << 4) | lo
    end
    BSONObjectId(NTuple{12, UInt8}(dst))
end

const HEX_DIGITS = [
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
]

function Base.show(io::IO, x::BSONObjectId)
    for i in 1:12
        print(io, HEX_DIGITS[x.data[i] >> 4 + 1])
        print(io, HEX_DIGITS[x.data[i] & 0xf + 1])
    end
    nothing
end

time_part_(x::BSONObjectId) = (Int(x.data[1]) << 24) | (Int(x.data[2]) << 16) | (Int(x.data[3]) << 8) | Int(x.data[4])

Dates.DateTime(x::BSONObjectId) = DateTime(Dates.UTM(Dates.UNIXEPOCH + time_part_(x) * 1000))

Base.time(x::BSONObjectId) = Float64(time_part_(x))

mutable struct BSONObjectIdGenerator
    cache_pad1::NTuple{4, UInt128}
    seq::UInt32
    rnd::NTuple{5, UInt8}
    cache_pad2::NTuple{4, UInt128}

    function BSONObjectIdGenerator()
        seq = rand(UInt32)
        rnd = rand(UInt64)
        new(
            (UInt128(0), UInt128(0), UInt128(0), UInt128(0)),
            seq,
            (
                (rnd >> 32) % UInt8,
                (rnd >> 24) % UInt8,
                (rnd >> 16) % UInt8,
                (rnd >> 8) % UInt8,
                rnd % UInt8,
            ),
            (UInt128(0), UInt128(0), UInt128(0), UInt128(0)),
        )
    end
end

function Base.show(io::IO, x::BSONObjectIdGenerator)
    print(io, "BSONObjectIdGenerator($(x.seq), $(x.rnd))")
end

if Sys.islinux()
    struct LinuxTimespec
        seconds::Clong
        nanoseconds::Cuint
    end
    @inline function seconds_from_epoch_()
        ts = Ref{LinuxTimespec}()
        ccall(:clock_gettime, Cint, (Cint, Ref{LinuxTimespec}), 0, ts)
        x = ts[]
        x.seconds % UInt32
    end
else
    @inline function seconds_from_epoch_()
        tv = Libc.TimeVal()
        tv.sec % UInt32
    end
end

function Base.getindex(x::BSONObjectIdGenerator)
    t = seconds_from_epoch_()
    x.seq += UInt32(1)
    s = x.seq
    BSONObjectId((
        (t >> 24) % UInt8,
        (t >> 16) % UInt8,
        (t >> 8) % UInt8,
        t % UInt8,
        x.rnd[1],
        x.rnd[2],
        x.rnd[3],
        x.rnd[4],
        x.rnd[5],
        (s >> 16) % UInt8,
        (s >> 8) % UInt8,
        s  % UInt8,
    ))
end

const DEFAULT_OBJECT_ID_GENERATORS = [BSONObjectIdGenerator() for _ in 1:Threads.nthreads()]

BSONObjectId() = @inbounds DEFAULT_OBJECT_ID_GENERATORS[Threads.threadid()][]
