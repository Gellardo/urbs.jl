module urbs

using JuMP
using ExcelReaders
using DataFrames

# for convenience
filename = normpath(Pkg.dir("urbs"), "test", "left-right.xlsx")

type Process
	site
	process_type
	"installed capacity at the beginning of the simulation"
	cap_init
	"minimal capacity"
	cap_min
	"maximal capacity"
	cap_max
	"fix cost per unit of installed capacity"
	cost_fix
	"variable cost per unit of generated unit of energy without commodities"
	cost_var
	"investment cost per unit of additional capacity"
	cost_inv
	"factor to balance long- and short term investments"
	annuity_factor
	"input-commodity"
	com_in
	"output-commodity"
	com_out
end

type Commodity
	name
	"commodity type, element of {\"Stock, SupIm\"}"
	com_type
	"ratio of input energy to resulting energy"
	ratio
	"price per MW"
	price
end

type Transmission
	"site on the \"left\" end of the transmission line"
	left
	"site on the \"right\" end of the transmission line"
	right
	"installed capacity at the beginning of the simulation"
	cap_init
	"minimal capacity"
	cap_min
	"maximal capcity"
	cap_max
	"fix cost per unit of installed capacity"
	cost_fix
	"variable cost per unit of generated unit of energy without commodities"
	cost_var
	"investment cost per unit of additional capacity"
	cost_inv
	"factor to balance long- and short term investments"
	annuity_factor
	"efficiency = E_out/E_in"
	efficiency
end

type Storage
	site
	storage_type
	# capacity/cost for for greater storage capacity
	cap_init_c
	cap_min_c
	cap_max_c
	cost_fix_c
	cost_var_c
	cost_inv_c
	# capacity/cost for for greater in/output power
	cap_init_p
	cap_min_p
	cap_max_p
	cost_fix_p
	cost_var_p
	cost_inv_p
	#other parameters
	annuity_factor
	efficiency_in
	efficiency_out
	fill_init
end

function read_xlsheet(file, sheetname; strict=true)
	try
		sheet = file.workbook[:sheet_by_name](sheetname)
		max_col = 'A' + sheet[:ncols] - 1
		readxl(DataFrame, file, string(sheetname, "!A1:", max_col, sheet[:nrows]),
		       header = true)
	catch XLRDError
		if !strict
			print("file ", file.filename, " does not contain sheet \"",
			      sheetname, "\"\n")
			return DataFrame()
		else
			throw(ErrorException(string("file ", file.filename,
			                            " does not contain sheet \"",
			                            sheetname, "\"\n")))
		end
	end
end

function append(array, element)
	if array != []
		[array; element]
	else
		[element]
	end
end

function calculate_annuity_factor(n, i)
	(1 + i)^n * i / ((1 + i)^n - 1)
end

