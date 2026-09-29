# XXX: to upstream to StringViews

# https://github.com/JuliaStrings/StringViews.jl/pull/23
function Base.unsafe_wrap(::Type{<:StringView}, cstr::Cstring)
    ptr = convert(Ptr{UInt8}, cstr)
    i = findfirst(i -> unsafe_load(ptr, i) == 0x00, 1:typemax(Int)) - 1
    return StringView(UnsafeArray(ptr, (i,)))
end

Base.IOBuffer(s::StringView) = IOBuffer(Vector{UInt8}(s))
