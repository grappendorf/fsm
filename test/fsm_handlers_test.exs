defmodule FsmHandlersTest do
  use ExUnit.Case

  defmodule FsmWithHandlers do
    use Fsm, initial_state: :start, initial_data: %{handler: nil}

    state start do
      on enter, data: data do
        transition(%{data | handler: :enter})
      end

      on leave, data: data do
        transition(%{data | handler: :leave})
      end

      event leave_state do
        transition(:stop_without_handler)
      end

      event enter_state do
        transition(:stop_with_handler)
      end

      event same_state do
        transition(:start)
      end
    end

    state stop_without_handler do
    end

    state stop_with_handler do
      on enter, data: data do
        transition(%{data | handler: :enter})
      end
    end
  end

  test "leave handler" do
    assert(
      FsmWithHandlers.new
      |> FsmWithHandlers.leave_state
      |> FsmWithHandlers.data == %{handler: :leave})
  end

  test "enter handler" do
    assert(
      FsmWithHandlers.new
      |> FsmWithHandlers.enter_state
      |> FsmWithHandlers.data == %{handler: :enter})
  end

  test "don't call handlers when transitioning to the same state" do
    assert(
      FsmWithHandlers.new
      |> FsmWithHandlers.same_state
      |> FsmWithHandlers.data == %{handler: nil})
  end
end
