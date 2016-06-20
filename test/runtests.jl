using urbs
using Base.Test
using JuMP
using DataFrames

function getFreeNaturalProcess(site; timesteps=0)
	process = urbs.Process(site, "free", 0, 0, Inf, 0, 0, 0, 1, urbs.Commodity("wind", "SupIm", 1, 0), urbs.Commodity("Elec", "", 1, 0))
	nat_com = DataFrame(a = zeros(timesteps))
	rename!(x -> Symbol(string(site, ".wind")), nat_com)
	[process], nat_com
end

# write your own tests here
@test 1 == 1

# test storage
site = ["A"]
demand = DataFrame(a = [4; 5])
rename!(x -> Symbol("A.Elec"), demand)
process, nat_com = getFreeNaturalProcess("A"; timesteps=2)
nat_com[1][1]=1
power    = (0,0,Inf,10,0.5,100) #var-cost = 0.5 since it costs both ways (un-/loading)
capacity = (0,0,Inf,10000,1000,100000)
storage = [ urbs.Storage("A","sto", capacity..., power..., 1,1,1,0) ]
m = urbs.build_model(site, process, [], storage, demand, nat_com)
solve(m)
@test 5 == getvalue(getvariable(m, :sto_cap_c))[1]
@test 5 == getvalue(getvariable(m, :sto_cap_p))[1]
@test 555555 == getobjectivevalue(m)

# test on whole file
filename = normpath(Pkg.dir("urbs"),"test", "left-right.xlsx")
m = urbs.build_model(filename)
solve(m)
@test isapprox(632.6, getobjectivevalue(m))
