#
# curried methods for the right-hand side of facts
#

# can't extend Base.isa, because not generic?!
"check (sub-)type of value"
is_instance(T) = x -> isa(x, T)

"match all of the arguments"
allof(x...) = y -> all(arg->(isa(arg,Function) ? arg(y)::Bool : (y==arg)), x)

"numerically less than"
roughly_less(x::Number) = anyof(roughly(x), less_than(x))

"numerically more than"
roughly_greater(x::Number) = anyof(roughly(x), greater_than(x))

"check that value is within bounds"
roughly_within(lb, ub) = allof(roughly_greater(lb), roughly_less(ub))

facts("meta tests for helpers") do
    @fact 1.0 --> is_instance(Real)
    @fact 1.0im --> not(is_instance(Real))

    @fact 5.1 --> allof(is_instance(Real), less_than(6), greater_than(4))
    @fact 5.1 --> not(allof(is_instance(Int), less_than(6), greater_than(4)))
    @fact 5.1 --> anyof(is_instance(Int), less_than(6), greater_than(4))

    @fact 1.5 --> roughly_less(2.0)
    @fact 2.0 + 1e-10 --> roughly_less(2.0)
    @fact 2.1 --> not(roughly_less(2.0))

    @fact 2.5 --> roughly_greater(2.0)
    @fact 2.0 - 1e-10 --> roughly_greater(2.0)
    @fact 1.9 --> not(roughly_greater(2.0))

    @fact 0.5 --> not(roughly_within(1.0, 2.0))
    @fact 1.0 - 1e-9 --> roughly_within(1.0, 2.0)
    @fact 1.5 --> roughly_within(1.0, 2.0)
    @fact 2.0 + 1e-9 --> roughly_within(1.0, 2.0)
    @fact 2.5 --> not(roughly_within(1.0, 2.0))
end

#
# test data
#
"create a small instance (and topology) with a single pipe"
function single_pipe(;length=100.0, flow=200.0)
    nodes = [Node(0,0), Node(length,0)]
    demand = [-flow, flow]
    press = fill(Bounds(60.0, 80.0), size(nodes))
    diams = [Diameter(t...) for t in [(0.8, 1.0),(1.0, 1.2),(1.2, 1.5)]]
    inst = Instance(nodes, demand, press, diams)
    topo = Topology(nodes, [Arc(1,2)])
    inst, topo
end
