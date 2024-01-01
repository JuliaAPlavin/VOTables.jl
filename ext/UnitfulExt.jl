module UnitfulExt

using Unitful
using VOTables.DataPipes
import VOTables: unit_viz_to_jl

function unit_viz_to_jl(col, viz::AbstractString)
    m = match(r"^(log\(|\[)([^([]+)(\)|\])$", viz)
    viz, postf = if !isnothing(m)
        @warn "assuming the decimal logarithm" viz
        (m[2], exp10)
    else
        (viz, identity)
    end
    u = try
        @p let
            viz
            replace(__,
                r"\bdeg\b" => "°",
                r"\barcsec\b" => "arcsecond",
                r"\barcmin\b" => "arcminute",
                r"\bum\b" => "μm",
                r"\b(/beam|electron)\b" => (s -> (@warn "ignoring the unsupported '$s' unit" viz; "")),)
            replace(__,
                r"^/" => "1/",)
            # handle eg "mas.yr-1":
            replace(__,
                r"(\w)\." => s"\1*",
                r"(\w)(-?\d)" => s"\1^\2")
            uparse(unit_context=Unitful.unitmodules, __)
        end
    catch exception
        @warn "cannot parse unit '$viz', ignoring it" exception
        return col
    end
    return postf.(col) .* u
end


# XXX: piracy, need to upstream
Base.:*(::Missing, ::Unitful.MixedUnits) = missing

end
