%% winn_stdlib_v07_tests.erl
%% Tests for v0.7.0 stdlib additions: File I/O, Regex, Timer, Retry,
%% System.get_env defaults, DateTime/String improvements.

-module(winn_stdlib_v07_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── File I/O ────────────────────────────────────────────────────────────────

file_write_read_test() ->
    Path = "/tmp/winn_file_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = winn_file:write(Path, <<"hello winn">>),
    {ok, Content} = winn_file:read(Path),
    ?assertEqual(<<"hello winn">>, Content),
    winn_file:delete(Path).

file_exists_test() ->
    Path = "/tmp/winn_exists_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ?assertEqual(false, winn_file:'exists?'(Path)),
    winn_file:write(Path, <<"x">>),
    ?assertEqual(true, winn_file:'exists?'(Path)),
    winn_file:delete(Path).

file_read_bang_test() ->
    Path = "/tmp/winn_bang_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    winn_file:write(Path, <<"data">>),
    ?assertEqual(<<"data">>, winn_file:'read!'(Path)),
    winn_file:delete(Path).

file_read_lines_test() ->
    Path = "/tmp/winn_lines_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    winn_file:write(Path, <<"a\nb\nc">>),
    {ok, Lines} = winn_file:read_lines(Path),
    ?assertEqual([<<"a">>, <<"b">>, <<"c">>], Lines),
    winn_file:delete(Path).

file_list_test() ->
    Dir = "/tmp/winn_list_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    winn_file:mkdir(Dir),
    winn_file:write(Dir ++ "/a.txt", <<"a">>),
    winn_file:write(Dir ++ "/b.txt", <<"b">>),
    {ok, Files} = winn_file:list(Dir),
    ?assertEqual(2, length(Files)),
    os:cmd("rm -rf " ++ Dir).

file_append_test() ->
    Path = "/tmp/winn_append_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    winn_file:write(Path, <<"hello">>),
    winn_file:append(Path, <<" world">>),
    {ok, Content} = winn_file:read(Path),
    ?assertEqual(<<"hello world">>, Content),
    winn_file:delete(Path).

%% ── Regex ───────────────────────────────────────────────────────────────────

regex_match_test() ->
    ?assertEqual(true, winn_regex:'match?'(<<"hello@example.com">>, <<"\\w+@\\w+\\.\\w+">>)),
    ?assertEqual(false, winn_regex:'match?'(<<"not-an-email">>, <<"\\w+@\\w+\\.\\w+">>)).

regex_replace_test() ->
    ?assertEqual(<<"X X">>, winn_regex:replace(<<"hello world">>, <<"\\w+">>, <<"X">>)).

regex_scan_test() ->
    Result = winn_regex:scan(<<"phone: 555-1234, fax: 555-5678">>, <<"\\d{3}-\\d{4}">>),
    ?assertEqual([<<"555-1234">>, <<"555-5678">>], Result).

regex_split_test() ->
    ?assertEqual([<<"a">>, <<"b">>, <<>>, <<"c">>], winn_regex:split(<<"a,b,,c">>, <<",">>)).

%% ── Timer ───────────────────────────────────────────────────────────────────

timer_after_test() ->
    Self = self(),
    TRef = winn_timer:'after'(50, ms, fun() -> Self ! done end),
    ?assert(is_tuple(TRef)),
    receive done -> ok after 500 -> ?assert(false) end.

timer_cancel_test() ->
    TRef = winn_timer:every(10000, ms, fun() -> ok end),
    ?assertEqual(ok, winn_timer:cancel(TRef)).

%% ── Retry ───────────────────────────────────────────────────────────────────

retry_success_test() ->
    ?assertEqual({ok, 42}, winn_retry:run(#{max => 3}, fun() -> 42 end)).

retry_failure_test() ->
    {error, {retries_exhausted, _}} = winn_retry:run(
        #{max => 2, base_delay => 1, max_delay => 10},
        fun() -> error(boom) end
    ).

%% ── System.get_env with default ─────────────────────────────────────────────

system_get_env_default_test() ->
    %% Non-existent env var should return default
    Result = winn_runtime:'system.get_env'(<<"WINN_NONEXISTENT_VAR_12345">>, <<"fallback">>),
    ?assertEqual(<<"fallback">>, Result).

system_get_env_exists_test() ->
    os:putenv("WINN_TEST_VAR_999", "hello"),
    Result = winn_runtime:'system.get_env'(<<"WINN_TEST_VAR_999">>, <<"default">>),
    ?assertEqual(<<"hello">>, Result),
    os:unsetenv("WINN_TEST_VAR_999").

%% ── DateTime additions ──────────────────────────────────────────────────────

datetime_add_test() ->
    Now = winn_runtime:'datetime.now'(),
    Later = winn_runtime:'datetime.add'(Now, 60, seconds),
    ?assertEqual(60, Later - Now).

datetime_add_days_test() ->
    Now = winn_runtime:'datetime.now'(),
    Tomorrow = winn_runtime:'datetime.add'(Now, 1, days),
    ?assertEqual(86400, Tomorrow - Now).

datetime_before_test() ->
    ?assertEqual(true, winn_runtime:'datetime.before?'(100, 200)),
    ?assertEqual(false, winn_runtime:'datetime.before?'(200, 100)).

datetime_after_test() ->
    ?assertEqual(true, winn_runtime:'datetime.after?'(200, 100)),
    ?assertEqual(false, winn_runtime:'datetime.after?'(100, 200)).

%% ── String additions ────────────────────────────────────────────────────────

string_pad_left_test() ->
    ?assertEqual(<<"00042">>, winn_runtime:'string.pad_left'(<<"42">>, 5, <<"0">>)).

string_pad_right_test() ->
    ?assertEqual(<<"hi   ">>, winn_runtime:'string.pad_right'(<<"hi">>, 5, <<" ">>)).

string_repeat_test() ->
    ?assertEqual(<<"ababab">>, winn_runtime:'string.repeat'(<<"ab">>, 3)).

string_byte_size_test() ->
    ?assertEqual(5, winn_runtime:'string.byte_size'(<<"hello">>)).

string_slice_safe_test() ->
    ?assertEqual(<<"hello">>, winn_runtime:'string.slice'(<<"hello">>, 0, 100)),
    ?assertEqual(<<>>, winn_runtime:'string.slice'(<<"hello">>, 10, 5)).

%% ── End-to-end from Winn source ────────────────────────────────────────────

file_from_winn_test() ->
    Mod = compile_and_load(
        "module FileE2e\n"
        "  def run()\n"
        "    File.write(\"/tmp/winn_e2e_test\", \"from winn\")\n"
        "    File.read(\"/tmp/winn_e2e_test\")\n"
        "  end\n"
        "end\n"),
    {ok, Content} = Mod:run(),
    ?assertEqual(<<"from winn">>, Content),
    file:delete("/tmp/winn_e2e_test").

regex_from_winn_test() ->
    Mod = compile_and_load(
        "module RegexE2e\n"
        "  def run()\n"
        "    Regex.match?(\"test@test.com\", \"\\\\w+@\\\\w+\")\n"
        "  end\n"
        "end\n"),
    ?assertEqual(true, Mod:run()).
