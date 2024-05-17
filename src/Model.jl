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
    "process `input` into into either `output` (`Ok`) or `error` (`Err`)"
    map
    "revert `output` into valid `input` (this new input should produce the same output when reassigned)"
    backtrack
    listener::ObserverFunction
end
function ObservablePipe(
    input::AbstractObservable{S},
    output::AbstractObservable{T},
    error::AbstractObservable{E};
    map = Ok,
    backtrack = identity
) where {S, T, E}
    listener = on(input; weak = true) do value
        unwrap(ok -> output[] = ok, err -> error[] = err, map(value))
    end
    ObservablePipe{S, T, E}(input, output, error, map, backtrack, listener)
end

Observables.observe(o::ObservablePipe) = o.output
Observables.off(o::ObservablePipe) = off(o.input, o.listener)

Base.getindex(o::ObservablePipe) = o.output[]
Base.setindex!(o::ObservablePipe{S}, value::S) where S = o.input[] = value

backtrack(o::ObservablePipe) = o.output[] |> o.backtrack
backtrack(o::ObservablePipe, value) = value |> o.backtrack
# end

# error types
struct ConversionError <: Exception
    val
    target
end
error_message(ex::ConversionError) = string("failed to convert ", ex.val, " to ", ex.target)
Base.showerror(io::IO, ex::ConversionError) = print(io, "failed to convert ", ex.val, " to ", ex.target)

struct ValidationError <: Exception
    val
    msg
end
error_message(ex::ValidationError) = string(ex.val, " failed to validate: ", ex.msg)
Base.showerror(io::IO, ex::ValidationError) = print(io, ex.val, " failed to validate: ", ex.msg)

error_message(::Nothing) = ""
# end

struct DefaultValueDrawer end
DefaultDrawer(::Type) = DefaultValueDrawer()
struct DefaultStructDrawer end
struct DefaultArrayDrawer end

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
    drawer::Observable{TDrawer} = S |> DefaultDrawer |> Observable,
    convert = v -> convert(T, v),
    validate = Ok,
    backtrack = v -> convert(S, v)
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
    value = ObservablePipe(input, output, error; map, backtrack)
    ValueProperty{S, T, TDrawer}(value, drawer)
    ValueProperty{S, T, TDrawer}(value, drawer)
end
function ValueProperty{T}(
    default::S;
    drawer::TDrawer = S |> DefaultDrawer,
    convert = v -> convert(T, v),
    validate = Ok,
    backtrack = v -> convert(S, v)
) where {S, T, TDrawer}
    input = Observable{S}(default)
    output = Observable{T}(default |> map |> ok)
    drawer = Observable(drawer)
    ValueProperty(input, output; drawer, convert, validate, backtrack)
end
function ValueProperty(
    default::T;
    drawer::TDrawer = T |> DefaultDrawer,
    validate = Ok
) where {T, TDrawer}
    input = Observable{T}(default)
    output = Observable{T}(default |> validate |> ok)
    drawer = Observable(drawer)
    ValueProperty(input, output; drawer, convert = identity, validate, backtrack = identity)
end

observable(p::ValueProperty) = p.value.output
value(p::ValueProperty) = p.value[]
drawer(p::ValueProperty) = p.drawer
lasterror(p::ValueProperty) = p.value.error
raw(p::ValueProperty) = backtrack(p.value)

Base.getindex(p::ValueProperty) = p.value[]
Base.setindex!(p::ValueProperty, value) = p.value[] = value
# end Property

# StructProperty
"Property representing heterogeneous data with named fields"
struct StructProperty{Names, T, TDrawer, TDeref} <: AbstractProperty
    data::NamedTuple{Names, T}
    event::Observable{ChangedEvent}
    drawer::Observable{TDrawer}

    deref::TDeref

    listeners::Vector{ObserverFunction}
