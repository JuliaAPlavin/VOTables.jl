using TestItems
using TestItemRunner
@run_package_tests

@testitem "read 1" begin
    using Dates

    votgzfile = joinpath(@__DIR__, "data/votable?-source=J%2FApJ%2F923%2F67%2Ftable2&-out=**&-out.max=100.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile)
    @test length(tbl) == 100
    @test tbl.recno::Vector{Int32} == 1:100
    @test eltype(tbl.Tb) == Float32
    @test eltype(tbl.l_Tb) == Union{Missing,Char}
    @test tbl[5].Bpa === -9.1f0
    @test tbl[5].Epoch == Date(2008, 5, 1)
    @test tbl[5].Tb === 11.682f0

    using Unitful
    tbl = VOTables.read(votfile; unitful=true)
    @test tbl.recno::Vector{Int32} == 1:100
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
    @test tbl._key::Vector{Int16} == [1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5]
    @test tbl[1].var"BP-RP" === 1.127016f0
    @test tbl[3].logg === 4.4046f0

    tbl = VOTables.read(votfile; unitful=true)
    @test length(tbl) == 18
    @test tbl._key::Vector{Int16} == [1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5]
    @test tbl[1].var"BP-RP" === 1.127016f0u"mag"
    @test tbl[3].logg === 25386.342f0u"cm/s^2"
end

@testitem "read error" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/xmatch_error.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    VOTables.read(votfile)
end

@testitem "_" begin
    import Aqua
    Aqua.test_all(VOTables; ambiguities=false, unbound_args=false)
    Aqua.test_ambiguities(VOTables)

    import CompatHelperLocal as CHL
    CHL.@check()
end
