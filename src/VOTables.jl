module VOTables

using EzXML
using Base64
using StringViews
using UnsafeArrays: UnsafeArray
using StructArrays
using Tables
using Dictionaries
using MetadataArrays
using DataAPI: metadata, colmetadata
using DataPipes
using AccessorsExtra
using AstroAngles
using Dates
using DateFormats: yeardecimal, julian_day
using Logging
using Unitful: Unitful, Quantity, ustrip, NoUnits
using VOUnits: parse_unit, unit_string

export metadata, colmetadata

include("stringviews.jl")
include("xml.jl")
include("misc.jl")
include("metadata_piracy.jl")
include("votypes.jl")


"""    VOTables.read([result_type=StructArray], votfile; [postprocess=true], [unitful=true], [quiet=false])

Read a VOTable from a file or another `IO` object. By default, the result is a `StructArray`: a Julian collection and table. Alternatively, specify `result_type=StructArray`.

- `postprocess=true`: do further processing of values, other than parsing formal VOTable datatypes. Includes parsing dates and times, and converting units to `Unitful.jl`; set to `false` to disable all of this.
- `unitful=true`: parse units from VOTable metadata to `Unitful.jl` units. Ignores unknown units and shows warnings for them. Requires `postprocess=true`.
- `quiet=false`: silence all warnings and informational messages emitted during parsing.
"""
function read end

struct VOTableException <: Exception
    message::String
end

# basetype, jltype, nullvalue should probably be type-parametrized to achieve type stability in row processing code
Base.@kwdef struct ColMeta
    attrs::Dictionary{Symbol,String}
    basetype::DataType
    jltype::DataType
    typesize::Int8
    fixwidth::Union{Int32,Nothing}
    nullvalue
end

# support Cols()?
# support <COOSYS> tag

function _parse_timeorigin(s::AbstractString)
    s == "MJD-origin" && return 2400000.5
    s == "JD-origin" && return 0.0
    return parse(Float64, s)
end


function _resolve_timeorigin(attrs, timesys)
    ref = get(attrs, :ref, nothing)
    if !isnothing(ref) && haskey(timesys, ref)
        return timesys[ref]
    elseif length(timesys) == 1
        # ref must be specified, but in practice many files omit it
        # so, if there's only one TIMESYS, assume it's the one
        return only(values(timesys))
    else
        return 0.0
    end
end

read(votfile; kwargs...) = read(StructArray, votfile; kwargs...)

function read(result_type, votfile; postprocess=true, unitful=true, strict=true, quiet=false)
    with_logger(quiet ? NullLogger() : current_logger()) do
        io = votfile isa IO ? votfile : open(votfile)
        reader = EzXML.StreamReader(io)
        try
            colmetas, colnames, timesys, colarrays = _stream_header!(reader; strict)
            _filltable_stream!(colarrays, colmetas, reader; strict)
            @p let
                colarrays
                @modify(col -> any(ismissing, col) ? col : convert(Vector{nonmissingtype(eltype(col))}, col), __[∗])  # narrow types, removing Missing unless actually present
                postprocess ? modify(__, ∗, colmetas) do col, (;attrs)
                    timeorigin = _resolve_timeorigin(attrs, timesys)
                    postprocess_col(col, attrs; unitful, timeorigin)
                end : __
                modify(__, ∗, colmetas) do col, (;attrs)
                    MetadataArray(
                        col,
                        _filter(!isnothing, (
                            description=get(attrs, :description, nothing),
                            ucd=get(attrs, :ucd, nothing),
                            unit_vot=get(attrs, :unit, nothing)
                        )),
                    )
                end
                _container_from_components(result_type, colnames .=> __)
            end
        finally
            close(reader)
            votfile isa IO || close(io)
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


function _container_from_components(::Type{StructArray}, pairs)
    keys = map(first, pairs)
    vals = map(last, pairs)
    while !allunique(keys)
        renamed_keys = []
        for (i, key) in enumerate(keys)
            if any(==(key), keys[1:i-1])
                push!(renamed_keys, key)
                keys[i] = Symbol(string(key, "_"))
            end
        end
        @warn "Duplicate column names found. Repeating occurrences have `_` appended to them." renamed_keys
    end
    NamedTuple{Tuple(keys)}(Tuple(vals)) |> StructArray
end

