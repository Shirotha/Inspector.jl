"convert property name to a human-readable display name"
function display_name(name::Symbol)
    name |> String |> s -> replace(s, r"_+" => " ") |> titlecase
end

export PropertyDrawer
"""
Base type for all drawers of `AbstractProperty` sub-types.

# Interface
- `DrawerType(::Type{MyViewModel}) = MyDrawer`: link view to view-model
"""
abstract type PropertyDrawer <: Widget end

"Type of view linked to a specific view-model"
DrawerType(::Type{T}) where {T} = error("no drawer registered for type $T")
DrawerType(::Observable{T}) where {T} = DrawerType(T)

export ValueDrawer
"""
Base type for all drawers of `ValueProperty`.
# Interface
- `MyValueDrawer(::Observable{MyViewModel}, ::ObservablePipe)`: setup drawer
- `SourceType(::Type{MyValueDrawer})`: specify type of data from GUI side
"""
abstract type ValueDrawer <: PropertyDrawer end

export StructDrawer
"""
Base type for all drawers of `StructProperty`.
# Interface
- `MyStructDrawer(::Observable{MyViewModel}, ::NamedTuple{Fields, NTuple{N, <:Widget}})`: setup drawer
"""
abstract type StructDrawer <: PropertyDrawer end

export ArrayDrawer
"""
Base type for all drawers of `StructProperty`.
# Interface
- `MyArrayDrawer(::Observable{MyViewModel}, ::Array{<:Widget})`: setup drawer
"""
abstract type ArrayDrawer <: PropertyDrawer end

export ObservableToggleButton
struct ObservableToggleButton <: Widget
    toggle::ToggleButton
    listener::ObserverFunction
end
function ObservableToggleButton(data::ObservablePipe{Bool})
    toggle = ToggleButton()
    set_is_active!(toggle, data |> backtrack)
    connect_signal_toggled!(toggle) do self
        data[] = get_is_active(self)
        nothing
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

export ObservableAdjustment
struct ObservableAdjustment
    adjustment::Adjustment
    listeners::Vector{ObserverFunction}
end
function ObservableAdjustment(
    value::Union{Number,ObservablePipe{<:Number}},
    lower::Union{Number,ObservablePipe{<:Number}},
    upper::Union{Number,ObservablePipe{<:Number}},
    increment::Union{Number,ObservablePipe{<:Number}}
)
    deref(x) = x isa ObservablePipe ? backtrack(x) : x

    adjustment = Adjustment(value |> deref, lower |> deref, upper |> deref, increment |> deref)
    listeners = ObserverFunction[]
    if value isa ObservablePipe
        connect_signal_value_changed!(adjustment) do self
            value[] = get_value(self)
            nothing
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

export ObservableEntry
struct ObservableEntry <: Widget
    entry::Entry
    listener::ObserverFunction
    error::ObserverFunction
end
function ObservableEntry(data::ObservablePipe{String})
    entry = Entry()
    set_text!(entry, data |> backtrack)
    connect_signal_text_changed!(entry) do _
        @debug "try update value $(data[]) -> $(get_text(entry))"
        data[] = get_text(entry)
        nothing
    end
    listener = on(data) do value
        @debug "value was changed to $(value)"
        # TODO: restore color
        set_tooltip_text!(entry, "")
        set_signal_text_changed_blocked!(entry, true)
        set_text!(entry, backtrack(data, value))
        set_signal_text_changed_blocked!(entry, false)
    end
    error = on(data.error) do error
        @debug error_message(error)
        # TODO: color red
        set_tooltip_text!(entry, error |> error_message)
    end
    ObservableEntry(entry, listener, error)
end
Mousetrap.get_top_level_widget(oe::ObservableEntry) = oe.entry

# TODO: define additional widgets

export EntryDrawer
struct EntryDrawer <: ValueDrawer
    entry::ObservableEntry
end
Mousetrap.get_top_level_widget(nfd::EntryDrawer) = nfd.entry
DrawerType(::Type{DefaultValueDrawer}) = EntryDrawer
SourceType(::Type{EntryDrawer}) = String
function EntryDrawer(::Observable{DefaultValueDrawer}, data::ObservablePipe{String})
    entry = ObservableEntry(data)
    EntryDrawer(entry)
end

export SimpleStructDrawer
struct SimpleStructDrawer <: StructDrawer
    root::Grid
    labels::Vector{Label}
    fields::Vector{<:Widget}
end
Mousetrap.get_top_level_widget(ssd::SimpleStructDrawer) = ssd.root
DrawerType(::Type{DefaultStructDrawer}) = SimpleStructDrawer
function SimpleStructDrawer(::Observable{DefaultStructDrawer}, fields::NamedTuple{Names}) where {Names}
    root = Grid()
    labels = [Label(name |> display_name) for name in Names]
    fields = [values(fields)...]
    for (row, (label, field)) in zip(labels, fields) |> enumerate
        Mousetrap.insert_at!(root, label, 1, row)
        Mousetrap.insert_at!(root, field, 2, row)
    end
    SimpleStructDrawer(root, labels, fields)
end

export SimpleArrayDrawer
struct SimpleArrayDrawer <: ArrayDrawer
    root::Box
    elements::Array{<:Widget}
end
Mousetrap.get_top_level_widget(sad::SimpleArrayDrawer) = sad.root
DrawerType(::Type{DefaultArrayDrawer}) = SimpleArrayDrawer
function SimpleArrayDrawer(::Observable{DefaultArrayDrawer}, elements::Array{<:Widget})
    root = Box(ORIENTATION_VERTICAL)
    set_horizontal_alignment!(root, ALIGNMENT_START)
    for element in elements
        push_back!(root, element)
    end
    SimpleArrayDrawer(root, elements)
end

# TODO: setup additional view-models/views

function PropertyDrawer(model::ValueProperty)
    Drawer = DrawerType(model)
    Drawer(model.drawer, model.value)
end
function PropertyDrawer(model::StructProperty{Names}) where {Names}
    children = NamedTuple{Names}(PropertyDrawer.(values(model.data)))
    Drawer = DrawerType(model)
    Drawer(model.drawer, children)
end
function PropertyDrawer(model::ArrayProperty)
    children = PropertyDrawer.(model.data)
    Drawer = DrawerType(model)
    Drawer(model.drawer, children)
end
