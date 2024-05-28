# Inspector

Generic property inspector for [Mousetrap](https://github.com/clemapfel/mousetrap.jl).

## Running Examples

To run the examples, open the project in the julia REPL and run

```julia
include("examples/range.jl")
Range.run()
```

To run directly from the terminal in debug mode

```sh
'include("examples/range.jl"); Range.run()' | JULIA_DEBUG=Inspector julia --project=.
```
