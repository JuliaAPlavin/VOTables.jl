using TestItems
using TestItemRunner
@run_package_tests


@testitem "unit parsing" begin
    # tested extensively in AstroUnitFormats, here just in case...
    using VOTables: unit_vot_to_jl
    using Unitful, UnitfulAngles, UnitfulAstro

    @test unit_vot_to_jl([1.0], "m") |> only === 1.0u"m"
    @test unit_vot_to_jl([1.0], "log(m)") |> only === 10.0u"m"
    @test unit_vot_to_jl([1.0], "[m]") |> only === 10.0u"m"
    @test unit_vot_to_jl([1.0], "Jy/pix") |> only === 1.0u"Jy"
    @test unit_vot_to_jl([1.0], "Jy/beam") |> only === 1.0u"Jy"
    @test unit_vot_to_jl([1.0], "electron.s") |> only === 1.0u"s"
    @test unit_vot_to_jl([1.0], "s.electron") |> only === 1.0u"s"
    @test unit_vot_to_jl([1.0], "m.s-1") |> only === 1.0u"m*s^-1"
    @test unit_vot_to_jl([1.0], "m.s**3") |> only === 1.0u"m*s^3"
    @test unit_vot_to_jl([1.0], "m.s**-3") |> only === 1.0u"m*s^-3"
    @test unit_vot_to_jl([1.0], "m.s2") |> only === 1.0u"m*s^2"
    @test unit_vot_to_jl([1.0], "m.s2.Hz-1") |> only === 1.0u"m*s^2*Hz^-1"
    @test unit_vot_to_jl([1.0], "W/deg") |> only === 1.0u"W*°^-1"
    @test unit_vot_to_jl([1.0], "W/arcsec") |> only === 1.0u"W*arcsecond^-1"
    @test unit_vot_to_jl([1.0], "W/arcmin") |> only === 1.0u"W*arcminute^-1"
    @test unit_vot_to_jl([1.0], "W/um") |> only === 1.0u"W*μm^-1"
    @test unit_vot_to_jl([1.0], "[W/um]") |> only === 10.0u"W*μm^-1"
    @test unit_vot_to_jl([1.0], "angstrom") |> only === 1.0u"Å"
    @test unit_vot_to_jl([1.0], "Angstrom") |> only === 1.0u"Å"
    @test unit_vot_to_jl([1.0], "solRad") |> only === 1.0u"Rsun"
    @test unit_vot_to_jl([1.0], "solLum") |> only === 1.0u"Lsun"
    @test unit_vot_to_jl([1.0], "solMass") |> only === 1.0u"Msun"
    @test unit_vot_to_jl([1.0], "") |> only === 1.0
end

@testitem "read 1" begin
    using Dates
    using DictArrays, StructArrays
    using StructArrays.Tables

    votgzfile = joinpath(@__DIR__, "data/votable_compressed.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile; unitful=false)
    @test length(tbl) == 100
    @test tbl.recno::AbstractVector{Int32} == 1:100
    @test eltype(tbl.Tb) == Float32
    @test eltype(tbl.l_Tb) == Union{Missing,Char}
    @test tbl[5].Bpa === -9.1f0
    @test tbl[5].Epoch == Date(2008, 5, 1)
    @test tbl[5].Tb === 11.682f0
    @test tbl.ID[1:20:100] == ["0003+380", "0003-066", "0006+061", "0007+106", "0011+189"]

    # @test metadata(tbl) == (description=...,)
    @test metadata(tbl.Epoch) == (description = "Epoch", ucd = "time.epoch", unit_vot = "'Y:M:D'")
    @test colmetadata(tbl, :Epoch) == metadata(tbl.Epoch)
    @test colmetadata(tbl, :ID) == (description = "Source name in truncated B1950.0 coordinates", ucd = "meta.id;meta.main")
    @test colmetadata(tbl)[:Epoch] == colmetadata(tbl, :Epoch)

    @test isequal(Tables.columns(VOTables.read(DictArray, votfile; unitful=false)), Tables.columns(DictArray(tbl)))
    @test isequal(Tables.columns(VOTables.read(StructArray, votfile; unitful=false)), Tables.columns(tbl))

    using Unitful
    tbl = VOTables.read(votfile; unitful=true)
    @test tbl.recno::AbstractVector{Int32} == 1:100
    @test tbl[5].Epoch == Date(2008, 5, 1)
    @test tbl[5].Tb === (10^11.682f0)u"K"
    # @test tbl[5].Bmaj == 0.82f0  # only passes with ]test, fails in VSCode test runner

    using UnitfulAstro, UnitfulAngles
    tbl = VOTables.read(votfile; unitful=true)
    @test tbl[5].Epoch == Date(2008, 5, 1)
    @test tbl[5].Tb === (10^11.682f0)u"K"
    @test tbl[5].Bmaj == 0.82f0u"mas"
end

@testitem "read 2" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/xmatch_gaia.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile; unitful=false)
    @test length(tbl) == 18
    @test tbl._key::AbstractVector{Int16} == [1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5]
    @test tbl[1].var"BP-RP" === 1.127016f0
    @test tbl[3].logg === 4.4046f0

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 18
    @test tbl._key::AbstractVector{Int16} == [1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5]
    @test tbl[1].var"BP-RP" === 1.127016f0u"mag"
    @test tbl[3].logg === 25386.342f0u"cm/s^2"
