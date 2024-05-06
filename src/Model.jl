# ChangedEvent
ChangedEventKey = Union{Symbol, Int}
"Represents a change in a `ValueProperty`"
struct ChangedEvent{T, N}
    "`Observable` that was changed"
    source::Option{Observable{T}}
    "property/index path from listener to source"
    path::NTuple{N, ChangedEventKey}
end
ChangedEvent(source::Observable{T}, path::Vararg{ChangedEventKey, N}) where {T, N} = ChangedEvent{T, N}(source |> Some, path)
ChangedEvent{T}(path::Vararg{ChangedEventKey, N}) where {T, N} = ChangedEvent{T, N}(nothing, path)
ChangedEvent(prefix::ChangedEventKey, e::ChangedEvent) = ChangedEvent(e.source, prefix, e.path...)

Base.getindex(e::ChangedEvent) = map(getindex, e.source) |> something
path(e::ChangedEvent) = e.path
# end ChangedEvent

abstract type AbstractProperty end

# ValueProperty
"Property representing a single (terminal) value"
struct ValueProperty{T, TDrawer, FConvert, FValidate} <: AbstractProperty
    value::Observable{T}
    "ViewModel of the drawer. Should redraw GUI when changed"
    drawer::Observable{TDrawer}

    "convert from user values. U -> T where U"
    convert::FConvert
    "reject invalid values and/or coerce into valid range. (T, TDrawer) -> Result{T, E} where E"
    validate::FValidate

    listener::ObserverFunction
end
function ValueProperty(value::Observable{T};
    drawer::Observable{TDrawer} = Observable(missing),
    convert::FConvert = v -> convert(T, v),
    validate::FValidate = (v, _) -> Ok(v),
) where {T, TDrawer, FConvert, FValidate}
    listener = on(d -> value[] = validate(value[], d), drawer; weak = true)
    ValueProperty{T, TDrawer, FConvert, FValidate}(value, drawer, convert, validate, listener)
end

observable(p::ValueProperty) = p.value
value(p::ValueProperty) = p.value[]
drawer(p::ValueProperty) = p.drawer

Base.getindex(p::ValueProperty) = p.value[]
Base.setindex!(p::ValueProperty, value) = map(v -> p.value[] = v, p.validate(value |> p.convert, p.drawer[]))
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
    event = Observable{ChangedEvent}(ChangedEvent{Missing}())
    function register(name, obs)
        on(obs; weak = true) do value
            event[] = if value isa ChangedEvent
                ChangedEvent(name, value)
            else
                ChangedEvent(obs, name)
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
    event = Observable{ChangedEvent}(ChangedEvent{Missing}())
    listeners = map(enumerate(data)) do (idx, dat)
        obs = dat |> observable
        on(obs; weak = true) do value
            event[] = if value isa ChangedEvent
                ChangedEvent(idx, value)
            else
                ChangedEvent(obs, idx)
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

# TODO: create all obervables first, then make them available in validate/drawer context
"""
This macro will declare a data type to be used with `Property`.

# Examples
```julia
@model struct MyModel <: MyAbstractModel
    @validate min > max ? Ok(max) : Ok(min)
    min::Int
    @validate max < min ? Ok(min) : Ok(max)
    max::Int
    @drawer Slider(min, max)
    @validate clamp(value, min, max) |> Ok
    value::Int
    @validate myvalidator(data) ? Ok(data) : Err("data not valid")
    data::SubModel
end
```
"""
macro model(expr)
    struct FieldData
        name::Expr
        type::Expr
        validate::Option{Expr}
        drawer::Option{Expr}
    end
    function declare_field(f::FieldData)
        :($(f.name) :: $(f.type))
    end

    @capture(expr, struct head_ lines__ end) || throw("expected struct definition")
    T = head |> namify |> esc
    fields = []
    validate = nothing
    drawer = nothing
    for line in lines
        if line.head == :macrocall
            attr, body = line.args
            if attr == :validate
                validate = body |> esc
            elseif attr == :drawer
                drawer = body |> esc
            else
                throw("unrecognized attribute: expected validate or drawer, given $(attr)")
            end
        elseif @capture(line, field_ :: type_)
            @esc field type
            push!(fields, FieldData(field, type, validate, drawer))
            validate = drawer = nothing
        else
            throw("unexpected expression: expected macrocall or field declaration, given $(line)")
        end
    end
    # TODO: in validate/drawer, substitute otherfield -> otherfield[] (only when otherfield is a valid field)
    quote
        struct $head
            $(declare_field.(fields)...)
        end
        function Property(data::$T; kwargs...)
            # TODO: initialize all field proeprties (how to do this before callbacks are created?)
            # TODO: store observable from all fields in variable with name of field
            # TODO: create validate/drawer callbacks while capturing field observables
        end
    end
end