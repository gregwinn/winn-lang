-module(winn_agent_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Helpers ────────────────────────────────────────────────────────────────

compile_and_load(Source) ->
    {ok, Tokens, _} = winn_lexer:string(Source),
    Filtered = winn_newline_filter:filter(Tokens),
    {ok, AST} = winn_parser:parse(Filtered),
    Transformed = winn_transform:transform(AST),
    [CoreMod] = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Basic agent: start, call, read ─────────────────────────────────────────

basic_counter_test() ->
    Mod = compile_and_load(
        "agent BasicCounter\n"
        "  state count = 0\n"
        "  def increment()\n"
        "    @count = @count + 1\n"
        "  end\n"
        "  def value()\n"
        "    @count\n"
        "  end\n"
        "end\n"),
    Pid = Mod:start(),
    ?assert(is_pid(Pid)),
    ?assertEqual(1, Mod:increment(Pid)),
    ?assertEqual(2, Mod:increment(Pid)),
    ?assertEqual(2, Mod:value(Pid)),
    gen_server:stop(Pid).

%% ── Agent with arguments ──────────────────────────────────────────────────

agent_with_args_test() ->
    Mod = compile_and_load(
        "agent ArgCounter\n"
        "  state count = 0\n"
        "  def add(n)\n"
        "    @count = @count + n\n"
        "  end\n"
        "  def value()\n"
        "    @count\n"
        "  end\n"
        "end\n"),
    Pid = Mod:start(),
    ?assertEqual(5, Mod:add(Pid, 5)),
    ?assertEqual(15, Mod:add(Pid, 10)),
    ?assertEqual(15, Mod:value(Pid)),
    gen_server:stop(Pid).

%% ── Multiple state variables ──────────────────────────────────────────────

multi_state_test() ->
    Mod = compile_and_load(
        "agent MultiState\n"
        "  state x = 1\n"
        "  state y = 2\n"
        "  def sum()\n"
        "    @x + @y\n"
        "  end\n"
        "  def set_x(val)\n"
        "    @x = val\n"
        "  end\n"
        "  def set_y(val)\n"
        "    @y = val\n"
        "  end\n"
        "end\n"),
    Pid = Mod:start(),
    ?assertEqual(3, Mod:sum(Pid)),
    ?assertEqual(10, Mod:set_x(Pid, 10)),
    ?assertEqual(12, Mod:sum(Pid)),
    ?assertEqual(20, Mod:set_y(Pid, 20)),
    ?assertEqual(30, Mod:sum(Pid)),
    gen_server:stop(Pid).

%% ── Start with overrides ──────────────────────────────────────────────────

start_with_overrides_test() ->
    Mod = compile_and_load(
        "agent OverrideCounter\n"
        "  state count = 0\n"
        "  def value()\n"
        "    @count\n"
        "  end\n"
        "end\n"),
    %% Default start
    Pid1 = Mod:start(),
    ?assertEqual(0, Mod:value(Pid1)),
    gen_server:stop(Pid1),
    %% Start with override
    Pid2 = Mod:start(#{count => 100}),
    ?assertEqual(100, Mod:value(Pid2)),
    gen_server:stop(Pid2).

%% ── Async def (cast) ──────────────────────────────────────────────────────

async_def_test() ->
    Mod = compile_and_load(
        "agent AsyncAgent\n"
        "  state count = 0\n"
        "  async def bump()\n"
        "    @count = @count + 1\n"
        "  end\n"
        "  def value()\n"
        "    @count\n"
        "  end\n"
        "end\n"),
    Pid = Mod:start(),
    ?assertEqual(ok, Mod:bump(Pid)),
    %% Cast is async, give it a moment to process
    timer:sleep(10),
    ?assertEqual(1, Mod:value(Pid)),
    gen_server:stop(Pid).

%% ── State isolation between instances ─────────────────────────────────────

state_isolation_test() ->
    Mod = compile_and_load(
        "agent IsoCounter\n"
        "  state count = 0\n"
        "  def increment()\n"
        "    @count = @count + 1\n"
        "  end\n"
        "  def value()\n"
        "    @count\n"
        "  end\n"
        "end\n"),
    Pid1 = Mod:start(),
    Pid2 = Mod:start(),
    Mod:increment(Pid1),
    Mod:increment(Pid1),
    Mod:increment(Pid1),
    Mod:increment(Pid2),
    ?assertEqual(3, Mod:value(Pid1)),
    ?assertEqual(1, Mod:value(Pid2)),
    gen_server:stop(Pid1),
    gen_server:stop(Pid2).

%% ── Return values ─────────────────────────────────────────────────────────

return_values_test() ->
    Mod = compile_and_load(
        "agent ReturnAgent\n"
        "  state items = []\n"
        "  def reset()\n"
        "    @items = []\n"
        "    :ok\n"
        "  end\n"
        "  def get_items()\n"
        "    @items\n"
        "  end\n"
        "end\n"),
    Pid = Mod:start(),
    ?assertEqual(ok, Mod:reset(Pid)),
    ?assertEqual([], Mod:get_items(Pid)),
    gen_server:stop(Pid).

%% ── Multiple writes in one function ───────────────────────────────────────

multiple_writes_test() ->
    Mod = compile_and_load(
        "agent SwapAgent\n"
        "  state a = 1\n"
        "  state b = 2\n"
        "  def swap()\n"
        "    temp = @a\n"
        "    @a = @b\n"
        "    @b = temp\n"
        "    :ok\n"
        "  end\n"
        "  def get_a()\n"
        "    @a\n"
        "  end\n"
        "  def get_b()\n"
        "    @b\n"
        "  end\n"
        "end\n"),
    Pid = Mod:start(),
    ?assertEqual(1, Mod:get_a(Pid)),
    ?assertEqual(2, Mod:get_b(Pid)),
    Mod:swap(Pid),
    ?assertEqual(2, Mod:get_a(Pid)),
    ?assertEqual(1, Mod:get_b(Pid)),
    gen_server:stop(Pid).

%% ── Agent with string state ──────────────────────────────────────────────

string_state_test() ->
    Mod = compile_and_load(
        "agent Greeter\n"
        "  state name = \"world\"\n"
        "  def set_name(n)\n"
        "    @name = n\n"
        "  end\n"
        "  def greet()\n"
        "    @name\n"
        "  end\n"
        "end\n"),
    Pid = Mod:start(),
    ?assertEqual(<<"world">>, Mod:greet(Pid)),
    Mod:set_name(Pid, <<"Alice">>),
    ?assertEqual(<<"Alice">>, Mod:greet(Pid)),
    gen_server:stop(Pid).
