"convert property name to a human-readable display name"
function display_name(name::Symbol)
    name |> String |> s -> replace(s, r"_+" => " ") |> titlecase
end

"""
Base type for all drawers of `AbstractProperty` sub-types.

# Interface
- `DrawerType(MyViewModel) = MyDrawer`: link view to view-model
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

"""
Base type for all drawers of `StructProperty`.
# Interface
- `MyStructDrawer(::MyViewModel, ::NamedTuple{Fields, NTuple{N, <:Widget}})`: setup drawer
"""
abstract type StructDrawer <: PropertyDrawer end

"""
Base type for all drawers of `StructProperty`.
# Interface
- `MyArrayDrawer(::MyViewModel, ::Array{<:Widget})`: setup drawer
"""
abstract type ArrayDrawer <: PropertyDrawer end

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

struct EntryDrawer <: ValueDrawer
    entry::ObservableEntry
end
Mousetrap.get_top_level_widget(nfd::EntryDrawer) = nfd.entry
DrawerType(::DefaultValueDrawer) = EntryDrawer
function EntryDrawer(::DefaultValueDrawer, data::ObservablePipe{String})
    entry = ObservableEntry(data)
    EntryDrawer(entry)
end

struct SimpleStructDrawer <: StructDrawer
    root::Box
    label_box::Box
    labels::Vector{Label}
    field_box::Box
    fields::Vector{<:Widget}
end
Mousetrap.get_top_level_widget(ssd::SimpleStructDrawer) = ssd.root
DrawerType(::DefaultStructDrawer) = SimpleStructDrawer
function SimpleStructDrawer(::DefaultStructDrawer, fields::NamedTuple{Names, <:Widget}) where Names
    root = Box(ORIENTATION_HORIZONTAL)
    label_box = Box(ORIENTATION_VERTICAL)
    set_horizontal_alignment!(label_box, ALIGNMENT_START)
    push_front!(root, label_box)
    labels = [Label(name |> display_name) for name in Names]
    for label in labels push_back!(label_box, label) end
    field_box = Box(ORIENTATION_VERTICAL)
    set_horizontal_alignment!(field_box, ALIGNMENT_END)
    push_back!(root, field_box)
    fields = [values(fields)...]
    for field in fields push_back!(field_box, field) end
    SimpleStructDrawer(root, label_box, labels, field_box, fields)
end

struct SimpleArrayDrawer <: ArrayDrawer
    root::Box
    elements::Array{<:Widget}
end
Mousetrap.get_top_level_widget(sad::SimpleArrayDrawer) = sad.root
DrawerType(::DefaultArrayDrawer) = SimpleArrayDrawer
function SimpleArrayDrawer(::DefaultArrayDrawer, elements::Array{<:Widget})
    root = Box(ORIENTATION_VERTICAL)
    set_horizontal_alignment!(ALIGNMENT_START)
    for element in elements push_back!(root, element) end
    SimpleArrayDrawer(root, elements)
end

# TODO: setup additional view-models/views