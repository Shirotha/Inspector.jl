using Inspector, Test

@testset "Model" begin
    @testset "ValueProperty" begin
        import Inspector: Ok, Err, ValueProperty
        validate(v) = v < 0 ? Err("can't be negative") : Ok(v)
        coerce(v) = clamp(v, 1:100)
        p = ValueProperty(0; validate, coerce)
        @test p[] == 0
        @test setindex!(p, 1) == Ok(1)
        @test setindex!(p, 101) == Ok(100)
        @test setindex!(p, -1) == Err("can't be negative")
    end
    @testset "StructProperty" begin
        import Inspector: Ok, Err, ValueProperty, StructProperty, ChangedEvent
        p1 = ValueProperty(1)
        p2 = ValueProperty(2)
        p = StructProperty(; a = p1, b = p2)
        @test p[:a] == p1
        @test p[:b] == p2
        @test setindex!(p[:a], 3) == Ok(3)
        @test p1[] == 3
        @test p.event[] == ChangedEvent(:a)
    end
    @testset "ArrayProperty" begin
        import Inspector: Ok, Err, ValueProperty, ArrayProperty, ChangedEvent
        ps = ValueProperty.(rand(1:10, 3, 2))
        p = ArrayProperty(ps)
        @test p[2] == ps[2]
        @test setindex!(ps[4], 11) == Ok(11)
        @test p[4][] == 11
        @test p.event[] == ChangedEvent(4)
    end
end