defmodule Blex.Bench.Comparison do
  def loop(0, x, _), do: x

  def loop(n, x, f) do
    loop(n - 1, f.(x), f)
  end

  @capacity 1_000_000
  @false_positive_probability 0.01
  @n 1_000_000

  def run_estimation() do
    Benchee.run(%{
      "Blex.estimate_size?" =>
        {fn b ->
           Blex.estimate_size(b)
         end,
         before_each: fn _ ->
           b = Blex.new(@capacity, @false_positive_probability)

           loop(@n, b, fn b ->
             Blex.put(b, :rand.uniform(1000_000))
             b
           end)

           b
         end},
      "Blex.estimate_size? with binary format" =>
        {fn b ->
           Blex.estimate_size(b)
         end,
         before_each: fn _ ->
           b = Blex.new(@capacity, @false_positive_probability)

           loop(@n, b, fn b ->
             Blex.put(b, :rand.uniform(1000_000))
             b
           end)

           Blex.encode(b)
         end}
    })
  end

  def run_serialization() do
    Benchee.run(%{
      "Blex.encode" =>
        {fn b ->
           Blex.encode(b)
         end,
         before_each: fn _ ->
           Blex.new(@capacity, @false_positive_probability)
         end},
      "Blex.decode" =>
        {fn encoded ->
           Blex.decode(encoded)
         end,
         before_each: fn _ ->
           Blex.new(@capacity, @false_positive_probability)
           |> Blex.encode()
         end},
      "Blex.merge" =>
        {fn list ->
           Blex.merge(list)
         end,
         before_each: fn _ ->
           b1 = Blex.new(@capacity, @false_positive_probability)
           b2 = Blex.new(@capacity, @false_positive_probability)
           [b1, b2]
         end},
      "Blex.merge_encode" =>
        {fn list ->
           Blex.merge_encode(list)
         end,
         before_each: fn _ ->
           b1 = Blex.new(@capacity, @false_positive_probability)
           b2 = Blex.new(@capacity, @false_positive_probability)
           [b1, b2]
         end}
    })
  end

  def run_read_operation() do
    Benchee.run(%{
      "Bloomex.members?" =>
        {fn b ->
           loop(@n, b, fn b ->
             Bloomex.member?(b, :rand.uniform(1000_000))
             b
           end)
         end,
         before_each: fn _ ->
           b = Bloomex.plain(@capacity, @false_positive_probability)

           loop(@n, b, fn b ->
             Bloomex.add(b, :rand.uniform(1000_000))
           end)
         end},
      "Blex.members?" =>
        {fn b ->
           loop(@n, b, fn b ->
             Blex.member?(b, :rand.uniform(1000_000))
             b
           end)
         end,
         before_each: fn _ ->
           b = Blex.new(@capacity, @false_positive_probability)

           loop(@n, b, fn b ->
             Blex.put(b, :rand.uniform(1000_000))
             b
           end)

           b
         end},
      "Blex.members? with binary format" =>
        {fn b ->
           loop(@n, b, fn b ->
             Blex.member?(b, :rand.uniform(1000_000))
             b
           end)
         end,
         before_each: fn _ ->
           b = Blex.new(@capacity, @false_positive_probability)

           loop(@n, b, fn b ->
             Blex.put(b, :rand.uniform(1000_000))
             b
           end)

           Blex.encode(b)
         end}
    })
  end

  def run_write_operation() do
    Benchee.run(
      %{
        "Bloomex.add" =>
          {fn b ->
             loop(@n, b, fn b ->
               Bloomex.add(b, :rand.uniform(1000_000))
             end)
           end,
           before_each: fn _ ->
             Bloomex.plain(@capacity, @false_positive_probability)
           end},
        "Blex.put" =>
          {fn b ->
             loop(@n, b, fn b ->
               Blex.put(b, :rand.uniform(1000_000))
               b
             end)
           end,
           before_each: fn _ ->
             Blex.new(@capacity, @false_positive_probability)
           end}
      },
      time: 10
    )
  end
end

Blex.Bench.Comparison.run_estimation()
IO.puts("\n=====================================\n")
Blex.Bench.Comparison.run_serialization()
IO.puts("\n=====================================\n")
Blex.Bench.Comparison.run_read_operation()
IO.puts("\n=====================================\n")
Blex.Bench.Comparison.run_write_operation()
