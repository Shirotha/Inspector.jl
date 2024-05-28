module Range

include("../src/Inspector.jl")
using .Inspector, Mousetrap

@model struct RangeModel
    @validate Ok(min > max ? max : min)
    min::Int
    @validate Ok(max < min ? min : max)
    max::Int
    @validate clamp(value, min, max) |> Ok
    value::Int
end

export run
function run()
    model = RangeModel(1, 100, 50)
    viewmodel = inspect(model)
    main() do app::Application
        view = PropertyDrawer(viewmodel)

        set_current_theme!(app, THEME_DEFAULT_DARK)
        window = Window(app)
        set_child!(window, view)
        present!(window)
    end
    model = viewmodel[]
    @show model
    nothing
end
end
