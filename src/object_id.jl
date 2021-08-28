struct BSONObjectId
    data::NTuple{12, UInt8}
end

function BSONObjectId(x::AbstractVector{UInt8})
    length(x) == 12 || throw(ArgumentError("ObjectId bytes must be 12 long"))
    BSONObjectId(NTuple{12, UInt8}(x))
end

function BSONObjectId(s::AbstractString)
    length(s) == 24 || throw(ArgumentError("ObjectId hex string must be 24 characters"))
    BSONObjectId(hex2bytes(s))
end

function Base.show(io::IO, x::BSONObjectId)
    print(io, bytes2hex(collect(x.data)))
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
