@doc Base.read(joinpath(dirname(@__DIR__), "README.md"), String) module VOTables

using EzXML
using StringViews
using UnsafeArrays: UnsafeArray
using Mmap
using StructArrays
using Tables
using Dictionaries
using MetadataArrays
using DataAPI: metadata, colmetadata
using DataPipes
using AccessorsExtra
using AstroAngles
using Dates

export metadata, colmetadata

include("stringviews.jl")
include("xml.jl")
include("misc.jl")


"""    VOTables.read([result_type=StructArray], votfile; [postprocess=true], [unitful=false])

Read a VOTable from a file or another `IO` object. By default, the result is a `StructArray`: a Julian collection and table. Alternatively, specify `result_type=StructArray`.

- `postprocess=true`: do further processing of values, other than parsing formal VOTable datatypes. Includes parsing dates and times, and converting units to `Unitful.jl`; set to `false` to disable all of this.
- `unitful=false`: parse units from VOTable metadata to `Unitful.jl` units. Uses units from all loaded `Unitful`-compatible packages, ignores unknown units and shows warnings for them. Requires `postprocess=true`.
"""
function read end

struct VOTableException <: Exception
    message::String
end

# support Cols()?
# support <COOSYS> tag

read(votfile; kwargs...) = read(StructArray, votfile; kwargs...)

function read(result_type, votfile; postprocess=true, unitful=false, strict=true)
    tblx = tblxml(votfile; strict)
    _fieldattrs = fieldattrs(tblx)
    @p let
        _fieldattrs
        map(Symbol(_[:name]) => Union{vo2jltype(_),Missing}[])
        _container_from_components(result_type, __)
        _filltable!(__, tblx)
        @modify(col -> any(ismissing, col) ? col : convert(Vector{nonmissingtype(eltype(col))}, col), __ |> Properties())  # narrow types, removing Missing unless actually present
        postprocess ? @modify(Tables.columns(__)) do cols
            @assert cols isa Union{NamedTuple,AbstractDictionary}
            modify(cols, ∗, _fieldattrs) do col, attrs
                postprocess_col(col, attrs; unitful)
            end
        end : __
        @modify(Tables.columns(__)) do cols
            modify(cols, ∗, _fieldattrs) do col, attrs
                MetadataArray(
                    col,
                    _filter(!isnothing, (
                        description=get(attrs, :description, nothing),
                        ucd=get(attrs, :ucd, nothing),
                        unit_vot=get(attrs, :unit, nothing)
                    )),
                )
            end
        end
    end
end

write(votfile) = Base.Fix1(write, votfile)
function write(votfile, tbl)
    doc = XMLDocument()

    votablex = ElementNode("VOTABLE")
    votablex["version"] = "1.4"
    votablex["xmlns:xsi"] = "http://www.w3.org/2001/XMLSchema-instance"
    votablex["xmlns"] = "http://www.ivoa.net/xml/VOTable/v1.3"
    votablex["xsi:schemaLocation"] = "http://www.ivoa.net/xml/VOTable/v1.3 http://www.ivoa.net/xml/VOTable/v1.3"
    setroot!(doc, votablex)

    resourcex = addelement!(votablex, "RESOURCE")
    tablex = addelement!(resourcex, "TABLE")
    cols = Tables.columns(tbl)
    for (colname, col) in pairs(cols)
        fieldx = addelement!(tablex, "FIELD")
        fieldx["name"] = colname
        for (k, v) in jl2votype(eltype(col)) |> pairs
            fieldx[String(k)] = v
        end
    end
    tabledatax = addelement!(addelement!(tablex, "DATA"), "TABLEDATA")
    for r in Tables.rowtable(tbl)
        trx = addelement!(tabledatax, "TR")
        for val in r
            addelement!(trx, "TD", _unparse(val))
        end
    end
    EzXML.write(votfile, doc)
end

_container_from_components(::Type{StructArray}, pairs) = @p pairs |> NamedTuple{Tuple(first.(__))}(Tuple(last.(__))) |> StructArray

function postprocess_col(col, attrs; unitful::Bool)
    ucds = split(get(attrs, :ucd, ""), ";")
    unit = get(attrs, :unit, nothing)
    if "time.epoch" in ucds
        if eltype(col) <: AbstractString && unit == "'Y:M:D'"
            map(x -> parse(Date, x, dateformat"Y-m-d"), col)
        elseif eltype(col) <: Real && unit == "d"
            @warn "assuming julian days" column=attrs[:name]
            map(julian2datetime, col)
        elseif isnothing(unit)
            try
                map(x -> parse(Date, x, dateformat"Y-m-d"), col)
            catch exc
                @warn "unknown time unit" unit eltype(col) exc
                col
            end
        else
            @warn "unknown time unit" unit eltype(col)
            col
        end
    elseif "pos.eq.ra" in ucds && unit == "\"h:m:s\""
        hms2rad.(col)
    elseif "pos.eq.dec" in ucds && unit == "\"d:m:s\""
        dms2rad.(col)
    elseif unitful && !isnothing(unit)
        if eltype(col) <: Union{Number,Missing,Nothing}
            unit_viz_to_jl(col, unit)
        else
            @warn "column with a non-numeric eltype has a unit specified; ignoring the unit" unit eltype(col) attrs
            col
        end
    else
        col
    end
end

unit_viz_to_jl(_, _) = error("Load Unitful.jl to use units")

