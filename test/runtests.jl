using TestItems
using TestItemRunner
@run_package_tests

@testitem "read" begin
    using Dates
    using Unitful, UnitfulAstro, UnitfulAngles

    votgzfile = joinpath(@__DIR__, "data/votable?-source=J%2FApJ%2F923%2F67%2Ftable2&-out=**&-out.max=100.gz")
    votfile = tempname()
    run(pipeline(`gunzip -ck $votgzfile`, stdout=votfile))

    tbl = VOTables.read(votfile)
    @test length(tbl) == 100
    @test tbl.recno == 1:100
    @test eltype(tbl.Tb) == Float32
    @test eltype(tbl.l_Tb) == Union{Missing,Char}
    @test tbl[5].Bpa === -9.1f0
    @test tbl[5].Epoch == Date(2008, 5, 1)
    @test tbl[5].Tb === 11.682f0

    tbl = VOTables.read(votfile; unitful=true)
    @test tbl.recno == 1:100
    @test eltype(tbl.l_Tb) == Union{Missing,Char}
    @test tbl[5].Epoch == Date(2008, 5, 1)
    @test tbl[5].Tb ≈ (10^11.682f0)u"K"
end

@testitem "_" begin
    import Aqua
    Aqua.test_all(VOTables; ambiguities=false, unbound_args=false)
    Aqua.test_ambiguities(VOTables)

    import CompatHelperLocal as CHL
    CHL.@check()
end
