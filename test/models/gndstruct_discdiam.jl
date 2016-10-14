using PipeLayout.GndStructDiscDiam
import PipeLayout: ploss_coeff_nice
import PipeLayout.GndStructDiscDiam: CandSol, make_master, make_sub, linear_overest, make_semimaster, make_semisub
using JuMP
using Cbc
using Clp

facts("solve master problem (ground structure, discrete diameters)") do
    #       7    9      even arc numbers for
    #   () - d2 - ()    reversed arcs
    #   /1   /3   /5
    #  s1 - () - d1
    #    11   13
    inst = Instance([Node(0,0), Node(40,0), Node(20, 20)],
                    [-50, 20, 30],
                    fill(Bounds(60,80), 3),
                    [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]])
    topo = squaregrid(2, 3, 20.0, antiparallel=true)
    model, y, z, q = make_master(inst, topo, CbcSolver())

    status = solve(model)
    @fact status --> :Optimal

    ysol = getvalue(y)
    zsol = getvalue(z)
    qsol = getvalue(q)

    # shortest tree is obvious:
    @fact ysol[11] --> roughly(1.0)
    @fact ysol[13] --> roughly(1.0)
    @fact ysol[4] --> roughly(1.0)
    @fact sum(ysol) --> roughly(3.0) # all others 0

    # only the smallest diameter is chosen
    @fact zsol[11,1] --> roughly(1.0)
    @fact zsol[13,1] --> roughly(1.0)
    @fact zsol[4,1] --> roughly(1.0)
    @fact sum(zsol) --> roughly(3.0) # all others 0

    # uniq flow solution
    @fact qsol[11] --> roughly(50.0)
    @fact qsol[13] --> roughly(20.0)
    @fact qsol[4] --> roughly(30.0)
    @fact sum(qsol) --> roughly(100.0) # all others 0
end

facts("solve subproblem (ground structure, discrete diameters)") do
    #       7    9      even arc numbers for
    #   () - d2 - ()    reversed arcs
    #   /1   /3   /5
    #  s1 - () - d1
    #    11   13
    solver = ClpSolver()

    inst = Instance([Node(0,0), Node(40,0), Node(20, 20)],
                    [-50, 20, 30],
                    fill(Bounds(60,80), 3),
                    [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]])
    topo = squaregrid(2, 3, 20.0, antiparallel=true)

    nnodes = 2*3
    narcs = 2*7
    ndiam = length(inst.diameters)

    # recreate solution from master problem
    zsol = fill(false, (narcs, ndiam))
    zsol[11,1] = true
    zsol[13,1] = true
    zsol[4,1] = true

    qsol = fill(0.0, narcs)
    qsol[11] = 50.0
    qsol[13] = 20.0
    qsol[4] = 30.0

    context("feasible subproblem") do
        cand = CandSol(zsol, qsol, fill(0.0, narcs))
        model, π, Δl, Δu, ploss, plb, pub = make_sub(inst, topo, cand, solver)
        status = solve(model)
        @fact status --> :Optimal

        # primal solution
        πsol = getvalue(π)
        Δlsol = getvalue(Δl)
        Δusol = getvalue(Δu)

        @fact Δlsol --> roughly(zeros(nnodes))
        @fact Δusol --> roughly(zeros(nnodes))

        # dual solution
        μsol = getdual(ploss)
        λlsol = getdual(plb)
        λusol = getdual(pub)

        @fact μsol --> roughly(zeros(length(ploss)))
        @fact λlsol --> roughly(zeros(nnodes))
        @fact λusol --> roughly(zeros(nnodes))
    end

    context("infeasible subproblem") do
        cand = CandSol(zsol, 10 * qsol, fill(0.0, narcs)) # scaled
        model, π, Δl, Δu, ploss, plb, pub = make_sub(inst, topo, cand, solver)
        status = solve(model)
        @fact status --> :Optimal

        # primal solution
        πsol = getvalue(π)
        Δlsol = getvalue(Δl)
        Δusol = getvalue(Δu)

        # complementarity
        @fact Δlsol .* Δusol --> roughly(zeros(nnodes))

        # innodes should not have slack
        terms = [2, 3, 6]
        isterm(v) = v in terms
        innodes = filter(not(isterm) , 1:nnodes)
        @fact Δlsol[innodes] --> roughly(zeros(length(innodes)))
        @fact Δusol[innodes] --> roughly(zeros(length(innodes)))

        # at least two vertices have slack
        slack = Δlsol + Δusol
        @fact sum(slack[terms] .> 0) --> greater_than_or_equal(2)

        # dual solution, TODO: fix sign of dual multipliers
        μsol = abs(getdual(ploss))
        λlsol = abs(getdual(plb))
        λusol = abs(getdual(pub))

        # at least two bounds active
        @fact sum(λlsol[terms] .> 0) --> greater_than_or_equal(1)
        @fact sum(λusol[terms] .> 0) --> greater_than_or_equal(1)

        # at least one path active
        @fact sum(μsol .> 0) --> greater_than_or_equal(2)

        @fact λlsol[innodes] --> roughly(zeros(length(innodes)))
        @fact λusol[innodes] --> roughly(zeros(length(innodes)))
    end
