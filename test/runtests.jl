using TestItems
using TestItemRunner
@run_package_tests

@testitem "read 1" begin
    using Dates
    using DictArrays, StructArrays
    using StructArrays.Tables

    votgzfile = joinpath(@__DIR__, "data/votable?-source=J%2FApJ%2F923%2F67%2Ftable2&-out=**&-out.max=100.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile)
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

    @test isequal(Tables.columns(VOTables.read(DictArray, votfile)), Tables.columns(tbl))
    @test isequal(Tables.columns(VOTables.read(StructArray, votfile)), Tables.columns(StructArray(tbl)))

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

    tbl = VOTables.read(votfile)
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

    tbl = VOTables.read(votfile)
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

    tbl = VOTables.read(votfile)
    @test length(tbl) == 88
    @test tbl[1].Freq === "8"
    @test tbl[1].PA === Int16(-105)

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 88
    @test tbl[1].Freq === "8"
    @test tbl[1].PA === Int16(-105)u"°"
end

@testitem "read error" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/xmatch_error.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    @test_throws "not in the service" VOTables.read(votfile)
    @test_throws "Incorrect ADQL query" VOTables.read(joinpath(@__DIR__, "data/tap_error"))
end

@testitem "write" begin
    using StructArrays.Tables
    using Unitful, UnitfulAngles

    for tbl in [
        (a=[1,2,3], b=["xx", "y", "zzz"],),
        (a=[1.,3.,2.], b=["xx", "y", missing],),
        (bool=[false], u8=[UInt8(12)], ch=['a'], str=["xyz"], i16=[Int16(123)], i32=[Int32(123)], i64=[Int64(123)], f32=[Float32(1.23)], f64=[Float64(1.23)], f32c=[ComplexF32(1.23, 4.56)], f64c=[ComplexF64(1.23, 4.56)],),
        # (a=[1u"m"], b=[1u"°"], c=[1u"arcsecond/m^2"]),
    ]
        f = tempname()
        tbl |> VOTables.write(f)
        tbl_c = tbl |> Tables.columntable
        read_c = VOTables.read(f; unitful=true) |> Tables.columntable
        @test isequal(read_c, tbl_c)
        @test map(eltype, read_c) == map(eltype, tbl_c)
    end
end

@testitem "_" begin
    import Aqua
    Aqua.test_all(VOTables; ambiguities=false, unbound_args=false, piracy=false)
    Aqua.test_ambiguities(VOTables)

    import CompatHelperLocal as CHL
    CHL.@check()
end
