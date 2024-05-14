"""
Base type for all drawers of `AbstractProperty` sub-types.

# Interface
- `DrawerType(MyViewModel) = MyDrawer`: link view to view-model
- `MyDrawer(::MyViewModel)`: setup drawer
"""
abstract type PropertyDrawer <: Widget end

"Type of view linked to a specific view-model"
DrawerType(::Type{T}) where T = error("no drawer registered for type $T")


"""
Base type for all drawers of `ValueProperty`.
# Interface
- `MyValueDrawer(::MyViewModel, ::ObservablePipe)`: setup drawer
"""
abstract type ValueDrawer <: PropertyDrawer end


struct ObservableToggleButton <: Widget
    toggle::ToggleButton
    listener::ObserverFunction
end
function ObservableToggleButton(data::ObservablePipe{Bool})
    toggle = ToggleButton()
    set_is_active!(toggle, data |> backtrack)
    connect_signal_toggled!(toggle) do self
        data[] = get_is_active(self)
    end
    listener = on(data) do value
        set_signal_toggled_blocked!(toggle, true)
        set_is_active!(toggle, backtrack(data, value))
        set_signal_toggled_blocked!(toggle, false)
    end
    ObservableToggleButton(toggle, listener)
end
Mousetrap.get_top_level_widget(otb::ObservableToggleButton) = otb.toggle
# TODO: implement other bool widgets

struct ObservableAdjustment
    adjustment::Adjustment
    listeners::Vector{ObserverFunction}
end
function ObservableAdjustment(
    value::Union{Number, ObservablePipe{<:Number}},
    lower::Union{Number, ObservablePipe{<:Number}},
    upper::Union{Number, ObservablePipe{<:Number}},
    increment::Union{Number, ObservablePipe{<:Number}}
)
    deref(x) = x isa ObservablePipe ? backtrack(x) : x

    adjustment = Adjustment(value |> deref, lower |> deref, upper |> deref, increment |> deref)
    listeners = ObserverFunction[]
    if value isa ObservablePipe
        connect_signal_value_changed!(adjustment) do self
            value[] = get_value(self)
        end
        push!(listeners, on(value) do val
            set_signal_value_changed_blocked!(adjustment, true)
            set_value!(adjustment, backtrack(value, val))
            set_signal_value_changed_blocked!(adjustment, false)
        end)
    end
    if lower isa ObservablePipe
        push!(listeners, on(lower) do low
            set_lower!(adjustment, backtrack(lower, low))
        end)
    end
    if upper isa ObservablePipe
        push!(listeners, on(upper) do up
            set_upper!(adjustment, backtrack(upper, up))
        end)
    end
    if increment isa ObservablePipe
        push!(listeners, on(increment) do inc
            set_step_increment!(adjustment, backtrack(increment, inc))
        end)
    end
    ObservableAdjustment(adjustment, listeners)
end
Mousetrap.get_adjustment(oa::ObservableAdjustment) = oa.adjustment

struct ObservableEntry <: Widget
    entry::Entry
    listener::ObserverFunction
    error::ObserverFunction
end
function ObservableEntry(data::ObservablePipe{String})
    entry = Entry()
    connect_signal_text_changed!(entry) do self
        data[] = get_text(self)
    end
    listener = on(data) do value
        # TODO: restore color
        set_tooltip_text!(entry, "")
        set_signal_text_changed_blocked!(entry, true)
        set_text!(entry, backtrack(data, value))
        set_signal_text_changed_blocked!(entry, false)
    end
    error = on(data.error) do error
        # TODO: color red
        set_tooltip_text!(entry, error |> error_message)
    end
    ObservableEntry(entry, listener, error)
end
Mousetrap.get_top_level_widget(oe::ObservableEntry) = oe.entry

# TODO: define additional widgets

# TODO: setup default view-models/views