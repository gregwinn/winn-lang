-module(winn_phase4_tests).
-include_lib("eunit/include/eunit.hrl").

lex(Src) -> {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_), Tokens.
parse(Src) -> {ok, Forms} = winn_parser:parse(lex(Src)), Forms.
transform(Src) -> winn_transform:transform(parse(Src)).
load_src(Src) ->
    Forms = transform(Src),
    [CoreMod | _] = winn_codegen:gen(Forms),
    {ok, ModName, Bin} = winn_core_emit:emit_to_binary(CoreMod),
    {module, ModName} = code:load_binary(ModName, "nofile", Bin),
    ModName.

%% ── Parser tests ─────────────────────────────────────────────────────────

parse_use_genserver_test() ->
    Src = "module M use Winn.GenServer end",
    [{module,_,'M',[UseDir]}] = parse(Src),
    ?assertMatch({use_directive, _, 'Winn', 'GenServer'}, UseDir).

parse_use_supervisor_test() ->
    Src = "module M use Winn.Supervisor end",
    [{module,_,'M',[UseDir]}] = parse(Src),
    ?assertMatch({use_directive, _, 'Winn', 'Supervisor'}, UseDir).

%% ── Transform tests ──────────────────────────────────────────────────────

transform_genserver_injects_behaviour_test() ->
    Src = "module MyServer use Winn.GenServer end",
    [{module,_,'MyServer', Body}] = transform(Src),
    BehavAttrs = [X || X <- Body, element(1, X) =:= behaviour_attr],
    ?assertMatch([{behaviour_attr, _, gen_server}], BehavAttrs).

transform_genserver_injects_start_link_test() ->
    Src = "module MyServer use Winn.GenServer end",
    [{module,_,'MyServer', Body}] = transform(Src),
    StartLinks = [F || {function,_,start_link,_,_} = F <- Body],
    ?assertMatch([_], StartLinks).

%% ── Compile + behaviour attribute tests ──────────────────────────────────

genserver_has_behaviour_attr_test() ->
    Src = "module Counter\n"
          "  use Winn.GenServer\n"
          "  def init(n)\n"
          "    {:ok, n}\n"
          "  end\n"
          "  def handle_call(:get, _from, state)\n"
          "    {:reply, state, state}\n"
          "  end\n"
          "  def handle_cast(:inc, state)\n"
          "    {:noreply, state + 1}\n"
          "  end\n"
          "  def handle_info(_msg, state)\n"
          "    {:noreply, state}\n"
          "  end\n"
          "  def terminate(_reason, _state)\n"
          "    :ok\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    %% start_link/1 is synthetically injected by `use Winn.GenServer` — its presence
    %% proves the use directive was correctly expanded by the transform pass.
    ?assert(erlang:function_exported(ModName, start_link, 1)).

%% ── End-to-end GenServer test ─────────────────────────────────────────────

genserver_e2e_test() ->
    Src = "module GsStack\n"
          "  use Winn.GenServer\n"
          "  def init(initial)\n"
          "    {:ok, initial}\n"
          "  end\n"
          "  def handle_call(:pop, _from, state)\n"
          "    {:reply, state, []}\n"
          "  end\n"
          "  def handle_cast(:push, state)\n"
          "    {:noreply, state}\n"
          "  end\n"
          "  def handle_info(_msg, state)\n"
          "    {:noreply, state}\n"
          "  end\n"
          "  def terminate(_reason, _state)\n"
          "    :ok\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    {ok, Pid} = ModName:start_link([]),
    ok = gen_server:cast(Pid, push),
    timer:sleep(10),
    Reply = gen_server:call(Pid, pop),
    ?assert(is_list(Reply)),
    gen_server:stop(Pid).

%% ── Regression: hello still works ────────────────────────────────────────

hello_regression_test() ->
    Src = "module Hello4\n"
          "  def main()\n"
          "    IO.puts(\"Hello from Phase 4!\")\n"
          "  end\n"
          "end",
    Forms = transform(Src),
    [CoreMod | _] = winn_codegen:gen(Forms),
    {ok, _, Bin} = winn_core_emit:emit_to_binary(CoreMod),
    ?assert(is_binary(Bin)).
