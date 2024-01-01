module UnitfulExt

using Unitful
using VOTables.DataPipes
import VOTables: unit_viz_to_jl

function unit_viz_to_jl(col, viz::AbstractString)
    m = match(r"^log\(([^(]+)\)$", viz)
    viz, postf = if !isnothing(m)
        @warn "assuming 'log()' is the decimal logarithm" viz
        (m[1], exp10)
    else
        (viz, identity)
    end
    u = @p let
        viz
        replace(__,
            r"\bdeg\b" => "°",
            r"\b/beam\b" => (s -> (@warn "ignoring the unsupported 'beam' unit" viz; "")),
        )
        uparse(unit_context=Unitful.unitmodules)
    end
    return postf.(col) .* u
end

end
