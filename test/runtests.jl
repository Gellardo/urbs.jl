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

function generateTransmissionPair(site1, site2; inv=0, fix=0, var=0)
	trans = urbs.Transmission(site1, site2, 0, 0, Inf, fix/2, var, inv/2, 1, 1)
	trans2 = deepcopy(trans)
	trans2.left, trans2.right = trans.right, trans.left
	[trans, trans2]
end

# write your own tests here
@test 1 == 1

# test process types
sites = ["A"]
demand = DataFrame(a = [1; 5])
rename!(x -> Symbol("A.Elec"), demand)
process = [urbs.Process(sites[1], "test", 1, 1, 10, 100, 10, 1000, 1, urbs.Commodity("coal", "Stock", 1, 1), urbs.Commodity("Elec", "", 1, 0))]
m = urbs.build_model(sites, process, [], [], demand, [])
urbs.solve(m)
@test 5 == m.variables["cap_avail"][1]
pro_through = m.variables["pro_through"]
@test [1;5] == pro_through.innerArray[:,1]
@test pro_through.innerArray == m.variables["com_in"].innerArray
@test 4566 == m.variables["objectivevalue"]

process, nat_com = getFreeNaturalProcess(sites[1]; timesteps=2)
process[1].cost_inv = 1000
process[1].cost_fix = 100
process[1].cost_var = 10
process[1].com_in = urbs.Commodity("wind", "SupIm", 1, 0)
nat_com[1][1] = 0.2
nat_com[1][2] = 1
m = urbs.build_model(sites, process, [], [], demand, nat_com)
urbs.solve(m)
@test 5 == m.variables["cap_avail"][1]
pro_through = m.variables["pro_through"]
@test [1;5] == pro_through.innerArray[:,1]
@test pro_through.innerArray == m.variables["com_in"].innerArray
@test 5560 == m.variables["objectivevalue"]


# test transmission
sites = ["A", "B"]
demand = DataFrame(a = [1; 5], b = [2; 4])
rename!(x -> x == :a ? Symbol("A.Elec") : Symbol("B.Elec"), demand)
process, nat_com = getFreeNaturalProcess(sites[1]; timesteps=2)
nat_com[:] = 1
transmissions = generateTransmissionPair(sites[1], sites[2]; inv = 1000, fix = 100, var = 10)
m = urbs.build_model(sites, process, transmissions, [], demand, nat_com)
urbs.solve(m)
@test 4460 == m.variables["objectivevalue"]


# test storage
sites = ["A"]
demand = DataFrame(a = [4; 5])
rename!(x -> Symbol("A.Elec"), demand)
process, nat_com = getFreeNaturalProcess("A"; timesteps=2)
nat_com[1][1]=1
power    = (0,0,Inf,10,0.5,100) #var-cost = 0.5 since it costs both ways (un-/loading)
capacity = (0,0,Inf,10000,1000,100000)
storage = [ urbs.Storage("A","sto", capacity..., power..., 1,1,1,0) ]
m = urbs.build_model(sites, process, [], storage, demand, nat_com)
urbs.solve(m)
@test 5 == m.variables["sto_cap_c"][1]
@test 5 == m.variables["sto_cap_p"][1]
@test 555555 == m.variables["objectivevalue"]


# test on whole file
filename = normpath(Pkg.dir("urbs"),"test", "left-right.xlsx")
m = urbs.build_model(filename)
urbs.solve(m)
@test isapprox(632.6, m.variables["objectivevalue"])