function read_excelfile(filename, debug=false)
	file = openxl(filename)

	commodities = read_xlsheet(file, "Commodity")
	processes = read_xlsheet(file, "Process")
	processCommodity = read_xlsheet(file, "Process-Commodity")
	demand = read_xlsheet(file, "Demand")
	natural_commodities = read_xlsheet(file, "SupIm")

	sites = unique(processes[:, :Site])

	if debug
		println(commodities)
		println(processes)
		println(processCommodity)
		println(demand)
	end

	# build an array of Process
	process_array = []
	for i in 1:size(processes, 1)
		# not known yet: cost_com, com_in, com_out
		annuity_fac = 1
		if :wacc in names(processes) && :depreciation in names(processes)
			annuity_fac = calculate_annuity_factor(processes[i, :wacc],
			                                       processes[i,:depreciation])
		end
		next_process = Process(processes[i, :Site],
		                       processes[i, :Process],
		                       processes[i, Symbol("inst-cap")],
		                       processes[i, Symbol("cap-lo")],
		                       processes[i, Symbol("cap-up")],
		                       processes[i, Symbol("fix-cost")],
		                       processes[i, Symbol("var-cost")],
		                       processes[i, Symbol("inv-cost")],
		                       annuity_fac,
		                       Commodity("", "", 0, 0),
		                       Commodity("", "", 0, 0))
		if next_process.cap_min < next_process.cap_init
			print("warning: installed capacity bigger than minimal capacity")
			next_process.cap_min = next_process.cap_init
		end
		process_array = append(process_array, next_process)
	end

	# add commodities to the processes
	proc_com_rel = []
	for i in 1:size(processCommodity, 1)
		process_ind = find(x -> x.process_type == processCommodity[i, :Process],
		                   process_array)
		for i_process in process_ind
			process = process_array[i_process]
			commodity = Commodity(processCommodity[i, :Commodity],
			                      "",
			                      processCommodity[i, :ratio], 0)
			if processCommodity[i,:Direction] == "out"
				process.com_out = commodity
			else
				process.com_in = commodity
			end
		end
	end

	# add prices to input commodities
	com_array = []
	for i in 1:size(commodities, 1)
		process_ind = find(x -> x.site == commodities[i, :Site], process_array)
		for i_process in process_ind
			process = process_array[i_process]
			if process.com_in.name == commodities[i, :Commodity]
				process.com_in.com_type = commodities[i, :Type]
				if commodities[i, :Type] == "Stock"
					process.com_in.price = commodities[i, :price]
				end
			end
		end
	end

	transmissions = read_xlsheet(file, "Transmission"; strict=false)
	trans_array = []
	for trans in 1:size(transmissions,1)
		annuity_fac = 1
		if :wacc in names(processes) && :depreciation in names(processes)
			annuity_fac = calculate_annuity_factor(transmissions[trans, :wacc],
			                                       transmissions[trans, :depreciation])
		end
		next_trans = Transmission(transmissions[trans, Symbol("Site In")],
		                          transmissions[trans, Symbol("Site Out")],
		                          transmissions[trans, Symbol("inst-cap")],
		                          transmissions[trans, Symbol("cap-lo")],
		                          transmissions[trans, Symbol("cap-up")],
		                          transmissions[trans, Symbol("fix-cost")],
		                          transmissions[trans, Symbol("var-cost")],
		                          transmissions[trans, Symbol("inv-cost")],
		                          annuity_fac,
		                          transmissions[trans, Symbol("eff")])
		if next_trans.cap_min < next_trans.cap_init
			print("warning: cap-lo smaller than installed capacity")
			next_trans.cap_min = next_trans.cap_init
		end
		next_trans.cost_inv *= 0.5
		next_trans.cost_fix *= 0.5
		trans_array = append(trans_array, next_trans)
		# add the reverse way
		next_trans = deepcopy(next_trans)
		tmp = next_trans.left
		next_trans.left = next_trans.right
		next_trans.right = tmp
		trans_array = append(trans_array, next_trans)
	end

	storages = read_xlsheet(file, "Storage"; strict=false)
	sto_array = []
	for sto in 1:size(storages,1)
		annuity_fac = 1
		if :wacc in names(processes) && :depreciation in names(processes)
			annuity_fac = calculate_annuity_factor(storages[sto, :wacc],
			                                       storages[sto, :depreciation])
		end
		next_sto = Storage(storages[sto, Symbol("Site")],
		                    storages[sto, Symbol("Storage")],
		                    storages[sto, Symbol("inst-cap-c")],
		                    storages[sto, Symbol("cap-lo-c")],
		                    storages[sto, Symbol("cap-up-c")],
		                    storages[sto, Symbol("fix-cost-c")],
		                    storages[sto, Symbol("var-cost-c")],
		                    storages[sto, Symbol("inv-cost-c")],
		                    storages[sto, Symbol("inst-cap-p")],
		                    storages[sto, Symbol("cap-lo-p")],
		                    storages[sto, Symbol("cap-up-p")],
		                    storages[sto, Symbol("fix-cost-p")],
		                    storages[sto, Symbol("var-cost-p")],
		                    storages[sto, Symbol("inv-cost-p")],
		                    annuity_fac,
		                    storages[sto, Symbol("eff-in")],
		                    storages[sto, Symbol("eff-out")],
		                    storages[sto, Symbol("init")])
		if next_sto.cap_min_c < next_sto.cap_init_c
			print("warning: cap-lo-c smaller than installed capacity")
			next_sto.cap_min_c = next_sto.cap_init_c
		end
		if next_sto.cap_min_p < next_sto.cap_init_p
			print("warning: cap-lo-p smaller than installed capacity")
			next_sto.cap_min_p = next_sto.cap_init_p
		end
		sto_array = append(sto_array, next_sto)
	end

	sites, process_array, trans_array, sto_array, demand[:, 2:end], natural_commodities
