# Blex

Blex is a fast Bloom filter with **concurrent accessibility**, powered by [`:atomics`](http://erlang.org/doc/man/atomics.html) module.

## Features

* Fixed size Bloom filter
* Concurrent reads & writes
* Serialization
* Merge multiple Bloom filters into one
* Only one copy of data because data is saved in either `:atomics` or binary (if > 64 bytes)
* Custom hash functions

## Example

```elixir
iex> b = Blex.new(1000, 0.01)
iex> Task.async(fn -> Blex.put(b, "hello") end) |> Task.await()
iex> Task.async(fn -> Blex.put(b, "world") end) |> Task.await()
iex> Blex.member?(b, "hello")
true
iex> Blex.member?(b, "world")
true
iex> Blex.member?(b, "others")
false
```

## Installation

**Note**: it requires OTP-21.2.1 or later. OTP-21.2 is not good due to a [issue](https://github.com/erlang/otp/pull/2061).

It can be installed by adding `blex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:blex, "~> 0.2"}
  ]
end
```

## Documentation

Documentation can be found at [hexdocs.pm/blex/Blex.html](https://hexdocs.pm/blex/Blex.html).

## Benchmarking

Compare to alternative Bloom filter powered by `:array` module,

Blex is faster with read operation:

```
Operating System: macOS"
CPU Information: Intel(R) Core(TM) i7-3720QM CPU @ 2.60GHz
Number of Available Cores: 8
Available memory: 16 GB
Elixir 1.7.4
Erlang 21.2.2

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 5 s
memory time: 0 μs
parallel: 1
inputs: none specified
Estimated total run time: 21 s


Benchmarking Blex.members?...
Benchmarking Blex.members? with binary format...
Benchmarking Bloomex.members?...

Name                                       ips        average  deviation         median         99th %
Blex.members? with binary format          0.69         1.44 s     ±0.23%         1.44 s         1.44 s
Blex.members?                             0.63         1.58 s     ±0.61%         1.58 s         1.58 s
Bloomex.members?                          0.40         2.51 s     ±0.00%         2.51 s         2.51 s

Comparison:
Blex.members? with binary format          0.69
Blex.members?                             0.63 - 1.09x slower
Bloomex.members?                          0.40 - 1.74x slower
```

Blex is much faster with write operation:

```
Operating System: macOS"
CPU Information: Intel(R) Core(TM) i7-3720QM CPU @ 2.60GHz
Number of Available Cores: 8
Available memory: 16 GB
Elixir 1.7.4
Erlang 21.2.2

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 10 s
memory time: 0 μs
parallel: 1
inputs: none specified
Estimated total run time: 24 s


Benchmarking Blex.put...
Benchmarking Bloomex.add...

Name                  ips        average  deviation         median         99th %
Blex.put             0.44         2.25 s     ±3.98%         2.30 s         2.33 s
Bloomex.add         0.126         7.91 s     ±0.22%         7.91 s         7.92 s

Comparison:
Blex.put             0.44
Bloomex.add         0.126 - 3.51x slower
```

Above benchmarking script is available at `bench/comparison.exs`.

## Implementation

Instead of traditional Bloom filter, partitioned Bloom filter (a variant Bloom filter described in section 3 of
[the paper](http://gsd.di.uminho.pt/members/cbm/ps/dbloom.pdf)) is used for performance benefits. The partitioned
Bloom filter would partition bits array into **k** parts where **k** is number of hash functions. Each hash functions
would only read & write bits from its own partitioned space. This would bring following benefits:

  * Reduce hash function (`:erlang.phash2`) calls for some cases.
  * Speed up `Blex.estimate_size` by scanning only part of bits.

## License

MIT