end

facts("compare relaxation and exact for subproblem") do
    #     __s1__  __s2
    #   t3      t4
    solver = ClpSolver()

    nodes = [Node(100,0), Node(300,0), Node(0,0), Node(200,0)]
    arcs = [Arc(1,3), Arc(1,4), Arc(2,4)]
    topo = Topology(nodes, arcs)

    demand = [-600, -400, 400, 600]
    bounds = fill(Bounds(40, 80), 4)
    diams = [Diameter(1.0, 1.0), Diameter(2.0, 2.0)]
    inst = Instance(nodes, demand, bounds, diams, ploss_coeff_nice)

    zsol = [true false; true false; true false]
    qsol = [400, 200, 400]
    cand = CandSol(zsol, qsol, qsol.^2)

    context("solving the exact subproblem") do
        model, π, Δl, Δu, ploss, plb, pub =
            make_sub(inst, topo, cand, solver, relaxed=false)
        status = solve(model)
        @fact status --> :Optimal
        @fact getobjectivevalue(model) --> roughly(3600)
    end

    context("solving the relaxation") do
        model, π, Δl, Δu, ploss, plb, pub =
            make_sub(inst, topo, cand, solver, relaxed=true)
        status = solve(model)
        @fact status --> :Optimal
        @fact getobjectivevalue(model) --> roughly(0)
    end
end