function postprocess_col(col, attrs; unitful::Bool, timeorigin::Real=0)
    ucds = split(get(attrs, :ucd, ""), ";")
    unit = get(attrs, :unit, nothing)
    if "time.epoch" in ucds
        if eltype(col) <: AbstractString && unit == "'Y:M:D'"
            map(x -> parse(Date, x, dateformat"Y-m-d"), col)
        elseif eltype(col) <: Union{Real,AbstractArray{<:Real}} && unit == "d"
           	julianday_numarr(col, timeorigin)
        elseif eltype(col) <: Union{Real,AbstractArray{<:Real}} && unit == "yr"
            @warn "assuming years AD" column=attrs[:name] unit first(col)
            yeardecimal_numarr(col)
        elseif isnothing(unit)
            try
                map(x -> parse(Date, x, dateformat"Y-m-d"), col)
            catch exc
                @warn "unknown time unit" column=attrs[:name] unit eltype(col) first(col) exc
                col
            end
        else
            @warn "unknown time unit" column=attrs[:name] unit eltype(col) first(col)
            col
        end
    elseif "pos.eq.ra" in ucds && unit == "\"h:m:s\""
        hms2rad.(col)
    elseif "pos.eq.dec" in ucds && unit == "\"d:m:s\""
        dms2rad.(col)
    elseif unitful && !isnothing(unit)
        if eltype(col) <: Union{Number,AbstractArray{<:Number},Missing,Nothing}
            unit_vot_to_jl(col, unit)
        else
            @warn "column with a non-numeric eltype has a unit specified; ignoring the unit" column=attrs[:name] unit eltype(col) first(col)
            col
        end
    else
        col
    end
end

julianday_numarr(x::Number, timeorigin) = isnan(x) ? missing : julian_day(x + timeorigin)
julianday_numarr(x::AbstractArray, timeorigin) = map(v -> julianday_numarr(v, timeorigin), x)

yeardecimal_numarr(x::Number) = isnan(x) ? missing : yeardecimal(x)
yeardecimal_numarr(x::AbstractArray) = map(yeardecimal_numarr, x)

function unit_vot_to_jl(col, vot_unit::AbstractString)
    (;unit, valuefn) = parse_unit(vot_unit)
    unit === NoUnits && return col
    result = valuefn.(col) .* unit
    # broadcasting all-missing columns loses the numeric type (Missing .* u"m" → Vector{Missing}), fix it
    if Missing <: eltype(col)
        @assert eltype(col) !== Missing
        NMT = nonmissingtype(eltype(col))
        sample_val = NMT <: AbstractArray ? [one(eltype(NMT))] : one(NMT)
        QT = typeof(valuefn(sample_val) * unit)
        result = convert(Vector{Union{Missing, QT}}, result)
    end
    return result
end

function jl2votype(::Type{QT}) where {T, QT <: Quantity{T}}
    inner = jl2votype(T)
    return (inner..., unit=unit_string(Unitful.unit(QT)))
end

function jl2votype(::Type{GT}) where {T, GT <: Unitful.Gain{<:Any, <:Any, T}}
    inner = jl2votype(T)
    return (inner..., unit=unit_string(Unitful.logunit(GT)))
end

_unparse(x::Quantity) = _unparse(ustrip(x))
_unparse(x::Unitful.Gain) = _unparse(ustrip(x))

# XXX: piracy, need to upstream
Base.:*(::Missing, ::Unitful.MixedUnits) = missing

function _stream_header!(reader::EzXML.StreamReader; strict::Bool)
    # Process each expanded node immediately — expandtree() nodes are only valid
    # until the reader advances, so we extract all needed data in-place.
    colmetas = ColMeta[]
    timesys_entries = Pair{String,Float64}[]
    error_messages = String[]
    found_table = false

    for typ in reader
        typ == EzXML.READER_ELEMENT || continue
        nm = nodename_sv_reader(reader)
        if nm == "FIELD"
            node = expandtree(reader)
            push!(colmetas, _colmeta_from_node(node))
        elseif nm == "TIMESYS"
            node = expandtree(reader)
            id = node["ID"]
            timeorigin = haskey(node, "timeorigin") ? _parse_timeorigin(node["timeorigin"]) : 0.0
            push!(timesys_entries, id => timeorigin)
        elseif nm == "INFO"
            node = expandtree(reader)
            if haskey(node, "name") && haskey(node, "value") &&
               uppercase(node["name"]) == "QUERY_STATUS" && uppercase(node["value"]) == "ERROR"
                push!(error_messages, nodecontent(node))
            end
        elseif nm == "TABLE"
            found_table = true
        elseif nm == "DATA"
            break
        end
    end

    if !found_table && isempty(colmetas)
        if isempty(error_messages)
            error("VOTable file has no tables")
        else
            error("VOTable file has no tables, see original errors ($(length(error_messages))) below.\n$(join(error_messages, "\n\n"))")
        end
    end
    if !isempty(error_messages)
        strict ?
            throw(VOTableException("VOTable file contains data, but errors have occurred. Pass `strict=false` to turn this exception into a warning.\n$(join(error_messages, "\n\n"))")) :
            @error "VOTable file contains data, but errors have occurred. Pass `strict=true` to turn this warning into an exception." errors=error_messages
    end

    timesys = dictionary(timesys_entries)
    colnames = @p colmetas map(Symbol(_.attrs[:name]))
    colarrays = @p colmetas map(Union{_.jltype, Missing}[])

    return colmetas, colnames, timesys, colarrays
