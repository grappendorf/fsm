defmodule FsmHandlersTest do
  use ExUnit.Case

  defmodule FsmWithHandlers do
    use Fsm, initial_state: :start, initial_data: %{handler: nil}

    state start do
      on leave, data: data do
        transition(%{data | handler: :leave})
      end

      event leave_state do
        transition(:stop_without_handler)
      end

      event enter_state do
        transition(:stop_with_handler)
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
end