facts("run GBD iterations") do
    #       7    9      even arc numbers for
    #   () - d2 - ()    reversed arcs
    #   /1   /3   /5
    #  s1 - () - d1
    #    11   13

    # slightly irregular grid
    nodes = [Node(0,0), Node(45,0), Node(25, 22)]
    demand = [-50, 20, 30]
    bounds = fill(Bounds(60,80), 3)
    diams = [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]]

    topo = Topology([Node(t...) for t in [(0,22), (0,0), (25,22), (25,0), (45,22), (45,0)]],
                    [Arc(t...) for t in [(1,2), (2,1), (3,4), (4,3), (5,6), (6,5),
                                         (1,3), (3,1), (3,5), (5,3),
                                         (2,4), (4,2), (4,6), (6,4)]])

    context("low flow: very easy instance") do
        inst = Instance(nodes, 1*demand, bounds, diams)

        result = optimize(inst, topo, IterGBD(CbcSolver(), ClpSolver()))
        @fact result.status --> :Optimal

        zsol = result.solution.zsol
        @fact zsol[4,1] --> true
        @fact zsol[11,1] --> true
        @fact zsol[13,1] --> true
        @fact sum(zsol) --> 3

        @fact result.dualbound --> roughly(67.0)
        @fact result.niter --> 1
    end

    context("medium flow: difficult instance") do
        inst = Instance(nodes, 5*demand, bounds, diams)

        result = optimize(inst, topo, IterGBD(CbcSolver(), ClpSolver()))
        @fact result.status --> :Optimal

        zsol = result.solution.zsol
        @fact zsol[4,1] --> true
        @fact zsol[11,2] --> true
        @fact zsol[13,1] --> true
        @fact sum(zsol) --> 3

        @fact result.dualbound --> roughly(72.0)
        @fact result.niter --> 3
    end

    context("high flow: iteration limit instance") do
        inst = Instance(nodes, 30*demand, bounds, diams)

        result = optimize(inst, topo, IterGBD(CbcSolver(), ClpSolver(), maxiter=3))
        @fact result.status --> :UserLimit
        @fact result.solution --> nothing
        @fact result.dualbound --> roughly(156.0)
        @fact result.niter --> 3
    end

    context("high flow: time limit instance") do
        inst = Instance(nodes, 30*demand, bounds, diams)

        result = optimize(inst, topo, IterGBD(CbcSolver(), ClpSolver(), timelimit=5.0))
        @fact result.status --> :UserLimit
        @fact result.solution --> nothing
    end

    context("high flow on triangle: infeasible") do
        inst3 = Instance([Node(0,0), Node(50,0)],
                         20*[-50, 50],
                         [Bounds(60,80), Bounds(60,80)],
                         [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]])
        topo3 = Topology([Node(0,0), Node(50,0), Node(30, 40)],
                         [Arc(1,3), Arc(1,2), Arc(2,3)])

        result = optimize(inst3, topo3, IterGBD(CbcSolver(), ClpSolver()))
        @fact result.status --> :Infeasible
        @fact result.solution --> nothing
        @fact result.dualbound --> Inf
        @fact result.niter --> 2
    end

    facts("on the example with subproblem/relaxation gap") do
        #     __s1__  __s2
        #   t3      t4
        nodes = [Node(100,0), Node(300,0), Node(0,0), Node(200,0)]
        arcs = [Arc(1,3), Arc(1,4), Arc(2,4)]
        topo = Topology(nodes, arcs)

        demand = [-600, -400, 400, 600]
        bounds = fill(Bounds(40, 80), 4)
        diams = [Diameter(1.0, 1.0), Diameter(2.0, 2.0)]
        inst = Instance(nodes, demand, bounds, diams, ploss_coeff_nice)

        result = optimize(inst, topo, IterGBD(CbcSolver(), ClpSolver()))
        @fact result.status --> :Optimal
        zsol = result.solution.zsol
        @fact sum(zsol[:,2]) --> 1
        @fact sum(zsol[:,1]) --> 2 # solution not quite uniqe
        @fact result.dualbound --> roughly(400.0)
        @fact result.niter --> 2
    end

    context("difficult instance with disconnected candidates") do
        inst = Instance([Node(0,0), Node(100,0), Node(200,100)],
                        [800, -900, 100],
                        fill(Bounds(40,80), 3),
                        [Diameter(t...) for t in [(1.0, 1.0), (2.0, 3.2)]],
                        ploss_coeff_nice)
        topo = squaregrid(2, 3, 100.0, antiparallel=true)

        # trigger the cuts for disconnected candidate
        result = optimize(inst, topo, IterGBD(CbcSolver(), ClpSolver(),
                                              addnogoods=true, addcritpath=false))
        @fact result.status --> :Optimal

        zsol = result.solution.zsol
        @fact sum(zsol) --> 3

        @fact result.dualbound --> roughly(520.0)
    end

end