end

function build_model(filename; timeseries = 0:0, debug = false)
	build_model(read_excelfile(filename)...;timeseries = timeseries, debug = debug)
end

function build_model(sites, processes, transmissions, storages, demand, natural_commodities;
	                 timeseries = 0:0, debug = false)
	# read
	if timeseries == 0:0
	    timeseries = 1:size(demand, 1)
	end
	numprocess = 1:size(processes,1)
	numsite = 1:size(sites,1)
	numtrans = 1:size(transmissions,1)

	if debug
	    println("read data")
	    println(timeseries)
	    println(sites)
	    println(processes)
	    println(demand)
	    println(transmissions)
	end

	# build model
	m = Model()

	#
	# Variables
	#
	@variable(m, cost)
	@objective(m, Min, cost)

	# process variables
	@variable(m, com_in[timeseries, numprocess] >= 0)
	@variable(m, com_out[timeseries, numprocess] >= 0)
	@variable(m, pro_through[timeseries, numprocess] >= 0)
	@variable(m, cap_avail[numprocess] >= 0)

	# transmission variables
	@variable(m, trans_cap[numtrans] >= 0)
	# assignment: each transmission consists of two directions i and i+1
	@variable(m, trans_in[timeseries, numtrans] >= 0)
	@variable(m, trans_out[timeseries, numtrans] >= 0)


	#
	# Constraints
	#

	# cost constraints
	@constraint(m, cost ==
	               # all commodity costs
	               sum{com_in[t, p] * processes[p].com_in.price,
	                   t = timeseries, p = numprocess} +
	               # investment costs process
	               sum{(cap_avail[p]-processes[p].cap_init) *
	                   processes[p].cost_inv * processes[p].annuity_factor,
	                   p = numprocess} +
	               # fix costs
	               sum{cap_avail[p] * processes[p].cost_fix, p = numprocess} +
	               # variable costs
	               sum{pro_through[t,p] * processes[p].cost_var,
	                   t = timeseries, p = numprocess} +

	               # transmission costs
	               sum{(trans_cap[tr] - transmissions[tr].cap_init) *
	                   transmissions[tr].cost_inv * transmissions[tr].annuity_factor,
	                   tr = numtrans} +
	               sum{trans_cap[tr] * transmissions[tr].cost_fix, tr = numtrans} +
	               sum{trans_in[t,tr] * transmissions[tr].cost_var,
	                   t = timeseries, tr = numtrans})

	# process constraints
	# assume that cap_inst <= cap_min
	@constraint(m, meet_cap_min[p = numprocess],
	               cap_avail[p] >= processes[p].cap_min)
	@constraint(m, meet_cap_max[p = numprocess],
	               cap_avail[p] <= processes[p].cap_max)

	# production constraints
	@constraint(m, commodity_in_to_through[t = timeseries, p = numprocess],
	               com_in[t, p] == pro_through[t, p] * processes[p].com_in.ratio)
	@constraint(m, commodity_out_to_through[t = timeseries, p = numprocess],
	               com_out[t, p] == pro_through[t, p] * processes[p].com_out.ratio)
	@constraint(m, check_cap[t = timeseries, p = numprocess],
	               pro_through[t,p] <= cap_avail[p])
	# for SupIm commodities com_in == available capacity * factor from timeseries
	@constraint(m, supim_com_in[t = timeseries, p = numprocess;
	                            processes[p].com_in.com_type == "SupIm"],
	               com_in[t, p] == cap_avail[p] *
	               natural_commodities[t, Symbol(string(processes[p].site,
	                                             '.', processes[p].com_in.name))])

	# transmission constraints
	@constraint(m, meet_trans_cap_bounds[tr = numtrans],
	               transmissions[tr].cap_min <= trans_cap[tr] <= transmissions[tr].cap_max)
	@constraint(m, ensure_symmetry[tr = numtrans; tr%2 == 0],
	               trans_cap[tr-1] == trans_cap[tr])

	@constraint(m, check_trans_cap[t = timeseries, tr = numtrans],
	               trans_in[t, tr] <= trans_cap[tr])
	@constraint(m, out_commidity[t = timeseries, tr = numtrans],
	               trans_out[t, tr] == trans_in[t, tr] * transmissions[tr].efficiency)

	# demand constraints
	@constraint(m, meet_demand[t = timeseries, s = 1:size(sites,1)],
	               demand[t, Symbol(string(sites[s],".Elec"))] ==
	               sum{com_out[t, p], p = numprocess;
	                   processes[p].site == sites[s]} +
	               sum{trans_out[t, tr], tr = numtrans;
	                   transmissions[tr].right == sites[s]} -
	               sum{trans_in[t, tr], tr = numtrans;
	                   transmissions[tr].left == sites[s]})

	return m
