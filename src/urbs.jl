module urbs

using JuMP
using ExcelReaders
using DataFrames

filename = normpath(Pkg.dir("urbs"), "test", "left-right.xlsx")

type Process
	site
	process_type
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
	"transient variable for the commodity cost of one generated unit of energy"
	cost_com
	"array of input-commodities"
	com_in
	"array of output-commodities"
	com_out
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

function read_excelfile(filename, debug=false)
	file = openxl(filename)

	commodities = read_xlsheet(file, "Commodity")
	processes = read_xlsheet(file, "Process")
	processCommodity = read_xlsheet(file, "Process-Commodity")
	demand = read_xlsheet(file, "Demand")

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
		next_process = Process(processes[i, :Site],
		                       processes[i, :Process],
		                       processes[i, Symbol("inst-cap")],
		                       processes[i, Symbol("cap-lo")],
		                       processes[i, Symbol("cap-up")],
		                       processes[i, Symbol("fix-cost")],
		                       processes[i, Symbol("var-cost")],
		                       processes[i, Symbol("inv-cost")],
		                       0, [], [])
		process_array = append(process_array, next_process)
	end

	# add commodities to the processes
	proc_com_rel = []
	for i in 1:size(processCommodity, 1)
		process_ind = find(x -> x.process_type == processCommodity[i, :Process],
		                   process_array)
		for i_process in process_ind
			process = process_array[i_process]
			commodity_tuple = (processCommodity[i, :Commodity],
			                   processCommodity[i, :ratio])
			if processCommodity[i,:Direction] == "out"
				process.com_out = append(process.com_out, commodity_tuple)
			else
				process.com_in = append(process.com_in, commodity_tuple)
			end
		end
	end

	com_array = []
	for i in 1:size(commodities, 1)
		process_ind = find(x -> x.site == commodities[i, :Site],
		                   process_array)
		for i_process in process_ind
			process = process_array[i_process]
			for i_com in find(x -> x[1] == commodities[i, :Commodity],
				                    process.com_in)
				process.cost_com += process.com_in[i_com][2] * commodities[i, :price]
			end
		end
	end

	sites, process_array, demand[:, 2:end]
end

function build_model(filename, debug=false)
	# read
	sites, processes, demand = read_excelfile(filename)
	timeseries = 1:size(demand, 1)
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

	@defVar(m, cost >=0)
	@defVar(m, production[timeseries, numprocess] >= 0)
	@defVar(m, cap_avail[numprocess] >= 0)
	@setObjective(m, Min, cost)

	# cost constraints
	@addConstraint(m, cost ==
	               # all commodity costs
	               sum{production[t, p] * processes[p].cost_com,
	                   t = timeseries, p = numprocess} +
	               # investment costs
	               sum{(cap_avail[p]-processes[p].cap_init) *
	                   processes[p].cost_inv, p = numprocess} +
	               # fix costs
	               sum{cap_avail[p] * processes[p].cost_fix, p = numprocess} +
	               # variable costs
	               sum{production[t,p] * processes[p].cost_var,
	                   t = timeseries, p = numprocess})

	# capacity constraints
	# assume that cap_inst <= cap_min
	@addConstraint(m, meet_cap_min[p = numprocess],
	               cap_avail[p] >= processes[p].cap_min)
	@addConstraint(m, meet_cap_max[p = numprocess],
	               cap_avail[p] <= processes[p].cap_max)
	@addConstraint(m, check_cap[t = timeseries, p = numprocess],
	               production[t,p] <= cap_avail[p])

	# demand constraints
	@addConstraint(m, meet_demand[t = timeseries, s = 1:size(sites,1)],
	               demand[t, Symbol(sites[s])] ==
	               sum{production[t, p], p = numprocess;
	                   processes[p].site == sites[s]})

	return m
end

function solve_and_show(model)
	solve(model)
	println("Optimal Cost ", getObjectiveValue(model))
	println("Optimal Production by timestep and process")
	println(getValue(getVar(model,:production)))
end

end # module