end

@testitem "read 3" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/2mass.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile; unitful=false)
    @test length(tbl) == 5
    @test tbl[1].errPA == 76
    @test tbl[1].JD == DateTime(1998, 9, 28, 7, 20, 55, 680)

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 5
    @test tbl[1].errPA == 76u"°"
    @test tbl[1].JD == DateTime(1998, 9, 28, 7, 20, 55, 680)
end

@testitem "read 4" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/jetdirs.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile; unitful=false)
    @test length(tbl) == 88
    @test tbl[1].Freq === "8"
    @test tbl[1].PA === Int16(-105)

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 88
    @test tbl[1].Freq === "8"
    @test tbl[1].PA === Int16(-105)u"°"
end

@testitem "read 5" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    # time is of "double" type, but Y:M:D format is given
    votfile = joinpath(@__DIR__, "data/weird_mix")

    tbl = VOTables.read(votfile; unitful=false)
    @test length(tbl) == 1
    @test tbl.recno::AbstractVector{Int32} == [10]
    @test tbl[1].Epoch == 2.456516e6
    @test tbl.ID[1] == "0003+380"
    @test tbl[1].Tb === 11.713

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 1
    @test tbl[1].Tb === (5.1641636927207e11)u"K"
end

@testitem "read 6" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votfile = joinpath(@__DIR__, "data/gaia")

    tbl = VOTables.read(votfile; unitful=false)
    @test length(tbl) == 5
    @test tbl[1].dec_error == 0.10277003f0

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 5
    @test tbl[1].dec_error == 0.10277003f0u"mas"
end

@testitem "read 7" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/ned_sed.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile; unitful=false)
    @test length(tbl) == 629
    @test tbl[1].DataFluxValue == 1.07e-15

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 629
    @test tbl[1].DataFluxValue == 1.07e-15u"Jy"
end

@testitem "read 8" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/vectorcol.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile; unitful=false)
    @test length(tbl) == 5
    @test tbl[1].energy_bounds_samples == [2e-7, 1.1e-6]
    @test tbl[1].obsID == "00000000-0000-0000-b65e-840e6d24aa6d"
    @test tbl[1].obsID_ == "00000000-0000-0000-b65e-840e6d24aa6d"
    @test tbl[1].lastModified == "2021-11-05T18:38:44.060"
    @test tbl[1].lastModified_ == "2021-11-05T18:38:44.060"

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 5
    @test tbl[5].energy_bounds_samples == [4.994e-7, 5.05e-7]*u"m"
    @test tbl[5].energy_bounds_lower == 4.994e-7u"m"
    @test tbl[5].obsID == "00000000-0000-0000-a22d-31527058196f"
    @test tbl[5].obsID_ == "00000000-0000-0000-a22d-31527058196f"