end

function solve_and_show(model)
	sites, processes, transmissions, storages, demand, natural_commodities = read_excelfile(filename)
	solve(model)
	println("Optimal Cost ", getobjectivevalue(model))
	println("Optimal Production by timestep and process")
	production = getvalue(getvariable(model,:pro_through))
	com_in = getvalue(getvariable(model,:com_in))
	capacities = getvalue(getvariable(model,:cap_avail))
	trans_in = getvalue(getvariable(model,:trans_in))

	function printhorizontal(prefix="", line=false)
		if line
			for p in 1:size(processes,1) + 1
				print("----\t")
			end
			println()
		end
		println(prefix)
	end

	# nice output tables
	print("\t")
	for p in 1:size(processes,1)
		print(processes[p].site[1:2], '.', processes[p].process_type[1:4], '\t')
	end
	println()
	printhorizontal("inv-cost", true)
	print("\t")
	for p in 1:JuMP.size(processes, 1)
		@printf("%.3f\t", (capacities[p] - processes[p].cap_init) * processes[p].cost_inv * processes[p].annuity_factor)
	end
	println()

	printhorizontal("fix-cost")
	print("\t")
	for p in 1:JuMP.size(processes, 1)
		@printf("%.3f\t", capacities[p] * processes[p].cost_fix)
	end
	println()

	printhorizontal("com-cost")
	print("\t")
	for p in 1:JuMP.size(processes, 1)
		sum = 0
		for t in 1:JuMP.size(production, 2)
			sum += com_in[t, p] * processes[p].com_in.price
		end
		@printf("%.3f\t", sum)
	end
	println()

	printhorizontal("var-cost")
	print("\t")
	for p in 1:JuMP.size(processes, 1)
		sum = 0
		for t in 1:JuMP.size(production, 2)
			sum += production[t,p] * processes[p].cost_var
		end
		@printf("%.3f\t", sum)
	end
	println()

	printhorizontal("cap", true)
	print("\t")
	for i in 1:JuMP.size(capacities, 1)
		@printf("%.3f\t", capacities[i])
	end
	println()

	printhorizontal("production per time", true)
	for i in 1:JuMP.size(production, 1)
		print(i, '\t')
		for j in 1:JuMP.size(production, 2)
			@printf("%.3f\t", production[i,j])
		end
		println()
	end
	print("sum\t")
	for p in 1:JuMP.size(production, 2)
		@printf("%.3f\t", sum(production[:,p]))
	end
	println()

	printhorizontal("transmissions", true)
	print('\t')
	for tr in 1:size(transmissions,1)
		print(transmissions[tr].left[1:2], "->", transmissions[tr].right[1:2], '\t')
	end
	println()

	for t in 1:JuMP.size(trans_in, 1)
		print(t, '\t')
		for tr in 1:JuMP.size(trans_in, 2)
			@printf("%.3f\t", trans_in[t,tr])
		end
		println()
	end
	print("sum\t")
	for tr in 1:JuMP.size(trans_in, 2)
		@printf("%.3f\t", sum(trans_in[:,tr]))
	end
	println()

end

end # module
