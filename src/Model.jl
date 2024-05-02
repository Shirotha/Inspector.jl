#=

construct observable/regular struct pair using @NamedTuple like syntax
observable struct should have support for validation, coersion and display attributes

```julia
@model MyModel begin
    @coerce clamp(x, 1:100)
    @drawer Slider
    x::Int
    @validate y < 0 && Err("y can't be negative")
    y::Float64
end
```

=#
# Property
abstract type AbstractProperty{T} end
"Property representing a single (structured) value"
struct ValueProperty{T, FConvert, FValidate, FCoerce} <: AbstractProperty{T}
    name::Symbol
    value::Observable{T}
    drawer::Symbol # TODO: how to store drawer data properly

    "convert from user values. U -> T where U"
    convert::FConvert
    "reject invalid values. T -> Result{T, E} where E"
    validate::FValidate
    "modify incoming value before updating value. T -> T"
    coerce::FCoerce
end
function ValueProperty(name::Symbol, value::T;
    drawer::Symbol = :default,
    convert::FConvert = v -> convert(T, v),
    validate::FValidate = _ -> true,
    coerce::FCoerce = identity
) where {T, FConvert, FValidate, FCoerce}
    value = Observable(value; ignore_equal_values = true)
    ValueProperty{T, FConvert, FValidate, FCoerce}(name, value, drawer, convert, validate, coerce)
end

observable(p::ValueProperty) = p.value

Base.getindex(p::ValueProperty) = p.value[]
Base.setindex!(p::ValueProperty, value) = map(v -> p.value[] = p.coerce(v), value |> p.convert |> p.validate)

"Property representing a collection of values"
struct CollectionProperty{T} <: AbstractProperty{T}
    name::Symbol
    items::T
end

# TODO: implement this
observable(p::CollectionProperty) = throw("not implemented")

Base.getindex(p::CollectionProperty, i) = p.items[i]
# TODO: implement this
Base.setindex!(p::CollectionProperty, value, i) = throw("not implemented")

# end Property

# Model
export Model
getobservabletype(::Type{T}) where T = throw("no observable model implemented for type $(T)")
observables(m) = observable.(getproperty.(m, propertynames(m)))

"""
Hold property information and handles conversion to and from plain data.
Redirectes property access to internal data.

# Generic Arguments
- `TObservable`: Type that holds all [AbstractProperty](@ref)
    (needs a constructor `TObservable(TPlain)`)
- `TPlain`: Type of the pure data without property information
    (needs a constructor from all properties ordered as returned by `propertynames`)

Both types have to share the same `propertynames`.
"""
struct Model{TObservable, TPlain}
    properties::TObservable
    observable::Observable{TPlain}
end
function Model{TObservable}(data::TPlain) where {TObservable, TPlain}
    m = TObservable(data)
    obs = map((ps...) -> TPlain(ps...), observables(m))
    Model{TObservable, TPlain}(m, obs)
end
Model(data::TPlain) where TPlain = Model{getobservabletype(TPlain)}(data)

observable(m::Model) = getfield(m, :observable)

Base.propertynames(m::Model, private=false) = propertynames(m.properties)
Base.getproperty(m::Model, name::Symbol) = getproperty(m.properties, name)
Base.setproperty!(m::Model, name::Symbol, value) = setproperty!(m.properties, name, value)
# end Model

#=
@model $typename({$typeargs...} (where {$constraints...})) begin
    $inner...
end
attribute:
    head: macrocall
    args[1]: name
    args[2]: body

    allowed names: validate, coerce, drawer (+ compound macros?)
property:
    head: ::
    args[1]: name
    args[2]: type
=#
macro model(expr)
    # TODO: implement this
end