end

function _filltable_stream!(cols, colmetas, reader::EzXML.StreamReader; strict::Bool)
    # Detect format from first child element of DATA
    for typ in reader
        typ == EzXML.READER_ELEMENT || continue
        nm = nodename_sv_reader(reader)
        if nm == "TABLEDATA"
            _filltable_tabledata_stream!(cols, colmetas, reader)
            _check_trailing_errors!(reader; strict)
            return cols
        elseif nm ∈ ("BINARY", "BINARY2")
            format = Symbol(nm)
            # Find STREAM element and expand it
            for typ2 in reader
                typ2 == EzXML.READER_ELEMENT || continue
                nm2 = nodename_sv_reader(reader)
                if nm2 == "STREAM"
                    streamx = expandtree(reader)
                    _filltable_binary!(cols, colmetas, streamx, Val(format))
                    _check_trailing_errors!(reader; strict)
                    return cols
                end
            end
            error("No STREAM content found for BINARY/BINARY2 data")
        end
    end
    error("No DATA content found")
end

function _check_trailing_errors!(reader::EzXML.StreamReader; strict::Bool)
    error_messages = String[]
    for typ in reader
        typ == EzXML.READER_ELEMENT || continue
        nm = nodename_sv_reader(reader)
        if nm == "INFO"
            node = expandtree(reader)
            if haskey(node, "name") && haskey(node, "value") &&
               uppercase(node["name"]) == "QUERY_STATUS" && uppercase(node["value"]) == "ERROR"
                push!(error_messages, nodecontent(node))
            end
        end
    end
    if !isempty(error_messages)
        strict ?
            throw(VOTableException("VOTable file contains data, but errors have occurred. Pass `strict=false` to turn this exception into a warning.\n$(join(error_messages, "\n\n"))")) :
            @error "VOTable file contains data, but errors have occurred. Pass `strict=true` to turn this warning into an exception." errors=error_messages
    end
end

function _filltable_binary!(cols, colmetas, streamx, ::Val{:BINARY2})
    streamx["encoding"] == "base64" || error("Unsupported encoding: $(streamx["encoding"])")
    dataraw = nodecontent_sv(base64decode, streamx)
    nnullbytes = let ncols = length(colmetas)
        cld(ncols, 8)
    end
    i = 1
    while true
        i == length(dataraw) + 1 && break
        @assert i ≤ length(dataraw)
        nullbytes = @view dataraw[i:i+nnullbytes-1]
        i += nnullbytes
        for (icol, (col, colmeta)) in enumerate(zip(cols, colmetas))
            len = @something(
                colmeta.fixwidth,
                let
                    lenarray = @view dataraw[i:i+4-1]
                    i += 4
                    _parse_binary(Int32, lenarray) * colmeta.typesize
                end
            )
            curdata = @view dataraw[i:i+len-1]
            i += len
            if nth_bit(nullbytes[div(icol-1, 8)+1], 8-mod(icol-1, 8))
                push!(col, missing)
            else
                push!(col, _parse_binary(colmeta.jltype, curdata))
            end
        end
    end
    return cols
end