facts("Linear overestimation of supremum terms") do
    values = Float64[i*j - 1 for i=1:4, j=1:4]
    values = 2*tril(values) - triu(values)

    cand_i, cand_j = 3, 2
    a, b, c = linear_overest(values, cand_i, cand_j, ClpSolver())
    @fact size(a) --> (4,)
    @fact size(b) --> (4,)
    @fact size(c) --> ()

    @fact a[cand_i] + b[cand_j] + c --> values[cand_i, cand_j]
end

facts("Solve semimaster without z vars") do
    #       7    9      even arc numbers for
    #   () - d2 - ()    reversed arcs
    #   /1   /3   /5
    #  s1 - () - d1
    #    11   13
    inst = Instance([Node(0,0), Node(40,0), Node(20, 20)],
                    [-50, 20, 30],
                    fill(Bounds(60,80), 3),
                    [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]])
    topo = squaregrid(2, 3, 20.0, antiparallel=true)
    model, y, q = make_semimaster(inst, topo, CbcSolver())

    status = solve(model)
    @fact status --> :Optimal

    ysol = getvalue(y)
    qsol = getvalue(q)

    # shortest tree is obvious:
    @fact ysol[11] --> roughly(1.0)
    @fact ysol[13] --> roughly(1.0)
    @fact ysol[4] --> roughly(1.0)
    @fact sum(ysol) --> roughly(3.0) # all others 0

    # uniq flow solution
    @fact qsol[11] --> roughly(50.0)
    @fact qsol[13] --> roughly(20.0)
    @fact qsol[4] --> roughly(30.0)
    @fact sum(qsol) --> roughly(100.0) # all others 0
end

facts("Solve semisubproblem with free z vars") do
    #       7    9      even arc numbers for
    #   () - d2 - ()    reversed arcs
    #   /1   /3   /5
    #  s1 - () - d1
    #    11   13

    # slightly irregular grid
    nodes = [Node(0,0), Node(45,0), Node(25, 22)]
    demand = [-50, 20, 30]
    bounds = fill(Bounds(60,80), 3)
    diams = [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]]

    topo = Topology([Node(t...) for t in [(0,22), (0,0), (25,22), (25,0), (45,22), (45,0)]],
                    [Arc(t...) for t in [(1,2), (2,1), (3,4), (4,3), (5,6), (6,5),
                                         (1,3), (3,1), (3,5), (5,3),
                                         (2,4), (4,2), (4,6), (6,4)]])

    zsol = fill(false, length(topo.arcs), length(diams))
    zsol[4,1]  = true
    zsol[11,1] = true
    zsol[13,1] = true
    qsol = fill(0.0, length(topo.arcs))
    qsol[[4, 11, 13]] = [30.0, 50.0, 20.0]

    context("low flow: very easy instance") do
        factor = 1.0
        inst = Instance(nodes, factor*demand, bounds, diams)

        sol = CandSol(zsol, factor*qsol, qsol.^2)
        model, candarcs, z = make_semisub(inst, topo, sol, CbcSolver())
        @fact length(candarcs) --> 3
        @fact size(z) --> (3, 2)

        status = solve(model)
        @fact status --> :Optimal

        znew = fill(false, length(topo.arcs), length(diams))
        znew[candarcs,:] = (getvalue(z) .> 0.5)
        @fact znew[4,1] --> true
        @fact znew[11,1] --> true
        @fact znew[13,1] --> true
        @fact sum(znew) --> 3
    end

    context("medium flow: difficult instance") do
        factor = 5.0
        inst = Instance(nodes, factor*demand, bounds, diams)

        sol = CandSol(zsol, factor*qsol, qsol.^2)
        model, candarcs, z = make_semisub(inst, topo, sol, CbcSolver())
        @fact length(candarcs) --> 3
        @fact size(z) --> (3, 2)

        status = solve(model)
        @fact status --> :Optimal

        znew = fill(false, length(topo.arcs), length(diams))
        znew[candarcs,:] = (getvalue(z) .> 0.5)
        @fact znew[4,1] --> true
        @fact znew[11,2] --> true
        @fact znew[13,1] --> true
        @fact sum(znew) --> 3

    end

    context("high flow on triangle: infeasible") do
        inst = Instance([Node(0,0), Node(50,0)],
                        [-1000, 1000],
                        [Bounds(60,80), Bounds(60,80)],
                        [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]])
        topo = Topology([Node(0,0), Node(50,0), Node(30, 40)],
                        [Arc(1,3), Arc(1,2), Arc(2,3)])

        zsol = fill(false, 3, 2)
        zsol[1,1] = true
        qsol = 1000*[1.0, 0.0, 0.0]
        sol = CandSol(zsol, qsol, qsol.^2)
        model, candarcs, z = make_semisub(inst, topo, sol, CbcSolver())
        @fact length(candarcs) --> 1
        @fact size(z) --> (1, 2)

        status = solve(model, suppress_warnings=true)
        @fact status --> :Infeasible
    end

