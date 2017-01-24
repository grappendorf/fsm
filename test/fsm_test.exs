defmodule FsmTest do
  use ExUnit.Case

  defmodule BasicFsm do
    use Fsm, initial_state: :stopped

    state stopped do
      event run do
        transition(:running)
      end
    end

    state running do
      event stop do
        transition(:stopped)
      end
    end
  end

  test "basic" do
    assert(
      BasicFsm.new
      |> BasicFsm.state == :stopped)

    assert(
      BasicFsm.new
      |> BasicFsm.run
      |> BasicFsm.state == :running)

    assert(
      BasicFsm.new
      |> BasicFsm.run
      |> BasicFsm.stop
      |> BasicFsm.state == :stopped)

    assert_raise(FunctionClauseError, fn ->
      BasicFsm.new
      |> BasicFsm.run
      |> BasicFsm.run
    end)
  end



  defmodule PrivateFsm do
    use Fsm, initial_state: :stopped

    state stopped do
      eventp run do
        transition(:running)
      end
    end

    def my_run(fsm), do: run(fsm)
  end

  test "private" do
    assert_raise(UndefinedFunctionError, fn ->
      PrivateFsm.new
      |> PrivateFsm.run
    end)

    assert(
      PrivateFsm.new
      |> PrivateFsm.my_run
      |> PrivateFsm.state == :running
    )
  end



  defmodule GlobalHandlers do
    use Fsm, initial_state: :stopped

    state stopped do
      event undefined_event1
      event undefined_event2/2

      event run do
        transition(:running)
      end

      event _ do
        transition(:invalid1)
      end
    end

    state running do
      event stop do
        transition(:stopped)
      end
    end

    event _ do
      transition(:invalid2)
    end
  end

  test "global handlers" do
    assert(
      GlobalHandlers.new
      |> GlobalHandlers.undefined_event1
      |> GlobalHandlers.state == :invalid1
    )

    assert(
      GlobalHandlers.new
      |> GlobalHandlers.run
      |> GlobalHandlers.undefined_event2(1,2)
      |> GlobalHandlers.state == :invalid2
    )
  end



  defmodule DataFsm do
    use Fsm, initial_state: :stopped, initial_data: 0

    state stopped do
      event run(speed) do
        transition(:running, speed)
      end
    end

    state running do
      event slowdown(by), data: speed do
        transition(:running, speed - by)
      end

      event stop do
        transition(:stopped, 0)
      end
    end
  end

  test "data" do
    assert(
      DataFsm.new
      |> DataFsm.data == 0
    )

    assert(
      DataFsm.new
      |> DataFsm.run(50)
      |> DataFsm.data == 50
    )

    assert(
      DataFsm.new
      |> DataFsm.run(50)
      |> DataFsm.slowdown(20)
      |> DataFsm.data == 30
    )

    assert(
      DataFsm.new
      |> DataFsm.run(50)
      |> DataFsm.stop
      |> DataFsm.data == 0
    )
  end



  defmodule ResponseFsm do
    use Fsm, initial_state: :stopped, initial_data: 0

    state stopped do
      event run(speed) do
        respond(:ok, :running, speed)
      end

      event _ do
        respond(:error)
      end
    end

    state running do
      event stop do
        respond(:ok, :stopped, 0)
      end

      event _ do
        respond(:error, :invalid)
      end
    end
  end

  test "response actions" do
    {response, fsm} = ResponseFsm.new
    |> ResponseFsm.run(50)

    assert(response == :ok)
    assert(ResponseFsm.state(fsm) == :running)
    assert(ResponseFsm.data(fsm) == 50)

    {response2, fsm2} = ResponseFsm.run(fsm, 10)
    assert(response2 == :error)
    assert(ResponseFsm.state(fsm2) == :invalid)

    assert(
      ResponseFsm.new
      |> ResponseFsm.stop == {:error, %ResponseFsm{data: 0, state: :stopped}}
    )
  end



  defmodule PatternMatch do
    use Fsm, initial_state: :running, initial_data: 10

    state running do
      event toggle_speed, data: d, when: d == 10 do
        transition(:running, 50)
      end

      event toggle_speed, data: 50 do
        transition(:running, 10)
      end

      event set_speed(1) do
        transition(:running, 10)
      end

      event set_speed(x), when: x == 2 do
        transition(:running, 50)
      end

      event stop, do: transition(:stopped)
    end

    event dummy, state: :stopped do
      respond(:dummy)
    end

    event _, event: :toggle_speed do
      respond(:error)
    end
  end

  test "pattern match" do
    assert(
      PatternMatch.new
      |> PatternMatch.toggle_speed
      |> PatternMatch.data == 50
    )

    assert(
      PatternMatch.new
      |> PatternMatch.toggle_speed
      |> PatternMatch.toggle_speed
      |> PatternMatch.data == 10
    )

    assert(
      PatternMatch.new
      |> PatternMatch.set_speed(1)
      |> PatternMatch.data == 10
    )

    assert(
      PatternMatch.new
      |> PatternMatch.set_speed(2)
      |> PatternMatch.data == 50
    )

    assert_raise(FunctionClauseError, fn ->
      PatternMatch.new
      |> PatternMatch.set_speed(3)
      |> PatternMatch.data == 50
    end)

    assert(
      PatternMatch.new
      |> PatternMatch.stop
      |> PatternMatch.dummy == {:dummy, %PatternMatch{data: 10, state: :stopped}}
    )

    assert(
      PatternMatch.new
      |> PatternMatch.stop
      |> PatternMatch.toggle_speed == {:error, %PatternMatch{data: 10, state: :stopped}}
    )

    assert_raise(FunctionClauseError, fn ->
      PatternMatch.new
      |> PatternMatch.dummy
    end)

    assert_raise(FunctionClauseError, fn ->
      PatternMatch.new
      |> PatternMatch.stop
      |> PatternMatch.stop
    end)

    assert_raise(FunctionClauseError, fn ->
      PatternMatch.new
      |> PatternMatch.stop
      |> PatternMatch.set_speed(1)
    end)
  end



  defmodule DynamicFsm do
    use Fsm, initial_state: :stopped

    fsm = [
      stopped: [run: :running],
      running: [stop: :stopped]
    ]

    for {state, transitions} <- fsm do
      state unquote(state) do
        for {event, target_state} <- transitions do
          event unquote(event) do
            transition(unquote(target_state))
          end
        end
      end
    end
  end

  test "dynamic" do
    assert(
      DynamicFsm.new
      |> DynamicFsm.state == :stopped)

    assert(
      DynamicFsm.new
      |> DynamicFsm.run
      |> DynamicFsm.state == :running)

    assert(
      DynamicFsm.new
      |> DynamicFsm.run
      |> DynamicFsm.stop
      |> DynamicFsm.state == :stopped)

    assert_raise(FunctionClauseError, fn ->
      DynamicFsm.new
      |> DynamicFsm.run
      |> DynamicFsm.run
    end)
  end
end