function _filltable!(res, tblx)
    trs = @p let
        tblx
        @aside ns = ["ns" => namespace(__)]
        findall("ns:DATA/ns:TABLEDATA", __, ns)
        only
        findall("ns:TR", __, ns)
    end
    for col in Tables.columns(res)
        sizehint!(col, length(trs))
    end
    foreach(trs) do tr
        for (col, td) in zip(Tables.columns(res), eachelementptr(tr))
            @assert nodename_sv(td) == "TD"
            @multiifs(
                (Bool, UInt8, Char, String, Int16, Int32, Int64, Float32, Float64, ComplexF32, ComplexF64),
                col isa AbstractVector{Union{Missing, _}},
                nodecontent_sv(content -> push!(col, _parse(eltype(col), content)), td),
                error("Shouldn't happen. Got eltype(col) == $(eltype(col))")
            )
        end
    end
    return res
end

function tblxml(votfile; strict::Bool)
    # xml = @p Base.read(votfile, String) |> parsexml
    xml = @p StringView(mmap(votfile)) |> parsexml
    tables = @p let 
        xml
        root
        @aside ns = ["ns" => namespace(__)]
        findall("ns:RESOURCE/ns:TABLE", __, ns)
    end
    infos = @p xml |> root |> findall("ns:RESOURCE/ns:INFO", __, ["ns" => namespace(__)])
    errorinfos = @p infos |> filter(uppercase(_["name"]) == "QUERY_STATUS" && uppercase(_["value"]) == "ERROR")
    if isempty(tables)
        if isempty(errorinfos)
            error("VOTable file has no tables")
        else
            error("VOTable file has no tables, see original errors ($(length(errorinfos))) below.\n$(join(nodecontent.(errorinfos), "\n\n"))")
        end
    end
    if !isempty(errorinfos)
        strict ?
            throw(VOTableException("VOTable file contains data, but errors have occurred. Pass `strict=false` to turn this exception into a warning.\n$(join(nodecontent.(errorinfos), "\n\n"))")) :
            @error "VOTable file contains data, but errors have occurred. Pass `strict=true` to turn this warning into an exception." errors=nodecontent.(errorinfos)
    end
    length(tables) == 1 ?
        only(tables) :
        error("VOTable files with multiple tables not supported yet")
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
        desc = @p fieldxml |> findall("ns:DESCRIPTION", __, ns) |> maybe(only)(__) |> maybe(nodecontent)(__)
        isnothing(desc) || insert!(attrs, :description, desc)
        return attrs
    end
end

const TYPE_VO_TO_JL = Dict(
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
    arraysize = get(attrs, :arraysize, nothing)
    basetype = TYPE_VO_TO_JL[attrs[:datatype]]
    if isnothing(arraysize) || arraysize == "1"
        basetype
    elseif occursin("x", arraysize)
        error("Multimensional arrays not supported yet")
    elseif basetype === Char
        @assert occursin(r"^[\d*]+$", arraysize)
        String
    else
        @assert occursin(r"^[\d*]+$", arraysize)
        Vector{basetype}
    end
end

jl2votype(::Type{Union{Missing, T}}) where {T} = jl2votype(T)
jl2votype(::Type{String}) = (datatype="char", arraysize="*")
jl2votype(::Type{Char}) = (datatype="char",)
jl2votype(::Type{Bool}) = (datatype="boolean",)
function jl2votype(T::Type)
    votypes = findall(==(T), TYPE_VO_TO_JL)
    isempty(votypes) && error("Don't know how to convert Julia type $T to a VOTable type")
    length(votypes) > 1 && error("Julia type $T maps to multiple VOTable types: $votypes")
    return (datatype=only(votypes),)
end

_parse(::Type{Union{Missing, T}}, s) where {T} = isempty(s) ? missing : _parse(T, s)
_parse(::Type{Union{Missing, T}}, s::Missing) where {T} = missing

_parse(::Type{T}, s) where {T} = parse(T, s)
_parse(::Type{Char}, s) = only(s)
_parse(::Type{String}, s) = s
function _parse(::Type{Bool}, s)
    first(s) in ('T', 't', '1') && return true
    first(s) in ('F', 'f', '0') && return false
    parse(Bool, s)
end

function _parse(::Type{T}, s) where {T <: Complex}
    re, im, rest... = split(s)
    @assert isempty(rest)
    complex(_parse(real(T), re), _parse(real(T), im))
end

_unparse(::Missing) = ""
_unparse(x::Complex) = "$(real(x)) $(imag(x))"
_unparse(x) = string(x)

# https://github.com/JuliaLang/julia/pull/50795
_filter(f, xs::NamedTuple)= xs[filter(k -> f(xs[k]), keys(xs))]

# XXX: should upstream to MetadataArrays
import DataAPI: metadata, metadatasupport, colmetadata, colmetadatasupport
metadatasupport(::Type{<:MetadataArray}) = (read=true, write=false)
metadata(ma::MetadataArray) = MetadataArrays.metadata(ma)

# XXX: should upstream to StructArrays
colmetadatasupport(::Type{<:StructArray}) = (read=true, write=false)
colmetadata(sa::StructArray, col::Symbol) = metadata(getproperty(sa, col))
colmetadata(sa::StructArray) =
    map(Tables.columns(sa)) do col
        metadatasupport(typeof(col)).read ? metadata(col) : nothing
    end



using PrecompileTools
@compile_workload begin
    read(joinpath(@__DIR__, "../test/data/alltypes"))
end

end
