struct BSONObjectId
    data::NTuple{12, UInt8}
end

Base.isless(x::BSONObjectId, y::BSONObjectId) = x.data < y.data

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
    seq::Threads.Atomic{UInt32}
    rnd::NTuple{5, UInt8}
    cache_pad2::NTuple{4, UInt128}

    function BSONObjectIdGenerator()
        seq = Threads.Atomic{UInt32}(rand(UInt32))
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

@inline id_from_parts_(t, r, s) = BSONObjectId((
    (t >> 24) % UInt8,
    (t >> 16) % UInt8,
    (t >> 8) % UInt8,
    t % UInt8,
    r[1],
    r[2],
    r[3],
    r[4],
    r[5],
    (s >> 16) % UInt8,
    (s >> 8) % UInt8,
    s  % UInt8,
))

@inline Base.getindex(x::BSONObjectIdGenerator) = id_from_parts_(
    seconds_from_epoch_(),
    x.rnd,
    Threads.atomic_add!(x.seq, UInt32(1))
)

struct BSONObjectIdIterator
    t::UInt32
    r::NTuple{5, UInt8}
    first::UInt32
    past_last::UInt32
end

Base.eltype(::BSONObjectIdIterator) = BSONObjectId

@inline Base.length(x::BSONObjectIdIterator) = (x.past_last - x.first) % Int

@inline function Base.iterate(x::BSONObjectIdIterator, cur::UInt32 = x.first)
    if cur == x.past_last
        nothing
    else
        id_from_parts_(x.t, x.r, cur), cur + UInt32(1)
    end
end

@inline function Base.getindex(x::BSONObjectIdGenerator, range)
    n = length(range) % UInt32
    first = Threads.atomic_add!(x.seq, n)
    BSONObjectIdIterator(seconds_from_epoch_(), x.rnd, first, first + n)
end

default_object_id_generator::BSONObjectIdGenerator = BSONObjectIdGenerator()

@inline BSONObjectId() = default_object_id_generator[]

@inline bson_object_id_range(n::Integer) = default_object_id_generator[1:n]