end
@testitem "read binary" begin
    votgzfile = joinpath(@__DIR__, "data/binary.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile)
    @test length(tbl) == 49
    @test isequal(tbl[12], (db_table_name = missing, description = missing, schema_name = "hsc_v2", size = 90751872, size_bytes = 52785233920, table_index = -1, table_name = "hsc_v2.hubble_sc2", table_type = "table", utype = missing))
end

@testitem "read binary - eltypes" begin
    tbl = VOTables.read(joinpath(@__DIR__, "data/test-binary2.vot"))
    @test length(tbl) == 10
    @test isequal(tbl.s_short, [0, 1, missing, 3, 4, 5, 6, 7, 8, 9])
    @test isequal(tbl.s_boolean, [false, true, false, true, false, true, false, true, missing, true])
    @test isequal(tbl[3], (s_byte=2, s_short=missing, s_int=2, s_long=2, s_float=2.0f0, s_double=2.0, s_string="two", s_boolean=false, f_byte=[2, 3, 4], f_short=missing, f_int=[2, 3, 4], f_long=[2, 3, 4], f_float=[2, NaN, 4.5], f_double=[2,NaN, 4.5], f_boolean=[false, true, false], v_byte=[2], v_short=missing, v_int=[2], v_long=[2], v_float=[2], v_double=[2], v_boolean=[false], m_int=[1002, 1003, 2002, 2003, 3002, 3003, 4002, 4003], m_double=missing))
end

@testitem "read arrays with units" begin
    using Unitful, UnitfulAstro
    using Dates
    votgzfile = joinpath(@__DIR__, "data/gaia_datalink_multiple.vot.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))
    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 5
    @test tbl.g_transit_time[1] isa Vector{Union{Missing, DateTime}}
    @test tbl.g_transit_flux[1] isa Vector{typeof(1.0u"s^-1")}
    @test length(tbl.g_transit_time[1]) == 50
    @test length(tbl.g_transit_flux[1]) == 50
    @test tbl.g_transit_time[1][1] == DateTime("2014-08-08T16:12:54.464")
    @test tbl.g_transit_flux[1][1] ≈ 213.96326742986244u"s^-1"
end

@testitem "quiet option" begin
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/votable_compressed.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    # with quiet=true: no messages
    @test_logs VOTables.read(votfile; unitful=true, quiet=true)
end

@testitem "read error" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/xmatch_error.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    @test_throws "not in the service" VOTables.read(votfile)
    @test_throws "Incorrect ADQL query" VOTables.read(joinpath(@__DIR__, "data/tap_error"))
    
    @test_throws "Maximum execution time" VOTables.read(joinpath(@__DIR__, "data/tap_results_and_error"))
    tbl = @test_warn "Maximum execution time" VOTables.read(joinpath(@__DIR__, "data/tap_results_and_error"); strict=false)
    @test length(tbl) == 5
end

@testitem "read formats consistency" begin
    # These files are written (using STILTS) by a script in the data directory.
    # They have different serializations but, as far as possible,
    # identical content.
    files = map(fmt -> joinpath(@__DIR__, "data/test-$fmt.vot"), ["tabledata", "binary2", "binary"])
    tables = VOTables.read.(files)
    @test length(tables) == 3
    basetbl = tables[1]
    @testset for i in 1:length(tables)
        isBINARY = i == 3
        tbl = tables[i]
        @test length(tbl) == 10
        @test propertynames(tbl) == propertynames(basetbl)
        @testset for p in propertynames(tbl)
            col = getproperty(tbl, p)
            basecol = getproperty(basetbl, p)
            if eltype(col) <: Union{Missing,AbstractString}
                @test isequal(coalesce.(col, ""), coalesce.(basecol, ""))
            elseif eltype(col) <: Union{Missing,AbstractFloat}
                @test isequal(coalesce.(col, NaN), coalesce.(basecol, NaN))
            elseif eltype(col) <: Union{Missing,AbstractArray}
                squashempty(a) = a -> ismissing(a) || isempty(a) ? missing : a
                @test isequal(map(squashempty, col), map(squashempty, basecol))
            else
                @test isequal(col, basecol)
            end
        end
    end
end

@testitem "read complex binary" begin
    # Binary data generated by STILTS from the TABLEDATA source file.
    # Tests that floatComplex/doubleComplex are parsed correctly in BINARY/BINARY2 formats.
    files = map(fmt -> joinpath(@__DIR__, "data/complex-$fmt.vot"), ["tabledata", "binary", "binary2"])
    tables = VOTables.read.(files)
    basetbl = tables[1]
    @testset for tbl in tables
        @test length(tbl) == 3
        @test tbl.s_floatComplex == basetbl.s_floatComplex
        @test tbl.s_doubleComplex == basetbl.s_doubleComplex
        @test tbl.s_float == basetbl.s_float
        @test tbl.s_double == basetbl.s_double
    end
end

@testitem "write" begin
    using StructArrays.Tables
    using DictArrays, StructArrays
    using Unitful, UnitfulAngles, UnitfulAstro

    f = tempname()
    for tbl in [
        (a=[1,2,3], b=["xx", "y", "zzz"],),
        (a=[1.,3.,2.], b=["xx", "y", missing],),
        (bool=[false], u8=[UInt8(12)], ch=['a'], str=["xyz"], i16=[Int16(123)], i32=[Int32(123)], i64=[Int64(123)], f32=[Float32(1.23)], f64=[Float64(1.23)], f32c=[ComplexF32(1.23, 4.56)], f64c=[ComplexF64(1.23, 4.56)],),
        (vf64=[[1.0, 2.0], [3.0, 4.0, 5.0], [6.0]], vi32=[Int32[10, 20], Int32[30], Int32[40, 50, 60]], vbool=[[true, false], [true], [false, true, false]]),
        (a=[1u"m"], b=[1u"°"], c=[1u"arcsecond/m^2"]),
        (mag=[1.0f0u"mag", 2.5f0u"mag", 3.1f0u"mag"],),
    ]
        tbl_c = tbl |> Tables.columntable
        @testset for tbl_f in (identity, rowtable, StructArray, DictArray)
            @testset "file" begin
                tbl |> tbl_f |> VOTables.write(f)
                read_c = VOTables.read(f; unitful=true) |> Tables.columntable
                @test isequal(read_c, tbl_c)
                @test map(eltype, read_c) == map(eltype, tbl_c)
            end

            @testset "iobuffer" begin
                iob = IOBuffer()
                tbl |> tbl_f |> VOTables.write(iob)
                seekstart(iob)
                read_c = VOTables.read(iob; unitful=true) |> Tables.columntable
                @test isequal(read_c, tbl_c)
                @test map(eltype, read_c) == map(eltype, tbl_c)
            end
        end
    end

    @testset "pure-missing column" begin
        tbl = (a=[missing, missing, missing],)
        tbl |> VOTables.write(f)
        read_c = VOTables.read(f) |> Tables.columntable
        @test all(ismissing, read_c.a)
        @test_broken eltype(read_c.a) === Missing
    end

    @testset "pure-missing empty column" begin
        tbl = (a=Missing[],)
        tbl |> VOTables.write(f)
        read_c = VOTables.read(f) |> Tables.columntable
        @test isempty(read_c.a)
        @test_broken eltype(read_c.a) === Missing
    end

    @testset "Union{Missing, Float64} column" begin
        @testset "all missing" begin
            tbl = (a=Union{Missing, Float64}[missing, missing, missing],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f; unitful=true) |> Tables.columntable
            @test all(ismissing, read_c.a)
            @test eltype(read_c.a) === Union{Missing, Float64}
        end
        @testset "all present" begin
            tbl = (a=Union{Missing, Float64}[1.0, 2.0, 3.0],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f; unitful=true) |> Tables.columntable
            @test read_c.a == [1.0, 2.0, 3.0]
            @test eltype(read_c.a) === Float64
        end
        @testset "empty" begin
            tbl = (a=Union{Missing, Float64}[],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f; unitful=true) |> Tables.columntable
            @test isempty(read_c.a)
            @test_broken eltype(read_c.a) === Union{Missing, Float64}
        end
    end

    @testset "Union{Missing, unitful} column" begin
        @testset "all missing" begin
            tbl = (a=Union{Missing, typeof(1.0u"m")}[missing, missing],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f; unitful=true) |> Tables.columntable
            @test all(ismissing, read_c.a)
            @test eltype(read_c.a) === Union{Missing, typeof(1.0u"m")}
        end
        @testset "all present" begin
            tbl = (a=Union{Missing, typeof(1.0u"m")}[1.0u"m", 2.0u"m"],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f; unitful=true) |> Tables.columntable
            @test read_c.a == [1.0u"m", 2.0u"m"]
            @test eltype(read_c.a) === typeof(1.0u"m")
        end
        @testset "empty" begin
            tbl = (a=Union{Missing, typeof(1.0u"m")}[],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f; unitful=true) |> Tables.columntable
            @test isempty(read_c.a)
            @test_broken eltype(read_c.a) === Union{Missing, typeof(1.0u"m")}
        end
    end

    @testset "Union{Missing, Vector{Float64}} column" begin
        @testset "all missing" begin
            tbl = (a=Union{Missing, Vector{Float64}}[missing, missing],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f) |> Tables.columntable
            @test all(ismissing, read_c.a)
            @test eltype(read_c.a) === Union{Missing, Vector{Float64}}
        end
        @testset "all present" begin
            tbl = (a=Union{Missing, Vector{Float64}}[[1.0, 2.0], [3.0, 4.0, 5.0]],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f) |> Tables.columntable
            @test read_c.a == [[1.0, 2.0], [3.0, 4.0, 5.0]]
            @test eltype(read_c.a) === Vector{Float64}
        end
        @testset "empty" begin
            tbl = (a=Union{Missing, Vector{Float64}}[],)
            tbl |> VOTables.write(f)
            read_c = VOTables.read(f) |> Tables.columntable
            @test isempty(read_c.a)
            @test_broken eltype(read_c.a) === Union{Missing, Vector{Float64}}
        end
    end

    using Dates
    @testset "Date/DateTime" begin
        tbl = (d=[Date(2020, 1, 15), Date(2021, 6, 30)], dt=[DateTime(2020, 1, 15, 12, 30), DateTime(2021, 6, 30, 0, 0)])
        tbl |> VOTables.write(f)
        read_c = VOTables.read(f) |> Tables.columntable
        @test read_c.d == DateTime.(tbl.d)
        @test read_c.dt == tbl.dt
    end
end

@testitem "_" begin
    import Aqua
    Aqua.test_all(VOTables; ambiguities=false, unbound_args=false, piracies=false)
    Aqua.test_ambiguities(VOTables)

    import CompatHelperLocal as CHL
    CHL.@check()
end
