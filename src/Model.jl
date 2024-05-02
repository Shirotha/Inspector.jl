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
export Property
struct Property{T, FConvert, FValidate, FCoerce}
    name::Symbol
    value::Observable{T}
    drawer::Symbol # TODO: how to store drawer data properly

    "convert from user values. U -> T"
    convert::FConvert
    "reject invalid values. T -> Result{T, E} where E"
    validate::FValidate
    "modify incoming value before updating value. T -> T"
    coerce::FCoerce
end
function Property(name::Symbol, value::T;
    drawer::Symbol = :default,
    convert::FConvert = v -> convert(T, v),
    validate::FValidate = _ -> true,
    coerce::FCoerce = identity
) where {T, FConvert, FValidate, FCoerce}
    value = Observable(value; ignore_equal_values = true)
    Property{T, FConvert, FValidate, FCoerce}(name, value, drawer, convert, validate, coerce)
end

Base.getindex(p::Property) = p.value[]
Base.setindex!(p::Property, value) = map(v -> p.value[] = p.coerce(v), value |> p.convert |> p.validate)