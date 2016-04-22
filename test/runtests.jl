using urbs
using Base.Test

# write your own tests here
@test 1 == 1

filename = normpath(Pkg.dir("urbs"),"test", "left-right.xlsx")
urbs.build_model(filename)
