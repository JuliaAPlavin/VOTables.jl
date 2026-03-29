# VOTables.jl

Support for the VOTable format (Virtual Observatory Table, [defined](https://www.ivoa.net/documents/VOTable/) by [IVOA](https://www.ivoa.net/)) in Julia.

Supports:
- ✅ Read VOTable files
  - ✅ XML (`TABLEDATA`) and binary (`BINARY`, `BINARY2`) formats
  - 🚧 `FITS` format in VOTable
- 🚧 Multiple tables in a single file
- ✅ Decompressing on the fly: pass a `DecompressorStream` from [TranscodingStreams.jl](https://github.com/JuliaIO/TranscodingStreams.jl)
- ✅ Parse numbers, strings, datetimes, units (uses [VOUnits.jl](https://github.com/JuliaAPlavin/VOUnits.jl) and [Unitful.jl](https://github.com/PainterQubits/Unitful.jl))
- ✅ Extract column descriptions from VOTable files into Julia array metadata
- ✅ Write VOTable files


See also: https://github.com/JuliaAstro/VOTables.jl, an older package with similar goals. That one was never registered in General, and the current `VOTables.jl` package is more performant and featureful.\
See also: [VirtualObservatory.jl](https://github.com/JuliaAplavin/VirtualObservatory.jl) for integrations with online services following [Virtual Observatory](https://www.ivoa.net/) protocols.

# Usage

```julia
using VOTables

# only parse plain data types (numbers, strings) and datetimes:
tbl = VOTables.read("tbl.vot")

# also parse physical units:
using Unitful
tbl = VOTables.read("tbl.vot"; unitful=true)
```

The result is a `StructArray` be default, a Julia table with column-based storage. Whole columns can be accessed as `tbl.colname`, rows as `tbl[123]`, and individual values as `tbl.colname[123]` or `tbl[123].colname`.
To avoid compilation overhead, especially for very wide tables, can use `DictArray` instead (from [DictArrays.jl](https://github.com/JuliaAplavin/DictArrays.jl)): `VOTables.read(DictArray, "tbl.vot")`.
