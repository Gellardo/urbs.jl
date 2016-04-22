module urbs

using ExcelReaders
using DataFrames

function main(filename)
	file = openxl(filename)

	commodities = readxl(DataFrame,file, "Commodity!A1:C3", header=true)
	processes = readxl(DataFrame,file, "Process!A1:B3", header=true)
	processCommodity = readxl(DataFrame,file, "Process-Commodity!A1:D3", header=true)
	demand = readxl(DataFrame, file, "Demand!A1:C5", header=true)

	println(commodities)
end # main()

end # module
