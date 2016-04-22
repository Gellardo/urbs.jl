module urbs

using JuMP
using ExcelReaders
using DataFrames

filename = normpath(Pkg.dir("urbs"), "test", "left-right.xlsx")

type Process
	site
	process_type
	min_prod
	max_prod
end

function read_xlsheet(file, sheetname)
		sheet = file.workbook[:sheet_by_name](sheetname)
		max_col = 'A' + sheet[:ncols] - 1
		readxl(DataFrame, file, string(sheetname, "!A1:", max_col, sheet[:nrows]),
		       header = true)
end

function read_excelfile(filename)
	file = openxl(filename)

	commodities = read_xlsheet(file, "Commodity")
	processes = read_xlsheet(file, "Process")
	processCommodity = read_xlsheet(file, "Process-Commodity")
	demand = read_xlsheet(file, "Demand")

	sites = unique(processes[:, :Site])

	# build an array of Process
	process_array = []
	for i in 1:size(processes, 1)
		next_process = Process(processes[i, :Site], processes[i, :Process],
		                       processes[i, :MinOut], processes[i, :MaxOut])
		if i != 1
			process_array = [process_array; next_process]
		else
			process_array = [next_process]
		end
	end

	com_array = []
	for i in 1:size(commodities, 1)
		next_com = (string(commodities[i, :Site], '.',
		                   commodities[i, :Commodity]),
		            commodities[i, :Price])
		if i != 1
			com_array = [com_array next_com]
		else
			com_array = [next_com]
		end
	end
	# Dict "Site.Commodity" => price
	prices = Dict{AbstractString, Number}(com_array)

	#process - commodity relation
	proc_com_rel = []
	for i in 1:size(processCommodity, 1)
		next_rel = (string(processCommodity[i, :Process], '.',
				           processCommodity[i, :Commodity], '.',
						   processCommodity[i, :Direction]),
				    processCommodity[i, :ratio])
		if i != 1
			proc_com_rel = [proc_com_rel next_rel]
		else
			proc_com_rel = [next_rel]
		end
	end
	# Dict "Site.Commodity.Direction" => ratio
	processratio_by_proc_com_dir = Dict{AbstractString, Number}(proc_com_rel)

	sites, prices, process_array, processratio_by_proc_com_dir, demand[:, 2:end]
end

function build_model(filename)
	# read
	sites, prices, processes, proc_com, demand = read_excelfile(filename)
	timeseries = 1:size(demand, 1)

	println("read data")
	println(timeseries)
	println(sites)
	println(prices)
	println(processes)
	println(proc_com)
	println(demand)

	#build model
	m = Model()

	@defVar(m, cost >= 0)
	@defVar(m, production[1:size(processes, 1)] >= 0)

	return m
end

end # module
