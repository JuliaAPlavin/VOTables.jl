# so that it works with or without namespaces:
_namespaces(x) = [(k == "" ? "ns" : k) => v for (k, v) in namespaces(x)]
_findall(xpath, x, ns) =
    if any(n -> first(n) == "ns", ns)
        findall(xpath, x, ns)
    else
        findall(replace(xpath, "ns:" => ""), x)
    end

# adapted from corresponding functions in EzXML:

# nodename_sv(node::EzXML.Node) = node.ptr
function nodename_sv(ptr::Ptr{EzXML._Node})
    node_str = unsafe_load(ptr)
    if node_str.name == C_NULL
        throw(ArgumentError("no node name"))
    end
    unsafe_wrap(StringView, node_str.name)
end

nodecontent_sv(f, node::EzXML.Node) = nodecontent_sv(f, node.ptr)
function nodecontent_sv(f, ptr::Ptr{EzXML._Node})
    str_ptr = EzXML.@check ccall(
        (:xmlNodeGetContent, EzXML.libxml2),
        Cstring,
        (Ptr{Cvoid},),
        ptr) != C_NULL
    str = unsafe_wrap(StringView, str_ptr)
    res = try
        f(str)
    finally
        Libc.free(str_ptr)
    end
    return res
end

eachelementptr(node::EzXML.Node, backward::Bool=false) = ChildElementPtrIterator(node.ptr, backward)
eachelementptr(ptr::Ptr{EzXML._Node}, backward::Bool=false) = ChildElementPtrIterator(ptr, backward)

struct ChildElementPtrIterator
    ptr::Ptr{EzXML._Node}
    backward::Bool
end

function Base.iterate(iter::ChildElementPtrIterator)
    cur_ptr = iter.backward ? EzXML.last_element_ptr(iter.ptr) : EzXML.first_element_ptr(iter.ptr)
    cur_ptr == C_NULL && return nothing
    return cur_ptr, cur_ptr
end

function Base.iterate(iter::ChildElementPtrIterator, cur_ptr)
    cur_ptr = iter.backward ? EzXML.prev_element_ptr(cur_ptr) : EzXML.next_element_ptr(cur_ptr)
    cur_ptr == C_NULL && return nothing
    return cur_ptr, cur_ptr
end

# XXX: piracy, should upstream
function Base.write(io::IO, x::EzXML.Document)
    mktemp() do path, fio
        Base.write(path, x)
        Base.write(io, fio)
    end
end

function EzXML.parsexml(io::IO)
    mktemp() do path, fio
        seekstart(io)
        Base.write(fio, io)
        close(fio)
        @p StringView(Base.read(path)) |> parsexml
    end
end

# StreamReader zero-copy helpers using libxml2's const-pointer APIs (no allocation/free per call)
function nodename_sv_reader(reader::EzXML.StreamReader)
    ptr = ccall((:xmlTextReaderConstName, EzXML.libxml2), Cstring, (Ptr{Cvoid},), reader)
    ptr == C_NULL && return nothing
    unsafe_wrap(StringView, ptr)
end

function nodevalue_sv_reader(reader::EzXML.StreamReader)
    ptr = ccall((:xmlTextReaderConstValue, EzXML.libxml2), Cstring, (Ptr{Cvoid},), reader)
    ptr == C_NULL && return nothing
    unsafe_wrap(StringView, ptr)
end
