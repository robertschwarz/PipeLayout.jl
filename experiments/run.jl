#! /usr/bin/env julia

# raise exception when receiving SIGINT
ccall(:jl_exit_on_sigint, Void, (Cint,), 0)

using PipeLayout
using PipeLayout.GndStr

function solve_with(instance::AbstractString, solver::GroundStructureSolver)
    inst = PipeLayout.read_instance(instance)
    topo = PipeLayout.read_topology(instance)

    optimize(inst, topo, solver)
end

if length(ARGS) != 2
    println("usage: run.jl <config> <instname>")
    exit(1)
end

config = ARGS[1]
instname = ARGS[2]

include(config) # creates solver

println("solving $instname with $(basename(config))")

try
    tic()
    println("vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv")
    result = solve_with(instname, solver)
    println("^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^")
    toc()
    println("Status: $(result.status)")
    if result.solution != nothing
        println("Solution: $(findn(result.solution.zsol))")
        println("Primal bound: $(result.primalbound)")
        println("Dual bound: $(result.dualbound)")
    else
        println("No solution")
    end
catch ex
    if isa(ex, InterruptException)
        println("-- was interrupted --")
    else
        rethrow()
    end
end
