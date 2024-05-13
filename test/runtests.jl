using Inspector, Test

@testset "Model" begin
    using Observables
    import Inspector: Ok, Err, ValueProperty, StructProperty, ArrayProperty, path, ValidationError, lasterror, ObservablePipe
    @testset "ValueProperty" begin
        import Inspector: Ok, Err, ValueProperty
        validate(v) = v < 0 ? Err("can't be negative") : clamp(v, 1:100) |> Ok
        p = ValueProperty(10; validate)
        @test p[] == 10
        p[] = 1
        @test p[] == 1
        p[] = 101
        @test p[] == 100
        p[] = -1
        @test p[] == 100
        @test lasterror(p)[] == ValidationError(-1, "can't be negative")
    end
    @testset "StructProperty" begin
        p1 = ValueProperty(1)
        p2 = ValueProperty(2)
        p = StructProperty(; a = p1, b = p2)
        @test p[:a] == p1
        @test p[:b] == p2
        p[:a][] = 3
        @test p1[] == 3
        @test p.event[][] == 3
        @test p.event[] |> path == (:a,)
    end
    @testset "ArrayProperty" begin
        ps = ValueProperty.(rand(1:10, 3, 2))
        p = ArrayProperty(ps)
        @test p[2] == ps[2]
        ps[4][] = 11
        @test p[4][] == 11
        @test p.event[][] == 11
        @test p.event[] |> path == (4,)
    end
    @testset "Dependencies (Manual)" begin
        raw_min = Observable(1; ignore_equal_values = true)
        min = deepcopy(raw_min)
        raw_max = Observable(100; ignore_equal_values = true)
        max = deepcopy(raw_max)
        raw_value = Observable(50; ignore_equal_values = true)
        value = deepcopy(raw_value)
        validate_min(v) = Ok(v > max[] ? max[] : v)
        validate_max(v) = Ok(v < min[] ? min[] : v)
        validate_value(v) = clamp(v, min[], max[]) |> Ok
        on(min) do _
            notify(raw_max)
            notify(raw_value)
        end
        on(max) do _
            notify(raw_min)
            notify(raw_value)
        end
        data = StructProperty(
            min = ValueProperty(raw_min, min; convert=identity, validate=validate_min),
            max = ValueProperty(raw_max, max; convert=identity, validate=validate_max),
            value = ValueProperty(raw_value, value; convert=identity, validate=validate_value)
        )
        data[:value][] = 150
        @test data[:value][] == 100
        data[:max][] = 200
        data[:value][] = 150
        @test data[:value][] == 150
        data[:max][] = 0
        @test data[:max][] == 1
        @test data[:value][] == 1
    end
    @testset "Dependencies (Macro)" begin
        @model struct Data
            @validate Ok(min > max ? max : min)
            min::Int
            @validate Ok(max < min ? min : max)
            max::Int
            @validate clamp(value, min, max) |> Ok
            value::Int
        end
        data = Data(1, 100, 50)
        data = inspect(data)
        data[:value][] = 150
        @test data[:value][] == 100
        data[:max][] = 200
        data[:value][] = 150
        @test data[:value][] == 150
        data[:max][] = 0
        @test data[:max][] == 1
        @test data[:value][] == 1
        @test data[] == Data(1, 1, 1)
    end
end