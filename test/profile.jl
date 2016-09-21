using urbs
using JuMP

function profile(filename, maxtime; stepsize=10, iterations=10, solve=false, cutoff=60)
	outer_iterations = round(Int, maxtime/stepsize)
	timing = zeros(outer_iterations)
	solvetime = zeros(outer_iterations)
	function ret_values(outer, i)
		timing = timing ./ iterations
		solvetime = solvetime ./ iterations
		timing[outer] = timing[outer] * iterations / i
		solvetime[outer] = solvetime[outer] * iterations / i
		if solve
			return (timing, solvetime, i)
		else
			return (timing,[], i)
		end
	end
	inputs = urbs.read_excelfile(filename)
	for mt = stepsize:stepsize:maxtime
		outer = round(Int, mt/stepsize)
		for i = 1:iterations
			println(mt, " ", i)
			t = time()
			m = urbs.build_model(inputs...; timeseries=1:mt)
			timing[outer] += time() - t
			# with solving?
			if solve
				t = time()
				urbs.solve(m)
				solvetime[outer] += time() - t
			end

			# break if the loop takes too long
			if (solvetime[outer] + timing[outer]) / i > (i+1) * cutoff
				return ret_values(outer, i)
			end
		end
	end
	if solve
		return ret_values(outer_iterations, iterations)
	else
		return ret_values(outer_iterations, iterations)
	end
end

function profiletolog(filename; logfile="", cutoff=60)
	if logfile == ""
		logfile = normpath(Pkg.dir("urbs"), "test", string(now(),".csv"))
	end

	maxt = 4

	open(logfile, "a") do f
		println(f, "maxt,overall, model, solve")
		for i = 1:10
			inputs = urbs.read_excelfile(filename)
			startingtime = time()
			m = urbs.build_model(inputs...; timeseries=1:maxt)
			modeltime = time()-startingtime
			urbs.solve(m)
			solvetime = time() - startingtime - modeltime
			overall = modeltime + solvetime
			@printf(f, "%7d,%7.4f,%7.4f,%7.4f\n", maxt, overall, modeltime, solvetime)
		end
	end

	#for debugging
	open(logfile,"r") do f
		print(readall(f))
	end

end

