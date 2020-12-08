defmodule BlexTest do
  use ExUnit.Case
  doctest Blex

  test "it should works" do
    b = Blex.new(1024, 0.01)

    Blex.put(b, "hello")

    assert Blex.member?(b, "hello") == true

    assert Blex.member?(b, "ok") == false
  end

  test "serialization" do
    b = Blex.new(1000, 0.02)

    Blex.put(b, "hello")
    Blex.put(b, "world")

    bin = Blex.encode(b)

    assert Blex.member?(bin, "hello") == true
    assert Blex.member?(bin, "world") == true
    assert Blex.member?(bin, "abcde") == false
    assert Blex.member?(bin, "okkkk") == false

    b2 = Blex.decode(bin)

    assert Blex.member?(b2, "hello") == true
    assert Blex.member?(b2, "world") == true
    assert Blex.member?(b2, "abcde") == false
    assert Blex.member?(b2, "okkkk") == false
  end

  test "serialization with StreamData" do
    StreamData.binary()
    |> Enum.take(1000)
    |> Enum.each(fn data ->
      b = Blex.new(100, 0.02)

      Blex.put(b, data)

      bin = Blex.encode(b)

      assert Blex.member?(bin, data) == true

      b2 = Blex.decode(bin)

      assert Blex.member?(b2, data) == true
    end)
  end

  test "merge" do
    b1 = Blex.new(1000, 0.05)
    b2 = Blex.new(1000, 0.05)

    Blex.put(b1, "hello")
    Blex.put(b2, "world")

    b3 = Blex.merge([b1, b2])

    assert Blex.member?(b3, "hello") == true
    assert Blex.member?(b3, "world") == true
    assert Blex.member?(b3, "abcde") == false
    assert Blex.member?(b3, "okkkk") == false
  end

  test "merge_into" do
    b1 = Blex.new(1000, 0.05)
    b2 = Blex.new(1000, 0.05)
    b3 = Blex.new(1000, 0.05)

    Blex.put(b1, "hello")
    Blex.put(b2, "world")
    Blex.put(b3, "third")

    b3_encoded = Blex.encode(b3)
    Blex.merge_into([b2, b3_encoded], b1)

    assert Blex.member?(b1, "hello") == true
    assert Blex.member?(b1, "world") == true
    assert Blex.member?(b1, "third") == true
    assert Blex.member?(b1, "abcde") == false
    assert Blex.member?(b1, "okkkk") == false
  end

  test "merge should be comptaible with merge_into" do
    b1 = Blex.new(1000, 0.05)
    b2 = Blex.new(1000, 0.05)
    b3 = Blex.new(1000, 0.05)
    b4 = Blex.new(1000, 0.05)

    Blex.put(b1, "cool")
    Blex.put(b2, "cool")
    Blex.put(b3, "okkk")
    Blex.put(b4, "nooo")

    b4_encoded = Blex.encode(b4)

    merge_encoded =
      Blex.merge([b1, b3, b4_encoded])
      |> Blex.encode()

    Blex.merge_into([b3, b4_encoded], b2)

    merge_into_encoded = Blex.encode(b2)

    assert merge_encoded == merge_into_encoded
  end

  test "merge_encode" do
    b1 = Blex.new(1000, 0.05)
    b2 = Blex.new(1000, 0.05)

    Blex.put(b1, "hello")
    Blex.put(b2, "world")

    b3 = Blex.merge_encode([b1, b2])

    assert Blex.member?(b3, "hello") == true
    assert Blex.member?(b3, "world") == true
    assert Blex.member?(b3, "abcde") == false
    assert Blex.member?(b3, "okkkk") == false
  end

  test "Blex.estimate_size" do
    b = Blex.new(1000, 0.01)
    assert Blex.estimate_size(b) == 0
    assert Blex.estimate_size(Blex.encode(b)) == 0
    Blex.put(b, 1)
    assert Blex.estimate_size(b) == 1
    assert Blex.estimate_size(Blex.encode(b)) == 1
    Blex.put(b, 2)
    assert Blex.estimate_size(b) == 2
    assert Blex.estimate_size(Blex.encode(b)) == 2
    Blex.put(b, 3)
    assert Blex.estimate_size(b) == 3
    assert Blex.estimate_size(Blex.encode(b)) == 3
    Blex.put(b, 4)
    assert Blex.estimate_size(b) == 4
    assert Blex.estimate_size(Blex.encode(b)) == 4
    Blex.put(b, 5)
    assert Blex.estimate_size(b) == 5
    assert Blex.estimate_size(Blex.encode(b)) == 5
    Blex.put(b, 6)
    assert Blex.estimate_size(b) == 6
    assert Blex.estimate_size(Blex.encode(b)) == 6

    for i <- 1..1000 do
      Blex.put(b, i)
    end

    estimated_size = Blex.estimate_size(b)
    assert estimated_size > 950
    assert estimated_size < 1050

    estimated_size_via_binary = Blex.estimate_size(Blex.encode(b))
    assert estimated_size == estimated_size_via_binary
  end

  test "Blex.estimate_capacity" do
    b = Blex.new(1400, 0.01)
    cap = Blex.estimate_capacity(b)
    assert cap > 1350
    assert cap < 1450
  end

  test "definitely not in" do
    b = Blex.new(1_000_000, 0.01)

    for i <- 1..1_000_000, rem(i, 2) == 0 do
      Blex.put(b, i)
    end

    for i <- 1..1_000_000, not Blex.member?(b, i) do
      assert rem(i, 2) == 1
    end
  end

  test "may be in" do
    b = Blex.new(1_000_000, 0.01)

    for i <- 1..1_000_000 do
      Blex.put(b, i)
    end

    result =
      Enum.reduce(1_000_001..10_000_000, 0, fn i, acc ->
        if Blex.member?(b, i) do
          acc + 1
        else
          acc
        end
      end)

    assert result < 9_000_000 * 0.01
  end

  @tag timeout: 3_000_000
  test "very large bloom filter" do
    # this takes about 6 GB memory, note that github actions host currently has 7 GB memory limit.
    b = Blex.new(3_200_000_000, 0.02)

    Blex.put(b, "hello")
    Blex.put(b, "world")

    assert Blex.member?(b, "hello") == true
    assert Blex.member?(b, "world") == true
    assert Blex.member?(b, "no exist") == false

    # this test takes a few minutes
    assert Blex.estimate_size(b) == 2
  end
end
