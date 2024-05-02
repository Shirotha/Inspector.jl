using Inspector, Test

@testset "Model" begin
    @testset "Property" begin
        import Inspector: Ok, Err
        validate(v) = v < 0 ? Err("can't be negative") : Ok(v)
        coerce(v) = clamp(v, 1:100)
        p = Property(:test, 0; validate, coerce)
        @test p[] == 0
        @test setindex!(p, 1) == Ok(1)
        @test setindex!(p, 101) == Ok(100)
        @test setindex!(p, -1) == Err("can't be negative")
    end
end