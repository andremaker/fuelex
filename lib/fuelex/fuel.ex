defmodule Fuelex.Fuel do
  @moduledoc """
  Pure fuel calculations in kilograms. Steps are `{action, world}` tuples in
  chronological order. Fuel for later steps is carried through earlier steps.
  """

  @gravities %{earth: 9807, moon: 1620, mars: 3711}
  @actions %{launch: {42, 33}, land: {33, 42}}

  @type step :: {:launch | :land, :earth | :moon | :mars}
  @type error :: :invalid_mass | :invalid_step | :invalid_steps | :invalid_sequence

  @doc "Fuel for one maneuver, including the fuel needed to carry its own fuel."
  @spec maneuver(number(), step()) :: {:ok, non_neg_integer()} | {:error, error()}
  def maneuver(mass, step) do
    with :ok <- validate_mass(mass),
         :ok <- validate_step(step) do
      {:ok, maneuver_fuel(mass, step)}
    end
  end

  @doc """
  Total fuel loaded before departure. An empty flight needs zero fuel.

  Actions must alternate: a landing must be followed by a launch from that
  same world before another landing.
  """
  @spec flight(number(), [step()]) :: {:ok, non_neg_integer()} | {:error, error()}
  def flight(mass, steps) do
    with :ok <- validate_mass(mass),
         :ok <- validate_steps(steps),
         :ok <- validate_sequence(steps) do
      fuel =
        steps
        |> Enum.reverse()
        |> Enum.reduce(0, fn step, later_fuel ->
          later_fuel + maneuver_fuel(mass + later_fuel, step)
        end)

      {:ok, fuel}
    end
  end

  defp validate_mass(mass) when is_number(mass) and mass > 0, do: :ok
  defp validate_mass(_), do: {:error, :invalid_mass}

  defp validate_step({action, world})
       when is_map_key(@actions, action) and is_map_key(@gravities, world),
       do: :ok

  defp validate_step(_), do: {:error, :invalid_step}

  defp validate_steps(steps) when is_list(steps) do
    Enum.reduce_while(steps, :ok, fn step, :ok ->
      case validate_step(step) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_steps(_), do: {:error, :invalid_steps}

  defp validate_sequence([]), do: :ok
  defp validate_sequence([_]), do: :ok

  defp validate_sequence([{:land, world}, {:launch, world} = next | rest]),
    do: validate_sequence([next | rest])

  defp validate_sequence([{:launch, _}, {:land, _} = next | rest]),
    do: validate_sequence([next | rest])

  defp validate_sequence(_), do: {:error, :invalid_sequence}

  defp maneuver_fuel(mass, {action, world}) do
    {coefficient, offset} = Map.fetch!(@actions, action)
    accumulate(mass, Map.fetch!(@gravities, world) * coefficient, offset, 0)
  end

  defp accumulate(mass, factor, offset, total) do
    # Exact decimal constants for integer masses, avoiding floating-point
    # rounding at floor boundaries. Fractional masses use the same recurrence.
    next =
      if is_integer(mass),
        do: div(mass * factor, 1_000_000) - offset,
        else: floor(mass * factor / 1_000_000) - offset

    if next <= 0, do: total, else: accumulate(next, factor, offset, total + next)
  end
end
