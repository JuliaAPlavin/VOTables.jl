module VOTables

using EzXML
using DictArrays
using Dictionaries
using DataPipes
using Accessors
using Dates


function read(votfile; postprocess=true, unitful=false)
    tblx = tblxml(votfile)
    _fieldattrs = fieldattrs(tblx)
    @p let
        _fieldattrs
        map(Symbol(_[:name]) => Union{vo2jltype(_),Missing}[])
        dictionary
        DictArray
        _filltable!(__, tblx)
        @modify(col -> map(identity, col), __ |> Properties())  # narrow types, removing Missing unless actually present
        postprocess ? @modify(AbstractDictionary(__)) do dct
            _fieldattrs_dct = @p _fieldattrs |> map(Symbol(_[:name]) => _) |> dictionary
            map(pairs(dct)) do (k, col)  # XXX: need to make typestable
                postprocess_col(col, _fieldattrs_dct[k]; unitful)
            end
        end : __
    end
end

function postprocess_col(col, attrs; unitful::Bool)
    ucds = split(get(attrs, :ucd, ""), ";")
    unit = get(attrs, :unit, nothing)
    if "time.epoch" in ucds
        if unit == "'Y:M:D'"
            map(x -> parse(Date, x, dateformat"Y-m-d"), col)
        else
            @warn "unknown time unit" unit
            col
        end
    elseif "pos.eq.ra" in ucds && unit == "\"h:m:s\""
        hms2rad.(col)
    elseif "pos.eq.dec" in ucds && unit == "\"d:m:s\""
        dms2rad.(col)
    elseif unitful && !isnothing(unit)
        unit_viz_to_jl(col, unit)
    else
        col
    end
end

unit_viz_to_jl(_, _) = error("Load Unitful.jl to use units")

function _filltable!(res, tblx)
    @p let
        tblx
        @aside ns = ["ns" => namespace(__)]
        findall("ns:DATA/ns:TABLEDATA", __, ns)
        only
        findall("ns:TR", __, ns)
        foreach() do tr
            map(AbstractDictionary(res), eachelement(tr)) do col, td  # XXX: need to make typestable
                @assert nodename(td) == "TD"
                val = _parse(eltype(col), nodecontent(td))
                push!(col, val)
            end
        end
    end
    return res
end

tblxml(votfile) = @p let
    Base.read(votfile, String)
    parsexml
    root
    @aside ns = ["ns" => namespace(__)]
    findall("ns:RESOURCE/ns:TABLE", __, ns)
    only
end

description(tblxml) = @p let
    tblxml
    @aside ns = ["ns" => namespace(__)]
    findall("ns:DESCRIPTION", __, ns)
    only
    nodecontent
end

fieldattrs(tblxml) = @p let
    tblxml
    @aside ns = ["ns" => namespace(__)]
    findall("ns:FIELD", __, ns)
    map() do fieldxml
        attrs = @p attributes(fieldxml) |> map(Symbol(nodename(_)) => nodecontent(_)) |> dictionary
        desc = @p fieldxml |> findall("ns:DESCRIPTION", __, ns) |> only |> nodecontent
        insert!(attrs, :description, desc)
        return attrs
    end
end

TYPE_VO_TO_JL = Dict(
    "boolean" => Bool,
    "bit" => Bool,
    "unsignedByte" => UInt8,
    "char" => Char,
    "unicodeChar" => Char,
    "short" => Int16,
    "int" => Int32,
    "long" => Int64,
    "float" => Float32,
    "double" => Float64,
    "floatComplex" => ComplexF32,
    "doubleComplex" => ComplexF64,
)

function vo2jltype(attrs)
    if get(attrs, :arraysize, "1") == "1"
        TYPE_VO_TO_JL[attrs[:datatype]]
    elseif attrs[:datatype] == "char"
        @assert occursin(r"^\d+$", attrs[:arraysize])
        String
    else
        @assert occursin(r"^\d+$", attrs[:arraysize])
        Vector{TYPE_VO_TO_JL[attrs[:datatype]]}
    end
end


_parse(::Type{Union{Missing, T}}, s) where {T} = _parse(T, s)
_parse(::Type{Union{Missing, T}}, s::Missing) where {T} = missing
_parse(::Type{Union{Missing, Char}}, s) = isempty(s) ? missing : only(s)
_parse(::Type{Union{Missing, Char}}, ::Missing) = missing  # disambiguation

_parse(::Type{T}, s) where {T} = parse(T, s)
_parse(::Type{Char}, s) = only(s)
_parse(::Type{String}, s) = s

end
