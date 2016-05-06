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

function read_xlsheet(file, sheetname)
		sheet = file.workbook[:sheet_by_name](sheetname)
		max_col = 'A' + sheet[:ncols] - 1
		readxl(DataFrame, file, string(sheetname, "!A1:", max_col, sheet[:nrows]),
		       header = true)
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

	sites, process_array, demand[:, 2:end], natural_commodities
end

function build_model(filename; timeseries = 0:0, debug=false)
	# read
	sites, processes, demand, natural_commodities = read_excelfile(filename)
	if timeseries == 0:0
	    timeseries = 1:size(demand, 1)
	end
	numprocess = 1:size(processes,1)

	if debug
	    println("read data")
	    println(timeseries)
	    println(sites)
	    println(processes)
	    println(demand)
	end

	# build model
	m = Model()

	@variable(m, cost >=0)
	@variable(m, com_in[timeseries, numprocess] >= 0)
	@variable(m, production[timeseries, numprocess] >= 0)
	@variable(m, cap_avail[numprocess] >= 0)
	@objective(m, Min, cost)

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
	               sum{production[t,p] * processes[p].cost_var,
	                   t = timeseries, p = numprocess})

	# capacity constraints
	# assume that cap_inst <= cap_min
	@constraint(m, meet_cap_min[p = numprocess],
	               cap_avail[p] >= processes[p].cap_min)
	@constraint(m, meet_cap_max[p = numprocess],
	               cap_avail[p] <= processes[p].cap_max)

	# production constraints
	@constraint(m, commodity_to_production[t = timeseries, p = numprocess],
	               com_in[t, p] * processes[p].com_in.ratio == production[t, p])
	@constraint(m, check_cap[t = timeseries, p = numprocess],
	               production[t,p] <= cap_avail[p])
	# for SupIm commodities com_in == available capacity * factor from timeseries
	@constraint(m, supim_com_in[t = timeseries, p = numprocess;
	                            processes[p].com_in.com_type == "SupIm"],
	               com_in[t, p] == cap_avail[p] *
	               natural_commodities[t, Symbol(string(processes[p].site,
	                                             '.', processes[p].com_in.name))])

	# demand constraints
	@constraint(m, meet_demand[t = timeseries, s = 1:size(sites,1)],
	               demand[t, Symbol(string(sites[s],".Elec"))] ==
	               sum{production[t, p], p = numprocess;
	                   processes[p].site == sites[s]})

	return m
end

function solve_and_show(model)
	solve(model)
	println("Optimal Cost ", getobjectivevalue(model))
	println("Optimal Production by timestep and process")
	println(getValue(getVar(model,:production)))
end

end # module
