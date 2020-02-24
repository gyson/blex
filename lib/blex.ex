defmodule Blex do
  @moduledoc """

  Blex is a fast Bloom filter with **concurrent accessibility**, powered by [`:atomics`](http://erlang.org/doc/man/atomics.html) module.

  ## Features

  * Fixed size Bloom filter
  * Concurrent reads & writes
  * Serialization
  * Merge multiple Bloom filters into one
  * Only one copy of data because data is saved in either `:atomics` or binary (if > 64 bytes)
  * Custom hash functions

  ## Example

      iex> b = Blex.new(1000, 0.01)
      iex> Task.async(fn -> Blex.put(b, "hello") end) |> Task.await()
      iex> Task.async(fn -> Blex.put(b, "world") end) |> Task.await()
      iex> Blex.member?(b, "hello")
      true
      iex> Blex.member?(b, "world")
      true
      iex> Blex.member?(b, "others")
      false

  ## Blex struct and Blex binary

  Blex struct is the struct that contains Blex info, created via `Blex.new/2`, `Blex.new/3`,
  `Blex.decode/1` and `Blex.merge/1`. Data is saved in atomics array.

  Blex binary is encoded binary from Blex struct via `Blex.encode/1` or `Blex.merge_encode/1`.
  It supports most operations (e.g. `Blex.member?/2`) except `Blex.put/2` (obviously, we cannot mutate binary).
  This is useful when we collect Bloom filters from other nodes, we can avoid deserialization
  if we do not need to add more memebers to it.

  ## How to start ?

  Checkout `Blex.new/2`, `Blex.put/2` and `Blex.member?/2`.

  ## How to do serialization ?

  Checkout `Blex.encode/1`, `Blex.decode/1`, `Blex.merge/1` and `Blex.merge_encode/1`.

  ## How to merge mutliple bloom filters ?

  Checkout `Blex.merge/1` and `Blex.merge_encode/1`.

  ## How to use custom hash functions ?

  Checkout `Blex.register/2` and `Blex.new/3`.

  ## How to collect meta info ?

  Checkout `Blex.estimate_size/1`, `Blex.estimate_memory/1` and `Blex.estimate_capacity/1`.

  """

  use Bitwise

  defstruct [
    :a,
    :k,
    :b,
    :m,
    :hash_id,
    :hash_fn
  ]

  @type hash_id :: non_neg_integer()

  @type hash_function :: (non_neg_integer(), any() -> {non_neg_integer(), any()})

  @type t :: %__MODULE__{
          a: :atomics.atomics_ref(),
          k: pos_integer(),
          b: pos_integer(),
          m: pos_integer(),
          hash_id: hash_id(),
          hash_fn: hash_function()
        }

  @doc """

  Create a Bloom filter with default hash function. It returns a Blex struct.

  `capacity` should be a positive integer.

  `false_positive_probability` should be a float that greater than 0 and smaller than 1.

  ## Example

  To create a Bloom filter with 1000 capacity and 1% false positive probability, we can do:

      iex> b = Blex.new(1000, 0.01)
      iex> Blex.put(b, "hello")
      :ok
      iex> Blex.member?(b, "hello")
      true
      iex> Blex.member?(b, "others")
      false

  """

  @spec new(pos_integer(), float()) :: t()

  def new(capacity, false_positive_probability)
      when is_integer(capacity) and capacity > 0 and false_positive_probability > 0 and
             false_positive_probability < 1 do
    k = compute_optimal_k(false_positive_probability)
    b = compute_optimal_b(capacity, false_positive_probability, k)

    hash_id =
      cond do
        b <= 16 -> 201
        b <= 32 -> 202
        b <= 48 -> 203
        true -> raise ArgumentError, "unsupported capacity"
      end

    create_instance(hash_id, k, b)
  end

  defp compute_optimal_k(false_positive_probability) do
    -:math.log2(false_positive_probability) |> ceil()
  end

  defp compute_optimal_b(n, false_positive_probability, k) do
    p = :math.pow(false_positive_probability, 1 / k)

    # From Scalable Bloom Filter paper, we have p = 1 - (1 - 1 / m)^n
    # Therefore, m = 1 / (1 - (1 - p)^(1 / n))
    m = 1 / (1 - :math.pow(1 - p, 1 / n))

    # grow in power of 2 to make hash coding easier
    b = :math.log2(m) |> ceil()

    # it needs to be at least 6 bits to fit :atomics 64 bits unsigned integer
    max(b, 6)
  end

  defp create_instance(hash_id, k, b) do
    m = 1 <<< b
    atomics_size = div(k * m, 64)
    hash_fn = get_hash_fn(hash_id)

    # Require OTP-21.2.1 or later for a bug fix
    a = :atomics.new(atomics_size, signed: false)

    %__MODULE__{
      a: a,
      k: k,
      b: b,
      m: m,
      hash_id: hash_id,
      hash_fn: hash_fn
    }
  end

  # hash_id coding range:
  # 0 ~ 200 custom hash functions
  # 201 ~ 203 default hash functions
  # 204 ~ 255 reserved for future extension

  @range 1 <<< 32

  @spec get_hash_fn(hash_id()) :: hash_function()

  # for b <= 16, it requires one :erlang.phash2 call
  defp get_hash_fn(201) do
    fn
      0, {item, b, m} ->
        hash = :erlang.phash2(item, @range)
        <<h1::size(b), h2::size(b), _::bits>> = <<hash::32>>
        {h1, {m, h1, h2}}

      i, {m, h1, h2} = acc when is_integer(h1) and is_integer(h2) ->
        {rem(h1 + i * h2, m), acc}
    end
  end

  # for 16 < b <= 32, it requires two :erlang.phash2 calls
  defp get_hash_fn(202) do
    fn
      0, {item, _b, m} ->
        h1 = :erlang.phash2(item, m)
        {h1, {item, m, h1}}

      1, {item, m, h1} when is_integer(h1) ->
        h2 = :erlang.phash2([item], m)
        {rem(h1 + h2, m), {h1, h2, m}}

      i, {h1, h2, m} = acc when is_integer(h1) and is_integer(h2) ->
        {rem(h1 + i * h2, m), acc}
    end
  end

  # for 32 < b <= 48, it requires three :erlang.phash2 calls
  defp get_hash_fn(203) do
    fn
      0, {item, b, m} ->
        first = :erlang.phash2(item, @range)
        second = :erlang.phash2([item], @range)
        <<h1::size(b), _::bits>> = bin = <<first::32, second::32>>
        {h1, {item, b, m, bin}}

      1, {item, b, m, bin} ->
        third = :erlang.phash2({item}, @range)
        <<h1::size(b), h2::size(b), _::bits>> = <<bin, third::32>>
        {rem(h1 + h2, m), {h1, h2, m}}

      i, {h1, h2, m} = acc when is_integer(h1) and is_integer(h2) ->
        {rem(h1 + i * h2, m), acc}
    end
  end

  # custom hash functions
  defp get_hash_fn(custom_hash_id) do
    :persistent_term.get({__MODULE__, custom_hash_id})
  end

  @doc """

  Create a Bloom filter with custom hash id. It returns a Blex struct.

  `capacity` should be a positive integer.

  `false_positive_probability` should be a float that greater than 0 and smaller than 1.

  Before we use a custom hash id, we need to do `Blex.register/2` to register it first.

  ## Example

  To create a Bloom filter with custom hash function, 1000 capacity and 1% false positive probability, we can do:

      iex> custom_hash_id = 1
      iex> Blex.register(custom_hash_id, fn
      ...>   0, {item, b, range} ->
      ...>     <<h1::size(b), h2::size(b), _::bits>> = <<Murmur.hash_x86_128(item)::128>>
      ...>     {h1, {range, h1, h2}}
      ...>
      ...>   i, {range, h1, h2} = acc ->
      ...>     {rem(h1 + i * h2, range), acc}
      ...> end)
      :ok
      iex> b = Blex.new(1000, 0.01, custom_hash_id)
      iex> Blex.put(b, "hello")
      :ok
      iex> Blex.member?(b, "hello")
      true
      iex> Blex.member?(b, "others")
      false

  """

  @spec new(pos_integer(), float(), hash_id()) :: t()

  def new(capacity, false_positive_probability, custom_hash_id)
      when is_integer(capacity) and 0 < capacity and 0 < false_positive_probability and
             false_positive_probability < 1 and custom_hash_id in 0..200 do
    k = compute_optimal_k(false_positive_probability)
    b = compute_optimal_b(capacity, false_positive_probability, k)
    create_instance(custom_hash_id, k, b)
  end

  @doc """

  Register a custom function with given id.

  Custom hash id must be integer and within range from 0 to 200.
  So we can have max 201 custom hash functions. Adding more
  custom hash functions is possible but not supported yet
  because 201 custom functions should be enough in practice.

  The signature of hash function is similar to `fun` from `Enum.map_reduce/3`.
  The spec of hash function is `(non_neg_integer(), any() -> {non_neg_integer(), any()})`.
  The hash function would be invoked k time if Bloom filter has k hash functions.
  The first parameter is integer from `0` to `k-1`.
  The second parameter is the accumulator. The first accumulator is `{item, b, range}` where
  `item` is the value to hash. `range` indicates that returned position should be in
  range from `0` to `range-1`. `b` is bit size of range and we have `(1 <<< b) == range`.
  The returned value is a tuple of two element. The first element is the position of the bit.
  The second element is the accumulator that would be passed to next interation.

  The hash id and hash function pair would be saved in `:persistent_term`. We should only
  register it once at the beginning.

  ## Example

      iex> custom_hash_id = 1
      iex> Blex.register(custom_hash_id, fn
      ...>   0, {item, b, range} ->
      ...>     <<h1::size(b), h2::size(b), _::bits>> = <<Murmur.hash_x86_128(item)::128>>
      ...>     {h1, {range, h1, h2}}
      ...>
      ...>   i, {range, h1, h2} = acc ->
      ...>     {rem(h1 + i * h2, range), acc}
      ...> end)
      :ok

  """

  @spec register(hash_id(), hash_function()) :: :ok

  def register(custom_hash_id, hash_function) when custom_hash_id in 0..200 do
    :persistent_term.put({__MODULE__, custom_hash_id}, hash_function)
  end

  @doc """

  Put item into Bloom filter (Blex struct).

  ## Example

      iex> b = Blex.new(1000, 0.01)
      iex> Blex.member?(b, "hello")
      false
      iex> Blex.put(b, "hello")
      :ok
      iex> Blex.member?(b, "hello")
      true

  """

  @spec put(t(), any()) :: :ok

  def put(%__MODULE__{a: a, k: k, b: b, m: m, hash_fn: hash_fn} = _blex_struct, item) do
    # base starts with 64 because :atomics array is one-indexed with 64 bits integer.
    set_all(0, k, a, {item, b, m}, hash_fn, 64, m)
  end

  @spec set_all(
          integer(),
          integer(),
          :atomics.atomics_ref(),
          {any(), integer(), integer()},
          hash_function(),
          integer(),
          integer()
        ) :: :ok

  defp set_all(k, k, _, _, _, _, _), do: :ok

  defp set_all(i, k, a, acc, f, base, m) do
    {position, new_acc} = f.(i, acc)
    index = div(position + base, 64)
    bits = 1 <<< rem(position, 64)
    set(a, index, bits, :atomics.get(a, index))
    set_all(i + 1, k, a, new_acc, f, base + m, m)
  end

  @spec set(:atomics.atomics_ref(), integer(), integer(), integer()) :: :ok

  defp set(a, index, bits, origin) do
    case origin ||| bits do
      ^origin ->
        :ok

      result ->
        case :atomics.compare_exchange(a, index, origin, result) do
          :ok ->
            :ok

          actual ->
            set(a, index, bits, actual)
        end
    end
  end

  @doc """

  Check if item is member of Blex struct or Blex binary.

  ## Example

      iex> b = Blex.new(1000, 0.01)
      iex> Blex.member?(b, "hello")
      false
      iex> Blex.put(b, "hello")
      :ok
      iex> Blex.member?(b, "hello")
      true
      iex> encoded = Blex.encode(b)
      iex> Blex.member?(encoded, "hello")
      true

  """

  @spec member?(t() | binary(), any()) :: boolean()

  def member?(%__MODULE__{a: a, k: k, b: b, m: m, hash_fn: hash_fn} = _blex, item) do
    check_member(0, k, a, {item, b, m}, hash_fn, 64, m)
  end

  def member?(<<code, k, b, _::bits>> = bin, item) do
    m = 1 <<< b
    f = get_hash_fn(code)
    # max = m * k + 8 * 3 - 1
    max = m * k + 23
    check_member_for_binary(0, k, bin, {item, b, m}, f, max, m)
  end

  @spec check_member(
          integer(),
          integer(),
          :atomics.atomics_ref(),
          {any(), integer(), integer()},
          hash_function(),
          integer(),
          integer()
        ) :: boolean()

  defp check_member(k, k, _, _, _, _, _), do: true

  defp check_member(i, k, a, acc, f, base, m) do
    {position, new_acc} = f.(i, acc)
    index = div(position + base, 64)
    bits = 1 <<< rem(position, 64)

    case :atomics.get(a, index) &&& bits do
      ^bits ->
        check_member(i + 1, k, a, new_acc, f, base + m, m)

      _ ->
        false
    end
  end

  @spec check_member_for_binary(
          integer(),
          integer(),
          binary(),
          {any(), integer(), integer()},
          hash_function(),
          integer(),
          integer()
        ) :: boolean()

  defp check_member_for_binary(k, k, _, _, _, _, _), do: true

  defp check_member_for_binary(i, k, bin, acc, f, max, m) do
    {position, new_acc} = f.(i, acc)
    index = div(max - position, 8)
    bits = 1 <<< rem(position, 8)

    case :binary.at(bin, index) &&& bits do
      ^bits ->
        check_member_for_binary(i + 1, k, bin, new_acc, f, max - m, m)

      _ ->
        false
    end
  end

  @doc """

  Estimate actual size of unique items that Blex struct or Blex binary contains.

  ## Example

      iex> b = Blex.new(1000, 0.01)
      iex> Blex.estimate_size(b)
      0
      iex> Blex.put(b, "hello")
      :ok
      iex> Blex.estimate_size(b)
      1
      iex> Blex.put(b, "world")
      :ok
      iex> Blex.estimate_size(b)
      2
      iex> encoded = Blex.encode(b)
      iex> Blex.estimate_size(encoded)
      2

  """

  @spec estimate_size(t() | binary()) :: non_neg_integer()

  def estimate_size(%__MODULE__{a: a, m: m} = _blex) do
    1..div(m, 64)
    |> Enum.reduce(0, fn i, acc ->
      bits = <<:atomics.get(a, i)::64>>
      acc + count_64_bits(bits)
    end)
    |> compute_estimated_size(m)
  end

  def estimate_size(<<_, k, b, _::bits>> = bin) do
    m = 1 <<< b
    prefix = 24 + m * (k - 1)

    <<_::bits-size(prefix), target::bits>> = bin

    count_bits_for_bin(target, 0)
    |> compute_estimated_size(m)
  end

  defp compute_estimated_size(x, m) when x < m do
    round(-m * :math.log(1 - x / m))
  end

  # when x == m, 1 - x/m would be 0.0, :math.log(0.0) would raise error
  defp compute_estimated_size(m, m) do
    round(-m * :math.log(1 / m))
  end

  @spec count_bits_for_bin(binary(), integer()) :: integer()

  defp count_bits_for_bin(<<x::bits-size(64), rest::bits>>, acc) do
    count_bits_for_bin(rest, acc + count_64_bits(x))
  end

  defp count_bits_for_bin(<<>>, acc), do: acc

  defp count_64_bits(
         <<b_01::1, b_02::1, b_03::1, b_04::1, b_05::1, b_06::1, b_07::1, b_08::1, b_09::1,
           b_10::1, b_11::1, b_12::1, b_13::1, b_14::1, b_15::1, b_16::1, b_17::1, b_18::1,
           b_19::1, b_20::1, b_21::1, b_22::1, b_23::1, b_24::1, b_25::1, b_26::1, b_27::1,
           b_28::1, b_29::1, b_30::1, b_31::1, b_32::1, b_33::1, b_34::1, b_35::1, b_36::1,
           b_37::1, b_38::1, b_39::1, b_40::1, b_41::1, b_42::1, b_43::1, b_44::1, b_45::1,
           b_46::1, b_47::1, b_48::1, b_49::1, b_50::1, b_51::1, b_52::1, b_53::1, b_54::1,
           b_55::1, b_56::1, b_57::1, b_58::1, b_59::1, b_60::1, b_61::1, b_62::1, b_63::1,
           b_64::1>>
       ) do
    b_01 + b_02 + b_03 + b_04 + b_05 + b_06 + b_07 + b_08 + b_09 + b_10 + b_11 + b_12 + b_13 +
      b_14 + b_15 + b_16 + b_17 + b_18 + b_19 + b_20 + b_21 + b_22 + b_23 + b_24 + b_25 + b_26 +
      b_27 + b_28 + b_29 + b_30 + b_31 + b_32 + b_33 + b_34 + b_35 + b_36 + b_37 + b_38 + b_39 +
      b_40 + b_41 + b_42 + b_43 + b_44 + b_45 + b_46 + b_47 + b_48 + b_49 + b_50 + b_51 + b_52 +
      b_53 + b_54 + b_55 + b_56 + b_57 + b_58 + b_59 + b_60 + b_61 + b_62 + b_63 + b_64
  end

  @doc """

  Estimate memory consumption in bytes for Blex struct or Blex binary.

  ## Example

      iex> b = Blex.new(1000, 0.01)
      iex> Blex.estimate_memory(b)
      1832
      iex> encoded = Blex.encode(b)
      iex> Blex.estimate_memory(encoded)
      1795

  """

  @spec estimate_memory(t() | binary()) :: non_neg_integer()

  def estimate_memory(%__MODULE__{a: a} = _blex) do
    :atomics.info(a).memory
  end

  def estimate_memory(bin) when is_binary(bin) do
    byte_size(bin)
  end

  @doc """

  Estimate actual capacity of Blex struct or Blex binary.

  Capacity grows in power of 2. Sometimes, the actual capacity
  could be bigger than specified capacity in `Blex.new/2` and `Blex.new/3`.

  It's estimated value and it could be slightly smaller than specified
  capacity.

  ## Example

      iex> b = Blex.new(1000, 0.01)
      iex> Blex.estimate_capacity(b)
      1419
      iex> encoded = Blex.encode(b)
      iex> Blex.estimate_capacity(encoded)
      1419

  """

  @spec estimate_capacity(t() | binary()) :: non_neg_integer()

  def estimate_capacity(%__MODULE__{m: m}) do
    compute_estimated_capacity(m)
  end

  def estimate_capacity(<<_, _, b, _::bits>> = _blex) do
    compute_estimated_capacity(1 <<< b)
  end

  defp compute_estimated_capacity(m) do
    # derived from Scalable Bloom filter paper that:
    # p = 1/2 = 1 - (1 - 1/m)^n
    round(:math.log(0.5) / :math.log(1 - 1 / m))
  end

  @doc """

  Encode Blex struct to Blex binary.

  ## Example

      iex> b = Blex.new(40, 0.5)
      iex> Blex.encode(b)
      <<201, 1, 6, 0, 0, 0, 0, 0, 0, 0, 0>>
      iex> Blex.put(b, "hello")
      iex> Blex.encode(b)
      <<201, 1, 6, 0, 0, 0, 0, 1, 0, 0, 0>>

  """

  @spec encode(t()) :: binary()

  def encode(%__MODULE__{a: a, k: k, b: b, m: m, hash_id: hash_id} = _blex_struct) do
    size = div(m, 64) * k

    data =
      Enum.reduce(1..size, [], fn i, acc ->
        [<<:atomics.get(a, i)::integer-unsigned-64>> | acc]
      end)

    IO.iodata_to_binary([hash_id, k, b | data])
  end

  @doc """

  Decode Blex binary to Blex struct.

  ## Example

      iex> b = Blex.new(40, 0.5)
      iex> Blex.put(b, "hello")
      :ok
      iex> encoded = Blex.encode(b)
      <<201, 1, 6, 0, 0, 0, 0, 1, 0, 0, 0>>
      iex> decoded = Blex.decode(encoded)
      iex> Blex.member?(decoded, "hello")
      true

  """

  @spec decode(binary()) :: t()

  def decode(<<hash_id, k, b, rest::bits>> = _blex_binary) do
    blex = create_instance(hash_id, k, b)
    size = div(k * blex.m, 64)
    copy_data(rest, blex.a, size)
    blex
  end

  @spec copy_data(binary(), :atomics.atomics_ref(), integer()) :: :ok

  defp copy_data(<<x::integer-unsigned-64, rest::bits>>, a, i) do
    :atomics.put(a, i, x)
    copy_data(rest, a, i - 1)
  end

  defp copy_data(<<>>, _, 0), do: :ok

  @doc """

  Merge multiple Blex struct or Blex binary into one Blex struct.

  ## Example

      iex> b1 = Blex.new(1000, 0.01)
      iex> b2 = Blex.new(1000, 0.01)
      iex> b3 = Blex.new(1000, 0.01)
      iex> Blex.put(b1, "hello")
      :ok
      iex> Blex.put(b2, "world")
      :ok
      iex> Blex.put(b3, "okk")
      :ok
      iex> encoded_b3 = Blex.encode(b3)
      iex> merged = Blex.merge([b1, b2, encoded_b3])
      iex> Blex.member?(merged, "hello")
      true
      iex> Blex.member?(merged, "world")
      true
      iex> Blex.member?(merged, "okk")
      true
      iex> Blex.member?(merged, "others")
      false

  """

  @spec merge([t() | binary()]) :: t()

  def merge([first | rest]) do
    {hash_id, k, b, f_first} = transform(first)

    f_rest =
      Enum.map(rest, fn it ->
        {^hash_id, ^k, ^b, f} = transform(it)
        f
      end)

    dest = create_instance(hash_id, k, b)
    a = dest.a
    m = dest.m
    size = div(m * k, 64)

    Enum.each(1..size, fn i ->
      result =
        Enum.reduce(f_rest, f_first.(i), fn f, acc ->
          f.(i) ||| acc
        end)

      :atomics.put(a, i, result)
    end)

    dest
  end

  @doc """

  Merge multiple Blex struct or Blex binary into given Blex struct.

  ## Example

      iex> b1 = Blex.new(1000, 0.01)
      iex> b2 = Blex.new(1000, 0.01)
      iex> b3 = Blex.new(1000, 0.01)
      iex> Blex.put(b1, "hello")
      :ok
      iex> Blex.put(b2, "world")
      :ok
      iex> Blex.put(b3, "okk")
      :ok
      iex> encoded_b3 = Blex.encode(b3)
      iex> Blex.merge_into([b2, encoded_b3], b1)
      :ok
      iex> Blex.member?(b1, "hello")
      true
      iex> Blex.member?(b1, "world")
      true
      iex> Blex.member?(b1, "okk")
      true
      iex> Blex.member?(b1, "others")
      false

  """

  @spec merge_into([t() | binary()], t()) :: :ok

  def merge_into(blexes, %__MODULE__{a: a, k: k, b: b, m: m, hash_id: hash_id} = _blex_struct) do
    f_blexes =
      Enum.reduce(blexes, [], fn it, acc ->
        {^hash_id, ^k, ^b, f} = transform(it)
        [f | acc]
      end)

    size = div(m * k, 64)

    Enum.each(1..size, fn i ->
      bits =
        Enum.reduce(f_blexes, 0, fn f, acc ->
          f.(i) ||| acc
        end)

      set(a, i, bits, :atomics.get(a, i))
    end)
  end

  defp transform(%__MODULE__{a: a, k: k, b: b, hash_id: hash_id}) do
    f = fn i ->
      :atomics.get(a, i)
    end

    {hash_id, k, b, f}
  end

  defp transform(<<hash_id, k, b, _::bits>> = bin) do
    size = (1 <<< b) * k + 24

    f = fn i ->
      prefix_size = size - i * 64
      <<_::size(prefix_size), x::integer-unsigned-64, _::bits>> = bin
      x
    end

    {hash_id, k, b, f}
  end

  @doc """

  Merge multiple Blex struct or Blex binary into one Blex binary.

  It does `list |> Blex.merge() |> Blex.encode()` without intermeidate step.

  ## Example

      iex> b1 = Blex.new(1000, 0.01)
      iex> b2 = Blex.new(1000, 0.01)
      iex> b3 = Blex.new(1000, 0.01)
      iex> Blex.put(b1, "hello")
      :ok
      iex> Blex.put(b2, "world")
      :ok
      iex> Blex.put(b3, "okk")
      :ok
      iex> encoded_b3 = Blex.encode(b3)
      iex> merged = Blex.merge_encode([b1, b2, encoded_b3])
      iex> is_binary(merged)
      true
      iex> Blex.member?(merged, "hello")
      true
      iex> Blex.member?(merged, "world")
      true
      iex> Blex.member?(merged, "okk")
      true
      iex> Blex.member?(merged, "others")
      false

  """

  @spec merge_encode([t() | binary()]) :: binary()

  def merge_encode([first | rest]) do
    {hash_id, k, b, f_first} = transform(first)

    f_rest =
      Enum.map(rest, fn it ->
        {^hash_id, ^k, ^b, f} = transform(it)
        f
      end)

    size = div((1 <<< b) * k, 64)

    data =
      Enum.reduce(1..size, [], fn i, acc ->
        result =
          Enum.reduce(f_rest, f_first.(i), fn f, acc ->
            f.(i) ||| acc
          end)

        [<<result::integer-unsigned-64>> | acc]
      end)

    [hash_id, k, b | data]
    |> IO.iodata_to_binary()
  end
end
