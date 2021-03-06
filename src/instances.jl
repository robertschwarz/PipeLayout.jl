# custom types
import Base.transpose
using StaticArrays

export Node, Bounds, Diameter, Instance, Arc, Topology

"Node type with location on plane."
struct Node <: FieldVector{2, Float64}
    x::Float64 # [km]
    y::Float64 # [km]
end

"Add no-op transpose to suppress warning."
Base.transpose(n::Node) = n

"Variable bounds as interval, used for node pressure."
struct Bounds <: FieldVector{2, Float64}
    lb::Float64 # [bar]
    ub::Float64 # [bar]
end

"Diameter has value and cost factor (per length)."
struct Diameter <: FieldVector{2, Float64}
    value::Float64 # [m]
    cost::Float64  # [Mio EUR/km]
end

"""
An instance for the Pipe Layout Problem.

It is defined by boundary nodes, a fixed and balanced flow demand, pressure
bounds and available diameters. The pressure loss coefficients is also
specified, but is optional.
"""
struct Instance
    nodes::Vector{Node}
    demand::Vector{Float64} # [kg/s]
    pressure::Vector{Bounds}
    diameters::Vector{Diameter}
    ploss_coeff::Float64 # [1e7 m2/s2]

    function Instance(nodes, demand, pressure, diameters, ploss_coeff)
        @assert length(nodes) == length(demand)
        @assert length(nodes) == length(pressure)
        @assert length(nodes) >= 2
        @assert length(diameters) >= 1
        new(nodes, demand, pressure, diameters, ploss_coeff)
    end
end

Instance(nodes, demand, pressure, diameters) =
    Instance(nodes, demand, pressure, diameters, ploss_coeff)

"An arc is specified by integer indices to the node array"
struct Arc <: FieldVector{2, Int}
    tail::Int
    head::Int
end

"""
A topology for a pipe layout.

May contain (Steiner) nodes (in addition to the boundary nodes defined in the
instance). These would be appended at the end. Their location need not be
considered fixed.

Contains arcs that are given as pairs of indices into the array of nodes.

Can be used both as a candidate topology (in form of a spanning tree) or as the
ground structure for the choice of topologies.
"""
struct Topology
    nodes::Vector{Node}
    arcs::Vector{Arc}
end

# JSON I/O
#  - serialization works out of the box,
#  - deserialization included:
include("deserialization.jl")

# Creating random instances
include("random.jl")
