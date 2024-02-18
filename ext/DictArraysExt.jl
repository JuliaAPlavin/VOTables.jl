module DictArraysExt

using DictArrays
using DictArrays.DataPipes
import VOTables: _container_from_components, Dictionary

_container_from_components(::Type{DictArray}, pairs) = @p pairs |> Dictionary(first.(__), last.(__)) |> DictArray

end
