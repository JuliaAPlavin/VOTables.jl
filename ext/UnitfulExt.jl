module UnitfulExt

using Unitful
using VOTables.DataPipes
import VOTables: unit_vot_to_jl, unit_jl_to_vot, jl2votype, _unparse

function unit_vot_to_jl(col, vot_unit::AbstractString)
    isempty(vot_unit) && return col
    m = match(r"^(log\(|\[)([^([]+)(\)|\])$", vot_unit)
    vot_unit, postf = if !isnothing(m)
        @info "assuming the decimal logarithm" vot_unit
        (m[2], exp10)
    else
        (vot_unit, identity)
    end
    u = try
        @p let
            vot_unit
            replace(__,
                r"\b(/beam|/pix|electron)\b" => (s -> (@warn "ignoring the unsupported '$s' unit" vot_unit; "")),
                "'" => "",  # XXX: shouldn't have arcminutes described this way?
            )
            replace(__,
                r"^/" => "1/",
                r"/$" => "",
                r"^\." => "",
                r"\.$" => "",
                r"([^*])\*\*([^*])" => s"\1^\2",  # XXX: should be tested
            )
            
            # handle eg "mas.yr-1":
            replace(__, r"(\w)\." => s"\1*")
            replace(__, r"(\w)(-?\d)" => s"\1^\2")

            replace(__,
                r"\bdeg\b" => "°",
                r"\barcsec\b" => "arcsecond",
                r"\barcmin\b" => "arcminute",
                r"\bum\b" => "μm",
                r"\bAngstrom\b" => "angstrom")
            uparse(unit_context=[Unitful; Unitful.unitmodules], __)
        end
    catch exception
        if exception isa ArgumentError && occursin("could not be found in unit modules", exception.msg)
            @warn "cannot parse unit '$vot_unit', ignoring it"
        else
            @warn "cannot parse unit '$vot_unit', ignoring it" exception
        end
        return col
    end
    return postf.(col) .* u
end

function jl2votype(::Type{QT}) where {T, QT <: Quantity{T}}
    inner = jl2votype(T)
    u = unit_jl_to_vot(Unitful.unit(QT))
    return (inner..., unit=u)
end

function jl2votype(::Type{GT}) where {T, GT <: Unitful.Gain{<:Any, <:Any, T}}
    inner = jl2votype(T)
    u = unit_jl_to_vot(Unitful.logunit(GT))
    return (inner..., unit=u)
end

const SUPERSCRIPT_MAP = Dict('⁰'=>'0','¹'=>'1','²'=>'2','³'=>'3','⁴'=>'4','⁵'=>'5','⁶'=>'6','⁷'=>'7','⁸'=>'8','⁹'=>'9','⁻'=>'-')

function unit_jl_to_vot(u::Union{Unitful.Units, Unitful.MixedUnits})
    s = string(u)
    s = replace(s, "°" => "deg", "″" => "arcsec", "′" => "arcmin", "μm" => "um")
    s = replace(s, r"[⁰¹²³⁴⁵⁶⁷⁸⁹⁻]+" => m -> join(SUPERSCRIPT_MAP[c] for c in m))
    s = replace(s, " " => ".")
    return s
end
_unparse(x::Quantity) = _unparse(ustrip(x))
_unparse(x::Unitful.Gain) = _unparse(ustrip(x))

# XXX: piracy, need to upstream
Base.:*(::Missing, ::Unitful.MixedUnits) = missing

end
