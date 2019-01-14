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

**Note**: it requires OTP-21.2.1 or later. OTP-21.2 is not good due to [this issue](https://github.com/erlang/otp/pull/2061).

It can be installed by adding `blex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:blex, "~> 0.1.0"}
  ]
end
```

## Documentation

Documentation can be found at [https://hexdocs.pm/blex/Blex.html](https://hexdocs.pm/blex/Blex.html).

## Implementation

Instead of traditional Bloom filter, partitioned Bloom filter (a variant Bloom filter described in section 3 of
[the paper](http://gsd.di.uminho.pt/members/cbm/ps/dbloom.pdf)) is used for performance benefits. The partitioned
Bloom filter would partition bits array into **k** parts where **k** is number of hash functions. Each hash functions
would only read & write bits from its own partitioned space. This would bring following benefits:

  * Reduce hash function (`:erlang.phash2`) calls for some cases.
  * Speed up `Blex.estimate_size` by scanning only part of bits.

## License

MIT
