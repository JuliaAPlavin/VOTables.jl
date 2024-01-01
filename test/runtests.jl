using TestItems
using TestItemRunner
@run_package_tests


@testitem "_" begin
    import Aqua
    Aqua.test_all(VOTables; ambiguities=false)
    Aqua.test_ambiguities(VOTables)

    import CompatHelperLocal as CHL
    CHL.@check()
end
