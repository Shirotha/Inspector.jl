# ChangedEvent
ChangedEventKey = Union{Symbol, Int}
struct ChangedEvent{N}
    path::NTuple{N, ChangedEventKey}
end
ChangedEvent(path::Vararg{ChangedEventKey, N}) where N = ChangedEvent{N}(path)

Base.eltype(::Type{<:ChangedEvent}) = Symbol
Base.length(::ChangedEvent{N}) where N = N
Base.iterate(::ChangedEvent{N}, state=1) where N = state >= N ? nothing : (e.path[state], state+1)
Base.isdone(::ChangedEvent{N}, state=1) where N = state >= N
# end ChangedEvent

abstract type AbstractProperty end

# ValueProperty
"Property representing a single (terminal) value"
struct ValueProperty{T, FConvert, FValidate, FCoerce} <: AbstractProperty
    value::Observable{T}
    drawer::Symbol # TODO: how to store drawer data properly

    "convert from user values. U -> T where U"
    convert::FConvert
    "reject invalid values. T -> Result{T, E} where E"
    validate::FValidate
    "modify incoming value before updating value. T -> T"
    coerce::FCoerce
end
function ValueProperty(value::T;
    drawer::Symbol = :default,
    convert::FConvert = v -> convert(T, v),
    validate::FValidate = Ok,
    coerce::FCoerce = identity
) where {T, FConvert, FValidate, FCoerce}
    value = Observable(value; ignore_equal_values = true)
    ValueProperty{T, FConvert, FValidate, FCoerce}(value, drawer, convert, validate, coerce)
end

observable(p::ValueProperty) = p.value
value(p::ValueProperty) = p.value[]

Base.getindex(p::ValueProperty) = p.value[]
Base.setindex!(p::ValueProperty, value) = map(v -> p.value[] = p.coerce(v), value |> p.convert |> p.validate)
# end Property

# StructProperty
"Property representing heterogeneous data with named fields"
mutable struct StructProperty{Names, T} <: AbstractProperty
    data::NamedTuple{Names, T}
    event::Observable{ChangedEvent}
    drawer::Symbol # TODO: how to store drawer data properly

    listeners::Vector{ObserverFunction}
end
function StructProperty(data::NamedTuple{Names, T}; drawer=:default) where {Names, T}
    event = Observable{ChangedEvent}(ChangedEvent())
    function register(name, obs)
        on(obs; weak = true) do value
            event[] = if value isa ChangedEvent
                ChangedEvent(name, value...)
            else
                ChangedEvent(name)
            end
        end
    end
    listeners = register.(Names, [observable.(values(data))...])
    StructProperty{Names, T}(data, event, drawer, listeners)
end
StructProperty(; data...) = StructProperty((; data...))

observable(p::StructProperty) = p.event
value(p::StructProperty{Names}) where Names = NamedTuple{Names}(value.(p.data |> values))

Base.getindex(p::StructProperty, name::Symbol) = p.data[name]
# end SructProperty

# ArrayProperty
"Property representing homogeneous data with index access"
struct ArrayProperty{T, N} <: AbstractProperty
    data::Array{T, N}
    event::Observable{ChangedEvent}
    drawer::Symbol

    listeners::Array{ObserverFunction, N}
end
function ArrayProperty(data::Array{T, N}; drawer=:default) where {T, N}
    event = Observable{ChangedEvent}(ChangedEvent())
    listeners = map(enumerate(data)) do (idx, dat)
        on(dat |> observable; weak = true) do value
            event[] = if value isa ChangedEvent
                ChangedEvent(idx, value)
            else
                ChangedEvent(idx)
            end
        end
    end
    ArrayProperty{T, N}(data, event, drawer, listeners)
end

observable(p::ArrayProperty) = p.event
value(p::ArrayProperty) = value.(p.data)

Base.getindex(p::ArrayProperty, idx...) = p.data[idx...]

# TODO: implment adding/removing elements
# end ArrayProperty

"Create a new `AbstractProperty` object from any data"
Property(data; kwargs...) = ValueProperty(data; kwargs...)
Property(p::AbstractProperty; kwargs...) = p

"""
This macro will declare a data type to be used with `Property`.

# Examples
```julia
@model struct MyModel <: MyAbstractModel
    @validate length(name) <= 100
    name::String
    @coerce clamp(count, 1:100)
    @drawer Slider(1, 100)
    count::Int
    data::SubModel
end
```
"""
macro model(expr)
    function fielddec((name, T, _))
        @esc name T
        :($name::$T)
    end
    function kwarg((name, value))
        @esc name value
        :($name = $value)
    end
    function propertycall((name, _, attrs))
        @esc name
        :($name = Property(getfield(data, $name); $(kwarg.(attrs))))
    end

    @capture(expr, struct head_ lines__ end) || throw("expected struct definition")
    T = head |> namify |> esc
    fields = []
    attrs = []
    for line in lines
        if @capture(line, name_ :: T_)
            map!(attrs, attrs) do (attr, value)
                if attr in (:validate, :coerce)
                    (attr, :($(name |> esc) -> $(value |> esc)))
                else
                    (attr, value)
                end
            end
            push!(fields, (name, T, attrs))
            attrs = []
        elseif line.head === :macrocall
            push!(attrs, (args[1], args[2]))
        else
            throw("expected field or macrocall")
        end
    end

    @esc head T
    quote
        struct $head
            $(fielddec.(fields)...)
        end
        function Property(data::$T; drawer=:default)
            data = (; $(propertycall.(fields)))
            StructProperty(data; drawer)
        end
    end
end