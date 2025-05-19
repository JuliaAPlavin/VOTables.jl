module UnitfulExt

using Unitful
using VOTables.DataPipes
import VOTables: unit_vot_to_jl, jl2votype, _unparse

function unit_vot_to_jl(col, vot_unit::AbstractString)
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
            
            # Handle empty vot_unit string
            if isempty(__)
                NoUnits
            else
                uparse(unit_context=[Unitful; Unitful.unitmodules], __)
            end
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

jl2votype(::Type{QT}) where {T, QT <: Quantity{T}} = error("Writing unitful values not supported yet")
_unparse(x::Quantity) = _unparse(ustrip(x))

# XXX: piracy, need to upstream
Base.:*(::Missing, ::Unitful.MixedUnits) = missing

end
