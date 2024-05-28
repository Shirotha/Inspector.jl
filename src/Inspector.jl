module Inspector

using Mousetrap, Observables
using MacroTools
import MacroTools: postwalk

# Option monad
export Option, issomething, unwrap
Option{T} = Union{Some{T},Nothing}

issomething(x) = !isnothing(x)
Base.map(f, o::Some) = o |> something |> f |> Some
Base.map(f, ::Nothing) = nothing
unwrap(f, g, o::Some) = o |> something |> f
unwrap(f, g, ::Nothing) = g()
# end Option

# Result monad
export Ok, Err, Result, ok, isok, unwrap, maperr
struct Ok{T}
    value::T
end
struct Err{E}
    error::E
end
Result{T,E} = Union{Ok{T},Err{E}}

ok(r::Ok) = r.value
ok(r::Err) = throw(r.error)
isok(r::Ok) = true
isok(r::Err) = false
Base.map(f, r::Ok) = r |> ok |> f |> Ok
Base.map(f, r::Err) = r
unwrap(f, g, r::Ok) = f(r.value)
unwrap(f, g, r::Err) = g(r.error)
maperr(f, r::Ok) = r
maperr(f, r::Err) = r.error |> f |> Err
# end Result

include("Model.jl")
include("Drawer.jl")

end # module Inspector