end

facts("Solve semi decomposition with nogoods on y") do
    #       7    9      even arc numbers for
    #   () - d2 - ()    reversed arcs
    #   /1   /3   /5
    #  s1 - () - d1
    #    11   13

    # slightly irregular grid
    nodes = [Node(0,0), Node(45,0), Node(25, 22)]
    demand = [-50, 20, 30]
    bounds = fill(Bounds(60,80), 3)
    diams = [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]]

    topo = Topology([Node(t...) for t in [(0,22), (0,0), (25,22), (25,0), (45,22), (45,0)]],
                    [Arc(t...) for t in [(1,2), (2,1), (3,4), (4,3), (5,6), (6,5),
                                         (1,3), (3,1), (3,5), (5,3),
                                         (2,4), (4,2), (4,6), (6,4)]])

    context("low flow: very easy instance") do
        inst = Instance(nodes, 1 * demand, bounds, diams)
        result = optimize(inst, topo, IterTopo(CbcSolver(), CbcSolver()))
        @fact result.status --> :Optimal

        zsol = result.solution.zsol
        qsol = result.solution.qsol

        # shortest tree is obvious, smallest diameter enough:
        @fact zsol[11, 1] --> roughly(1.0)
        @fact zsol[13, 1] --> roughly(1.0)
        @fact zsol[4, 1] --> roughly(1.0)
        @fact sum(zsol) --> roughly(3.0) # all others 0

        # uniq flow solution
        @fact qsol[11] --> roughly(50.0)
        @fact qsol[13] --> roughly(20.0)
        @fact qsol[4] --> roughly(30.0)
        @fact sum(qsol) --> roughly(100.0) # all others 0
    end

    context("medium flow: difficult instance") do
        inst = Instance(nodes, 10 * demand, bounds, diams)
        result = optimize(inst, topo, IterTopo(CbcSolver(), CbcSolver()))
        @fact result.status --> :Optimal

        zsol = result.solution.zsol
        qsol = result.solution.qsol

        # shortest tree is obvious, need one large diameter
        @fact sum(zsol[2, :]) --> 1
        @fact sum(zsol[7, :]) --> 1
        @fact sum(zsol[11, :]) --> 1
        @fact sum(zsol[13, :]) --> 1
        @fact sum(zsol[:, 1]) --> 1
        @fact sum(zsol[:, 2]) --> 3
        @fact sum(zsol) --> roughly(4.0) # all others 0
    end

    context("high flow on triangle: infeasible instance") do
        inst = Instance([Node(0,0), Node(50,0)],
                        [-1000, 1000],
                        [Bounds(60,80), Bounds(60,80)],
                        [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2)]])
        topo = Topology([Node(0,0), Node(50,0), Node(30, 40)],
                        [Arc(1,3), Arc(1,2), Arc(2,3),
                         Arc(3,1), Arc(2,1), Arc(3,2)])

        result = optimize(inst, topo, IterTopo(CbcSolver(), CbcSolver()))
        @fact result.status --> :Infeasible
    end
end
