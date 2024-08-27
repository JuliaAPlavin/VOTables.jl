# put in some package? see ManualDispatch?
macro multiifs(vals, cond, body, elsebody=body)
    @assert Base.isexpr(vals, :tuple)
    vals = vals.args
    foldr(vals, init=elsebody) do val, prev
        curcond = modify(cond, RecursiveOfType(Symbol)) do sym
            sym == :_ ? val : sym
        end
        curbody = modify(body, RecursiveOfType(Symbol)) do sym
            sym == :_ ? val : sym
        end
        :(if $curcond
            $curbody
        else
            $prev
        end)
    end |> esc
end
