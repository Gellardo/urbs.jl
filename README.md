# urbs

[![Build Status](https://travis-ci.org/Gellardo/urbs.jl.svg?branch=master)](https://travis-ci.org/Gellardo/urbs.jl)

urbs.jl is a [linear programming](https://en.wikipedia.org/wiki/Linear_programming) optimisation model for distributed energy systems. Its name stems from it's origin as a port of [URBS](https://github.com/tum-ens/urbs).

## Installation
Urbs can be installed through the Julia package manager:

```julia
julia> Pkg.clone("https://github.com/Gellardo/urbs.jl.git", "urbs")
```

Before any optimization can be done, one also has to install a solver
for the [JuMP](https://github.com/JuliaOpt/JuMP.jl) package, for example:

```julia
julia> Pkg.add("GLPKMathProgInterface")
```

In order to read data from Excelfiles, urbs uses ExcelReaders.jl which in turn needs
pythons `xlrd` package.

## Copyright

Copyright (C) 2016  Gellardo

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>
