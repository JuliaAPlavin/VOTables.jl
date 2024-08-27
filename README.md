# VOTables.jl

Support for the VOTable format (Virtual Observatory Table, [defined](https://www.ivoa.net/documents/VOTable/) by [IVOA](https://www.ivoa.net/)) in Julia.

Supports:
- ✅ Read VOTable files, both XML (`TABLEDATA`) and binary (`BINARY2`) formats
- ✅ Parse numbers, strings, datetimes (optional), units (optional, uses [Unitful.jl](https://github.com/PainterQubits/Unitful.jl))
- ✅ Extract column descriptions from VOTable files into Julia table metadata
- ✅ Write VOTable files

Does not support (yet):
- Some binary serialization formats: `FITS`, `BINARY`
- Multiple tables in a single file

See also: https://github.com/JuliaAstro/VOTables.jl, an older package with similar goals. That one was never registered in General, and the current `VOTables.jl` package is more performant and featureful.\
See also: [VirtualObservatory.jl](https://gitlab.com/aplavin/VirtualObservatory.jl) for integrations with online services following [Virtual Observatory](https://www.ivoa.net/) protocols.

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
To avoid compilation overhead, especially for very wide tables, can use `DictArray` instead (from [DictArrays.jl](https://gitlab.com/aplavin/DictArrays.jl)): `VOTables.read(DictArray, "tbl.vot")`.
