using urbs
using Base.Test
using JuMP

# write your own tests here
@test 1 == 1

filename = normpath(Pkg.dir("urbs"),"test", "left-right.xlsx")
m = urbs.build_model(filename)
solve(m)
@test 687 == getobjectivevalue(m)
