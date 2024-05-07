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

# ObervablePipe
struct ObservablePipe{S, T, E} <: AbstractObservable{T}
    input::Observable{S}
    output::Observable{T}
    error::Observable{E}
    map
    listener::ObserverFunction
end
function ObservablePipe(
    input::AbstractObservable{S},
    output::AbstractObservable{T},
    error::AbstractObservable{E};
    map = Ok
) where {S, T, E}
    listener = on(input; weak = true) do value
        unwrap(ok -> output[] = ok, err -> error[] = err, map(value))
    end
    ObservablePipe{S, T, E}(input, output, error, map, listener)
end

Observables.observe(o::ObservablePipe) = o.output
Observables.off(o::ObservablePipe) = off(o.input, o.listener)

Base.getindex(o::ObservablePipe) = o.output[]
Base.setindex!(o::ObservablePipe{S}, value::S) where S = o.input[] = value
# end

# error types
struct ConversionError <: Exception
    val
    target
end
Base.showerror(io::IO, ex::ConversionError) = print(io, "failed to convert ", ex.val, " to ", ex.target)

struct ValidationError <: Exception
    val
    msg
end
Base.showerror(io::IO, ex::ValidationError) = print(io, ex.val, " failed to validate: ", ex.msg)
# end

abstract type AbstractProperty end

# ValueProperty
# TODO: convert T -> S for rendering to GUI
"Property representing a single (terminal) value"
struct ValueProperty{S, T, TDrawer} <: AbstractProperty
    value::ObservablePipe{S, T, Union{Nothing, ConversionError, ValidationError}}
    "ViewModel of the drawer. Should redraw GUI when changed"
    drawer::Observable{TDrawer}
end
function ValueProperty(
    input::AbstractObservable{S},
    output::AbstractObservable{T};
    drawer::Observable{TDrawer} = Observable(missing),
    convert = v -> convert(T, v),
    validate = Ok
) where {S, T, TDrawer}
    function map(v::S)
        converted =
            try
                convert(v)
            catch e
                return Err(ConversionError(v, T))
            end
        maperr(err -> ValidationError(converted, err), validate(converted))
    end
    error = Observable{Union{Nothing, ConversionError, ValidationError}}(nothing)
    value = ObservablePipe(input, output, error; map)
    ValueProperty{S, T, TDrawer}(value, drawer)
    ValueProperty{S, T, TDrawer}(value, drawer)
end
function ValueProperty{T}(
    default::S;
    drawer::TDrawer = missing,
    convert = v -> convert(T, v),
    validate = Ok
) where {S, T, TDrawer}
    input = Observable{S}(default)
    output = Observable{T}(default |> map |> ok)
    drawer = Observable(drawer)
    ValueProperty(input, output; drawer, convert, validate)
end
function ValueProperty(
    default::T;
    drawer::TDrawer = missing,
    validate = Ok
) where {T, TDrawer}
    input = Observable{T}(default)
    output = Observable{T}(default |> validate |> ok)
    drawer = Observable(drawer)
    ValueProperty(input, output; drawer, convert = identity, validate)
end

observable(p::ValueProperty) = p.value.output
value(p::ValueProperty) = p.value[]
drawer(p::ValueProperty) = p.drawer
error(p::ValueProperty) = p.value.error

Base.getindex(p::ValueProperty) = p.value[]
Base.setindex!(p::ValueProperty, value) = p.value[] = value
# end Property

# StructProperty
"Property representing heterogeneous data with named fields"
struct StructProperty{Names, T, TDrawer} <: AbstractProperty
    data::NamedTuple{Names, T}
    event::Observable{ChangedEvent}
    drawer::Observable{TDrawer}

    listeners::Vector{ObserverFunction}
end
function StructProperty(
    data::NamedTuple{Names, T};
    drawer::Observable{TDrawer} = Observable(missing)
) where {Names, T, TDrawer}
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
    StructProperty{Names, T, TDrawer}(data, event, drawer, listeners)
end
StructProperty(; data...) = StructProperty((; data...))

observable(p::StructProperty) = p.event
value(p::StructProperty{Names}) where Names = NamedTuple{Names}(value.(p.data |> values))

Base.getindex(p::StructProperty, name::Symbol) = p.data[name]
# end SructProperty

# ArrayProperty
"Property representing homogeneous data with index access"
struct ArrayProperty{T, N, TDrawer} <: AbstractProperty
    data::Array{T, N}
    event::Observable{ChangedEvent}
    drawer::Observable{TDrawer}

    listeners::Array{ObserverFunction, N}
end
function ArrayProperty(
    data::Array{T, N};
    drawer::Observable{TDrawer} = Observable(missing)
) where {T, N, TDrawer}
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
    ArrayProperty{T, N, TDrawer}(data, event, drawer, listeners)
end

observable(p::ArrayProperty) = p.event
value(p::ArrayProperty) = value.(p.data)

Base.getindex(p::ArrayProperty, idx...) = p.data[idx...]

# TODO: implment adding/removing elements
# end ArrayProperty

"This should return a subtype of `AbstractProperty` that should be used to represent data of type `T`"
PropertyType(T::Type) = ValueProperty

struct FieldInfo
    name::Symbol
    type::Expr
    convert::Option{Expr}
    validate::Option{Expr}
    drawer::Option{Expr}
end
function FieldInfo(name::Symbol, type::Expr=Any;
    convert::Option{Expr} = nothing,
    validate::Option{Expr} = nothing,
    drawer::Option{Expr} = nothing
)
    FieldInfo(name, type, convert, validate, drawer)
end
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
    function parse_callback(this::Symbol, body, fields)
        deps = Set{Symbol}()
        body = postwalk(body) do expr
            if !(expr isa Symbol) || (expr in fields && expr != this)
                return expr
            end
            push!(deps, expr)
            :($expr[])
        end
        (:($this -> $body), deps)
    end

    @capture(expr, struct head_ lines__ end) || error("expected struct definition")
    T = head |> namify |> esc

    fields = Vector{FieldInfo}
    convert::Option{Expr} = nothing
    validate::Option{Expr} = nothing
    drawer::Option{Expr} = nothing
    for line in lines
        if @capture(line, name_ :: type_)
            if name in keys(fields)
                error("field $(name) already exists")
            end
            push!(fields, FieldInfo(name, type; convert, validate, drawer))
            convert = validate = drawer = nothing
        elseif line.head == :macrocall
            name, body = line.args
            if name == :convert
                convert = body
            elseif name == :validate
                validate = body
            elseif name == :drawer
                drawer = body
            else
                error("unknown attribute $(name)")
            end
        else
            error("unrecognized expression")
        end
    end
    names = getfield.(fields, :name)

    # TODO: build type for plain data named T
    # TODO: implement inspect overload for type T
        # TODO: create new observables for fields with PropertyType == ValueProperty and grab existing observables from other fields
        # TODO: define convert/validate callbacks for ValueProperty fields
        # TODO: register listeners to notify dependencies of fields
        # TODO: construct StructProperty from all fields

end