function StringViews.StringView(cstr::Cstring)
    ptr = convert(Ptr{UInt8}, cstr)
    i = findfirst(i -> unsafe_load(ptr, i) == 0x00, 1:typemax(Int)) - 1
    return StringView(UnsafeArray(ptr, (i,)))
end

# should remove this?
# and change to Ptr at https://github.com/JuliaIO/EzXML.jl/blob/a0025a7d801ec0cd6e74633de6ff2bd04e568696/src/document.jl#L83
Base.cconvert(::Type{Cstring}, s::StringView) = Vector{UInt8}(s)

Base.IOBuffer(s::StringView) = IOBuffer(Vector{UInt8}(s))
