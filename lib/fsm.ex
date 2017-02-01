defmodule Fsm do
  defmacro __using__(opts) do
    quote do
      import Fsm

      defstruct [state: unquote(opts[:initial_state]),
                 data:  unquote(opts[:initial_data])]

      @declaring_state nil
      @declared_events MapSet.new

      def new do
        %__MODULE__{}
      end

      def state(%__MODULE__{state: state}), do: state
      def data(%__MODULE__{data: data}), do: data

      defp change_state(%__MODULE__{} = fsm, {:action_responses, responses}), do: parse_action_responses(fsm, responses)
      defp change_state(%__MODULE__{} = fsm, _), do: fsm

      defp parse_action_responses(fsm, responses) do
        Enum.reduce(responses, fsm, fn(response, fsm) ->
          handle_action_response(fsm, response)
        end)
      end

      defp handle_action_response(fsm, {:next_state, next_state}) do
        data = case leave(fsm, fsm.state) do
          {:action_responses, [new_data: new_data]} -> new_data
          _ -> fsm.data
        end
        data = case enter(%{fsm | data: data}, next_state) do
          {:action_responses, [new_data: new_data]} -> new_data
          _ -> data
        end
        %__MODULE__{fsm | state: next_state, data: data}
      end

      defp handle_action_response(fsm, {:new_data, new_data}) do
        %__MODULE__{fsm | data: new_data}
      end

      defp handle_action_response(fsm, {:respond, response}) do
        {response, fsm}
      end

      @before_compile Fsm
    end
  end

  defmacro __before_compile__(_) do
    quote do
      defp enter(_, _), do: nil
      defp leave(_, _), do: nil
    end
  end

  def transition(state) when is_atom(state), do: {:action_responses, [next_state: state]}
  def transition(data), do: {:action_responses, [new_data: data]}
  def transition(state, data), do: {:action_responses, [next_state: state, new_data: data]}

  def respond(response), do: {:action_responses, [respond: response]}
  def respond(response, state), do: {:action_responses, [next_state: state, respond: response]}
  def respond(response, state, data), do: {:action_responses, [next_state: state, new_data: data, respond: response]}

  defmacro state(state, state_def) do
    quote do
      state_name = case unquote(Macro.escape(state, unquote: true)) do
        name when is_atom(name) -> name
        {name, _, _} -> name
      end

      @declaring_state state_name
      unquote(state_def)
      @declaring_state nil
    end
  end

  defmacro event(event) do
    decl_event(event, false)
  end

  defmacro eventp(event) do
    decl_event(event, true)
  end

  defp decl_event(event, private) do
    quote do
      {event_name, arity} = case unquote(Macro.escape(event, unquote: nil)) do
        event_name when is_atom(event_name) -> {event_name, 0}
        {:/, _, [{event_name, _, _}, arity]} -> {event_name, arity}
        {event_name, _, _} -> {event_name, 0}
      end

      args = case arity do
        0 -> []
        n -> Enum.to_list(1..n)
      end

      private = unquote(private)
      unquote(define_interface())
    end
  end

  defmacro event(event, opts) do
    do_defevent(event, opts, opts[:do])
  end

  defmacro event(event, opts, do: event_def) do
    do_defevent(event, opts, event_def)
  end

  defmacro eventp(event, opts) do
    do_defevent(event, [{:private, true} | opts], opts[:do])
  end

  defmacro eventp(event, opts, do: event_def) do
    do_defevent(event, [{:private, true} | opts], event_def)
  end

  defp do_defevent(event_decl, opts, event_def) do
    quote do
      unquote(extract_args(event_decl, opts, event_def))
      unquote(define_interface())
      unquote(implement_transition())
    end
  end

  defp extract_args(event_decl, opts, event_def) do
    quote do
      {event_name, args} = case unquote(Macro.escape(event_decl, unquote: true)) do
        :_ -> {:_, []}
        name when is_atom(name) -> {name, []}
        {name, _, args} -> {name, args || []}
      end

      private = unquote(opts[:private])
      state_arg = unquote(Macro.escape(opts[:state] || quote(do: _), unquote: true))
      data_arg = unquote(Macro.escape(opts[:data] || quote(do: _), unquote: true))
      event_arg = unquote(Macro.escape(opts[:event] || quote(do: _), unquote: true))
      args_arg = unquote(Macro.escape(opts[:args] || quote(do: _), unquote: true))
      event_def = unquote(Macro.escape(event_def, unquote: true))
      guard = unquote(Macro.escape(opts[:when]))
    end
  end

  defp define_interface do
    quote bind_quoted: [] do
      unless event_name == :_ or MapSet.member?(@declared_events, {event_name, length(args)}) do
        interface_args = Enum.reduce(args, {0, []}, fn(_, {index, args}) ->
          {
            index + 1,
            [{:"arg#{index}", [], nil} | args]
          }
        end)
        |> elem(1)
        |> Enum.reverse

        body = quote do
          transition(fsm, unquote(event_name), [unquote_splicing(interface_args)])
        end

        interface_args = [quote(do: fsm) | interface_args]

        if private do
          defp unquote(event_name)(unquote_splicing(interface_args)), do: unquote(body)
        else
          def unquote(event_name)(unquote_splicing(interface_args)), do: unquote(body)
        end

        @declared_events MapSet.put(@declared_events, {event_name, length(args)})
      end
    end
  end

  defp implement_transition do
    quote bind_quoted: [] do
      transition_args = [
        if @declaring_state do
          quote do
            %__MODULE__{state: unquote(@declaring_state) = unquote(state_arg), data: unquote(data_arg)} = fsm
          end
        else
          quote do
            %__MODULE__{state: unquote(state_arg), data: unquote(data_arg)} = fsm
          end
        end,

        quote do
          unquote(if event_name == :_, do: quote(do: _), else: event_name) = unquote(event_arg)
        end,

        quote do
          unquote(if event_name == :_, do: quote(do: _), else: args) = unquote(args_arg)
        end
      ]

      body = quote(do: change_state(fsm, (unquote(event_def))))

      if guard do
        def transition(unquote_splicing(transition_args)) when unquote(guard), do: unquote(body)
      else
        def transition(unquote_splicing(transition_args)), do: unquote(body)
      end
    end
  end

  defmacro on(handler_decl, opts) do
    do_defhandler(handler_decl, opts, opts[:do])
  end

  defmacro on(handler_decl, opts, do: handler_def) do
    do_defhandler(handler_decl, opts, handler_def)
  end

  defp do_defhandler handler_decl, opts, handler_def do
    handler_name = case handler_decl do
      name when is_atom(name) -> name
      {name, _, _} -> name
    end
    data_arg = opts[:data]
    fsm_arg = if data_arg do
      quote do
        %__MODULE__{data: var!(unquote(data_arg))} = fsm
      end
    else
      quote do: fsm
    end
    quote do
      defp unquote(handler_name)(unquote(fsm_arg), @declaring_state) do
        unquote(handler_def)
      end
    end
  end
end
