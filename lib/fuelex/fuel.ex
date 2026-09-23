defmodule Fuelex.Fuel do
  @moduledoc """
  Pure fuel calculations in kilograms. Actions are `{action, world}` tuples in
  chronological order. Fuel for later actions is carried through earlier actions.
  """

  @gravities %{earth: 9807, moon: 1620, mars: 3711}
  @actions %{launch: {42, 33}, land: {33, 42}}

  @type action :: {:launch | :land, :earth | :moon | :mars}
  @type error :: :invalid_mass | :invalid_action | :invalid_actions | :invalid_sequence

  @doc "Fuel for one action, including the fuel needed to carry its own fuel."
  @spec calculate_for_action(number(), action()) :: {:ok, non_neg_integer()} | {:error, error()}
  def calculate_for_action(mass, action) do
    with :ok <- validate_mass(mass),
         :ok <- validate_action(action) do
      {:ok, action_fuel(mass, action)}
    end
  end

  @doc """
  Total fuel loaded before departure. An empty flight needs zero fuel.

  Actions must alternate: a landing must be followed by a launch from that
  same world before another landing.
  """
  @spec calculate_for_departure(number(), [action()]) ::
          {:ok, non_neg_integer()} | {:error, error()}
  def calculate_for_departure(mass, actions) do
    with :ok <- validate_mass(mass),
         :ok <- validate_actions(actions),
         :ok <- validate_sequence(actions) do
      fuel =
        actions
        |> Enum.reverse()
        |> Enum.reduce(0, fn action, later_fuel ->
          later_fuel + action_fuel(mass + later_fuel, action)
        end)

      {:ok, fuel}
    end
  end

  defp validate_mass(mass) when is_number(mass) and mass > 0, do: :ok
  defp validate_mass(_), do: {:error, :invalid_mass}

  defp validate_action({action, world})
       when is_map_key(@actions, action) and is_map_key(@gravities, world),
       do: :ok

  defp validate_action(_), do: {:error, :invalid_action}

  defp validate_actions(actions) when is_list(actions) do
    Enum.reduce_while(actions, :ok, fn action, :ok ->
      case validate_action(action) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_actions(_), do: {:error, :invalid_actions}

  defp validate_sequence([]), do: :ok
  defp validate_sequence([_]), do: :ok

  defp validate_sequence([{:land, world}, {:launch, world} = next | rest]),
    do: validate_sequence([next | rest])

  defp validate_sequence([{:launch, _}, {:land, _} = next | rest]),
    do: validate_sequence([next | rest])

  defp validate_sequence(_), do: {:error, :invalid_sequence}

  defp action_fuel(mass, {action, world}) do
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