end
function StructProperty(
    data::NamedTuple{Names, T};
    drawer::Observable{TDrawer} = DefaultStructDrawer() |> Observable,
    deref::TDeref = identity
) where {Names, T, TDrawer, TDeref}
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
    StructProperty{Names, T, TDrawer, TDeref}(data, event, drawer, deref, listeners)
end
StructProperty(; data...) = StructProperty((; data...))

observable(p::StructProperty) = p.event
value(p::StructProperty{Names}) where Names = NamedTuple{Names}(value.(p.data |> values))

Base.getindex(p::StructProperty, name::Symbol) = p.data[name]
Base.getindex(p::StructProperty) = p.deref(p.data)
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
    drawer::Observable{TDrawer} = DefaultArrayDrawer() |> Observable
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

export inspect
inspect(data) = error("no model registered with data of type $(data |> typeof)")

struct FieldInfo{T}
    name::Symbol
    type::Union{Symbol, Expr}
    convert::Option{T}
    validate::Option{T}
    backtrack::Option{T}
    drawer::Option{T}
end
struct FunctionInfo
    body::Expr
    deps::Set{Symbol}
end

export @model
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
            if !(expr isa Symbol) || expr == this || !(expr in fields)
                return expr
            end
            push!(deps, expr)
            :($expr[])
        end
        (body, deps)
    end
    function parse_state(body, fields)
        args = Set{Symbol}()
        body = postwalk(body) do expr
            if expr isa Symbol && expr in fields
                push!(args, expr)
            end
            expr
        end
        (body, args)
    end

    function esc_fielddec(field)
        :($(field.name |> esc)::$(field.type |> esc))
    end
    function esc_initobs(field)
        :(if PropertyType($(field.type)) == ValueProperty
            $(field.name |> esc) = Observable(getfield(data, $(field.name |> QuoteNode)); ignore_equal_values = true)
            $(Symbol("raw_", field.name) |> esc) = Observable(getfield(data, $(field.name |> QuoteNode)); ignore_equal_values = true)
        else
            # FIXME: circular dependency: {field} needs drawer_{field}, and drawer_{field} needs {field} (only ValueDrawers should be able to register callbacks)
            $(field.name |> esc) = inspect(getfield(data, $(field.name |> QuoteNode)); drawer = $(Symbol("drawer_", field.name)))
        end)
    end
    function esc_defconvert(field)
        body = unwrap(
            c -> c.body |> esc,
            () -> :(convert($(field.type |> esc), $(field.name |> esc))),
            field.convert
        )
        :($(Symbol("convert_", field.name) |> esc)(
            $(field.name |> esc)
        ) = $body)
    end
    function esc_defvalidate(field)
        body = unwrap(
            v -> v.body |> esc,
            () -> :(Ok($(field.name |> esc))),
            field.validate
        )
        :($(Symbol("validate_", field.name) |> esc)(
            $(field.name |> esc)
        ) = $body)
    end
    function esc_backtrack(field)
        body = unwrap(
            v -> v.body |> esc,
            () -> :(convert($(field.type |> esc), $(field.name |> esc))),
            field.backtrack
        )
        :($(Symbol("backtrack_", field.name) |> esc)(
            $(field.name |> esc)
        ) = $body)
    end
    function esc_notify(name)
        :(notify($(Symbol("raw_", name) |> esc)))
    end
    function esc_registerdeps(name, deps)
        if isempty(deps[name])
            return missing
        end
        :(on($(name |> esc); weak = true) do _
            $(esc_notify.(deps[name])...)
        end)
    end
    function esc_drawerdeps(field; deref=false)
        unwrap(() -> (), field.drawer) do drawer
            map(drawer.deps) do name
                deref ? :($(name |> esc)[]) : esc(name)
            end
        end
    end
    function esc_drawerarg(field)
        unwrap(identity, () -> :($(field.type |> esc) |> DefaultDrawer), field.drawer)
    end
    function esc_initdrawer(field)
        quote
            $(Symbol("drawer_", field.name, "_update"))($(esc_drawerdeps(field)...)) = $(esc_drawerarg(field))
            $(Symbol("drawer_", field.name) |> esc) = Observable($(Symbol("drawer_", field.name, "_update"))($(esc_drawerdeps(field; deref = true)...)); ignore_equal_values = true)
            # TODO: register onany callback if drawerdeps is not empty (only for ValueProperty, other properties are not allowed to have deps on drawer)
        end
    end
    function esc_localfield(field)
        :(getfield(this, $(field.name |> QuoteNode))[])
    end
    function esc_initderef(type, fields)
        :(deref(this) = $(type |> esc)(
            $(esc_localfield.(fields)...)
        ))
    end
    function esc_initfield(field)
        :($(field.name |> esc) = $(field.name |> esc) isa AbstractProperty ? $(field.name |> esc)
            : ValueProperty(
                $(Symbol("raw_", field.name) |> esc),
                $(field.name |> esc),
                convert = $(Symbol("convert_", field.name) |> esc),
                validate = $(Symbol("validate_", field.name) |> esc),
                backtrack = $(Symbol("backtrack_", field.name) |> esc),
                drawer = $(Symbol("drawer_", field.name) |> esc)
            ))
    end

    @capture(expr, struct head_ lines__ end) || error("expected struct definition")

    fields = FieldInfo{Expr}[]
    convert::Option{Expr} = nothing
    validate::Option{Expr} = nothing
    backtrack::Option{Expr} = nothing
    drawer::Option{Expr} = nothing
    for line in lines
        if @capture(line, name_ :: type_)
            push!(fields, FieldInfo{Expr}(name, type, convert, validate, backtrack, drawer))
            convert = validate = drawer = nothing
        elseif line.head == :macrocall
            name, node, body = line.args
            # TODO: preserve line numbers for debugging
            @assert node isa LineNumberNode
            if name == Symbol("@convert")
                convert = Some(body)
            elseif name == Symbol("@validate")
                validate = Some(body)
            elseif name == Symbol("@backtrack")
                backtrack = Some(body)
            elseif name == Symbol("@drawer")
                drawer = Some(body)
            else
                error("unknown attribute $(name)")
            end
        else
            error("unrecognized expression")
        end
    end

    names = getfield.(fields, :name)
    fields = map(fields) do field
        c = map(field.convert) do c
            FunctionInfo(parse_callback(field.name, c, names)...)
        end
        v = map(field.validate) do v
            FunctionInfo(parse_callback(field.name, v, names)...)
        end
        b = map(field.backtrack) do b
            FunctionInfo(parse_callback(field.name, b, names)...)
        end
        d = map(field.drawer) do d
            FunctionInfo(parse_state(d, names)...)
        end
        FieldInfo{FunctionInfo}(field.name, field.type, c, v, b, d)
    end
    notifydeps = Dict{Symbol, Set{Symbol}}()
    for name in names
        notify = Set{Symbol}()
        for field in fields
            if field.name == name continue end
            map(field.convert) do c
                if name in c.deps
                    push!(notify, field.name)
                end
            end
            map(field.validate) do v
                if name in v.deps
                    push!(notify, field.name)
                end
            end
        end
        notifydeps[name] = notify
    end

    quote
        struct $(head |> esc)
            $(esc_fielddec.(fields)...)
        end
        Inspector.PropertyType(::Type{$(head |> namify |> esc)}) = StructProperty
        # TODO: handle cases with generic head (might refer to type parameters inside callbacks)
        function Inspector.inspect(data::$(head |> namify |> esc); drawer = Observable(missing))
            $(esc_initobs.(fields)...)
            $(esc_defconvert.(fields)...)
            $(esc_defvalidate.(fields)...)
            $(esc_backtrack.(fields)...)
            listeners = [$(skipmissing(esc_registerdeps.(names, (notifydeps,)))...)]
            $(esc_initdrawer.(fields)...)
            $(esc_initderef(head |> namify, fields))
            result = StructProperty((;$(esc_initfield.(fields)...)); drawer, deref)
            append!(result.listeners, listeners)
            result
        end
    end
end