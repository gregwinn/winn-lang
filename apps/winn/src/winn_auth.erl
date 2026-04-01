-module(winn_auth).
-export([middleware/3]).

%% Auth middleware: extracts Bearer token, validates JWT, adds claims to conn.
%% Returns 401 if token is missing/invalid, unless path is excluded.

middleware(Conn, Next, Config) ->
    Path = maps:get(path, Conn),
    ExcludedPaths = maps:get(exclude, Config, []),
    case is_excluded(Path, ExcludedPaths) of
        true ->
            Next(Conn);
        false ->
            case extract_token(Conn) of
                {ok, Token} ->
                    Secret = maps:get(secret, Config, <<>>),
                    case winn_jwt:verify(Token, Secret) of
                        {ok, Claims} ->
                            Next(Conn#{claims => Claims});
                        {error, _Reason} ->
                            unauthorized(Conn)
                    end;
                {error, _} ->
                    unauthorized(Conn)
            end
    end.

%% ── Internal ────────────────────────────────────────────────────────────────

extract_token(Conn) ->
    Req = maps:get(req, Conn),
    case cowboy_req:header(<<"authorization">>, Req) of
        <<"Bearer ", Token/binary>> ->
            {ok, Token};
        _ ->
            {error, no_token}
    end.

unauthorized(Conn) ->
    winn_server:json(Conn, #{error => <<"unauthorized">>}, 401).

is_excluded(_Path, []) ->
    false;
is_excluded(Path, [Pattern | Rest]) ->
    PatternBin = to_binary(Pattern),
    case match_path_pattern(Path, PatternBin) of
        true  -> true;
        false -> is_excluded(Path, Rest)
    end.

match_path_pattern(Path, Pattern) ->
    case binary:last(Pattern) of
        $* ->
            Prefix = binary:part(Pattern, 0, byte_size(Pattern) - 1),
            binary:match(Path, Prefix) =:= {0, byte_size(Prefix)};
        _ ->
            Path =:= Pattern
    end.

to_binary(V) when is_binary(V) -> V;
to_binary(V) when is_list(V)   -> list_to_binary(V).
