module Inspector

using Mousetrap
using Observables

# Result monad
struct Ok{T}
    value::T
end
struct Err{E}
    error::E
end
Result{T, E} = Union{Ok{T}, Err{E}}

ok(r::Ok) = r.value
ok(r::Err) = throw(r.error)
isok(r::Ok) = true
isok(r::Err) = false
Base.map(f, r::Ok) = Ok(f(r.value))
Base.map(f, r::Err) = r
# end Result

include("Model.jl")

end # module Inspector