function _filltable_binary!(cols, colmetas, streamx, ::Val{:BINARY})
    streamx["encoding"] == "base64" || error("Unsupported encoding: $(streamx["encoding"])")
    dataraw = nodecontent_sv(base64decode, streamx)
    i = 1
    while true
        i == length(dataraw) + 1 && break
        @assert i ≤ length(dataraw)
        for (icol, (col, colmeta)) in enumerate(zip(cols, colmetas))
            len = @something(
                colmeta.fixwidth,
                let
                    lenarray = @view dataraw[i:i+4-1]
                    i += 4
                    _parse_binary(Int32, lenarray) * colmeta.typesize
                end
            )
            curdata = @view dataraw[i:i+len-1]
            i += len
            rawvalue = _parse_binary(colmeta.jltype, curdata)
            value = @something(if !ismissing(rawvalue)
                if rawvalue == colmeta.nullvalue
                    missing
                elseif rawvalue isa AbstractArray && all(ismissing, rawvalue)
                    missing
                end
            end, rawvalue)
            push!(col, value)
        end
    end
    return cols
end

function _filltable_tabledata_stream!(cols, colmetas, reader::EzXML.StreamReader)
    ncols = length(cols)
    col_idx = 0
    in_td = false

    for typ in reader
        if typ == EzXML.READER_ELEMENT
            nm = nodename_sv_reader(reader)
            if nm == "TR"
                col_idx = 0
            elseif nm == "TD"
                col_idx += 1
                if ccall((:xmlTextReaderIsEmptyElement, EzXML.libxml2), Cint, (Ptr{Cvoid},), reader) == 1
                    push!(cols[col_idx], _parse(eltype(cols[col_idx]), ""))
                else
                    in_td = true
                end
            end
        elseif typ ∈ (EzXML.READER_TEXT, EzXML.READER_CDATA) && in_td
            in_td = false
            col = cols[col_idx]
            content = nodevalue_sv_reader(reader)
            @multiifs(
                (Bool, UInt8, Char, String, Int16, Int32, Int64, Float32, Float64, ComplexF32, ComplexF64, Vector{Float64}),
                col isa AbstractVector{Union{Missing, _}},
                push!(col, _parse(eltype(col), content)),
                let
                    @warn "VOTable parsing can be slow due to runtime dispatch. Got eltype(col) == $(eltype(col)) that isn't handled by the fast path." maxlog=1
                    push!(col, _parse(eltype(col), content))
                end
            )
        elseif typ == EzXML.READER_SIGNIFICANT_WHITESPACE
            # whitespace-only text nodes (indentation) — ignore
        elseif typ == EzXML.READER_END_ELEMENT
            nm = nodename_sv_reader(reader)
            if nm == "TD"
                if in_td
                    col = cols[col_idx]
                    push!(col, _parse(eltype(col), ""))
                    in_td = false
                end
            elseif nm == "TABLEDATA"
                break
            end
        elseif typ ∈ (EzXML.READER_COMMENT, EzXML.READER_PROCESSING_INSTRUCTION)
            # standard XML constructs — ignore
        else
            @warn "Unexpected XML node type during TABLEDATA parsing" typ in_td maxlog=1
        end
    end
    return cols
end

description(tblxml) = @p let
    tblxml
    _findall("ns:DESCRIPTION", __, _namespaces(__))
    only
    nodecontent
end

function _colmeta_from_node(fieldxml::EzXML.Node)
    attrs = @p attributes(fieldxml) |> map(Symbol(nodename(_)) => nodecontent(_)) |> dictionary
    basetype = TYPE_VO_TO_JL[attrs[:datatype]]
    jltype = vo2jltype(attrs)
    typesize = TYPE_VO_TO_NBYTES[attrs[:datatype]]
    fixwidth = vo2nbytes_fixwidth(attrs)
    # Walk children directly (expandtree nodes don't support XPath)
    nullvalues = Any[]
    desc = nothing
    for child in eachelement(fieldxml)
        cname = nodename(child)
        if cname == "VALUES" && haskey(child, "null")
            val = try parse(basetype, child["null"]) catch err nothing end
            push!(nullvalues, val)
        elseif cname == "DESCRIPTION"
            desc = nodecontent(child)
        end
    end
    length(nullvalues) > 1 && @warn "Multiple null values found" column=attrs[:name] nullvalues
    nullvalue = @oget first(nullvalues)
    isnothing(desc) || insert!(attrs, :description, desc)
    return ColMeta(; attrs, basetype, jltype, typesize, fixwidth, nullvalue)
end

using PrecompileTools
@compile_workload begin
    read(joinpath(@__DIR__, "../test/data/alltypes"); unitful=false)
    read(joinpath(@__DIR__, "../test/data/alltypes"); unitful=true, quiet=true)  # quiet because uparse() fails in precompilation
end

end
