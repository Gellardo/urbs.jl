using urbs
using JuMP

function profile(filename, maxtimesteps; it_outer=10, it_inner=10, solve=false, cutoff=60)
	timing = zeros(it_outer)
	solvetime = zeros(it_outer)
	function ret_values(outer, i)
		timing = timing ./ it_inner
		solvetime = solvetime ./ it_inner
		timing[outer] = timing[outer] * it_inner / i
		solvetime[outer] = solvetime[outer] * it_inner / i
		if solve
			return (timing, solvetime, i)
		else
			return (timing,[], i)
		end
	end
	inputs = urbs.read_excelfile(filename)
	for mt = maxtimesteps/it_outer:maxtimesteps/it_outer:maxtimesteps
		outer = round(Int, mt/maxtimesteps*it_outer)
		for i = 1:it_inner
			t = time()
			m = urbs.build_model(inputs...; timeseries=1:round(Int, mt))
			timing[outer] += time() - t
			# with solving?
			if solve
				t = time()
				JuMP.solve(m)
				solvetime[outer] += time() - t
			end

			# break if the loop takes too long
			if (solvetime[outer] + timing[outer]) / i > (i+1) * cutoff
				return ret_values(outer, i)
			end
		end
	end
	if solve
		return ret_values(it_outer, it_inner)
	else
		return ret_values(it_outer, it_inner)
	end
end

