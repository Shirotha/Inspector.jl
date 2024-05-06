using Inspector, Test

@testset "Model" begin
    using Observables
    import Inspector: Ok, Err, ValueProperty, StructProperty, ArrayProperty, path
    @testset "ValueProperty" begin
        import Inspector: Ok, Err, ValueProperty
        validate(v, _) = v < 0 ? Err("can't be negative") : clamp(v, 1:100) |> Ok
        p = ValueProperty(Observable(0); validate)
        @test p[] == 0
        @test setindex!(p, 1) == Ok(1)
        @test setindex!(p, 101) == Ok(100)
        @test setindex!(p, -1) == Err("can't be negative")
    end
    @testset "StructProperty" begin
        p1 = ValueProperty(Observable(1))
        p2 = ValueProperty(Observable(2))
        p = StructProperty(; a = p1, b = p2)
        @test p[:a] == p1
        @test p[:b] == p2
        @test setindex!(p[:a], 3) == Ok(3)
        @test p1[] == 3
        @test p.event[][] == 3
        @test p.event[] |> path == (:a,)
    end
    @testset "ArrayProperty" begin
        ps = ValueProperty.(Observable.(rand(1:10, 3, 2)))
        p = ArrayProperty(ps)
        @test p[2] == ps[2]
        @test setindex!(ps[4], 11) == Ok(11)
        @test p[4][] == 11
        @test p.event[][] == 11
        @test p.event[] |> path == (4,)
    end
end