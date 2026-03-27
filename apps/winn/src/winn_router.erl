%% winn_router.erl
%% Cowboy handler that dispatches HTTP requests to Winn router modules.
%%
%% A Winn router module defines routes/0 returning a list of
%% {Method, PathPattern, HandlerFun} tuples, plus handler functions
%% that take a conn map and return a conn map.

-module(winn_router).
-behaviour(cowboy_handler).
-export([init/2]).
-export([match_route/3, match_path/2]).  %% exported for testing

init(Req, #{router := RouterModule} = State) ->
    Method = method_atom(cowboy_req:method(Req)),
    Path = cowboy_req:path(Req),
    Routes = RouterModule:routes(),
    case match_route(Method, Path, Routes) of
        {ok, HandlerFun, PathParams} ->
            QsParams = maps:from_list(cowboy_req:parse_qs(Req)),
            Conn = #{
                req          => Req,
                method       => cowboy_req:method(Req),
                path         => Path,
                path_params  => PathParams,
                query_params => QsParams,
                body_params  => nil
            },
            ResultConn = RouterModule:HandlerFun(Conn),
            FinalReq = maps:get(req, ResultConn, Req),
            {ok, FinalReq, State};
        nomatch ->
            Req2 = cowboy_req:reply(404,
                #{<<"content-type">> => <<"application/json">>},
                jsone:encode(#{<<"error">> => <<"not found">>}), Req),
            {ok, Req2, State}
    end.

%% ── Route matching ──────────────────────────────────────────────────────

match_route(_Method, _Path, []) ->
    nomatch;
match_route(Method, Path, [{Method, Pattern, Handler} | Rest]) ->
    case match_path(Pattern, Path) of
        {ok, Params} -> {ok, Handler, Params};
        nomatch      -> match_route(Method, Path, Rest)
    end;
match_route(Method, Path, [_ | Rest]) ->
    match_route(Method, Path, Rest).

%% Match a route pattern against a request path.
%% Pattern: <<"/users/:id">>  Path: <<"/users/42">>
%% Returns {ok, #{<<"id">> => <<"42">>}} or nomatch.
match_path(Pattern, Path) when is_binary(Pattern), is_binary(Path) ->
    PatSegs  = split_path(Pattern),
    PathSegs = split_path(Path),
    match_segments(PatSegs, PathSegs, #{}).

split_path(P) ->
    [S || S <- binary:split(P, <<"/">>, [global]), S =/= <<>>].

match_segments([], [], Params) ->
    {ok, Params};
match_segments([<<$:, Name/binary>> | PatRest], [Val | PathRest], Params) ->
    match_segments(PatRest, PathRest, Params#{Name => Val});
match_segments([Seg | PatRest], [Seg | PathRest], Params) ->
    match_segments(PatRest, PathRest, Params);
match_segments(_, _, _) ->
    nomatch.

%% ── Method conversion ───────────────────────────────────────────────────

method_atom(<<"GET">>)     -> get;
method_atom(<<"POST">>)    -> post;
method_atom(<<"PUT">>)     -> put;
method_atom(<<"PATCH">>)   -> patch;
method_atom(<<"DELETE">>)  -> delete;
method_atom(<<"HEAD">>)    -> head;
method_atom(<<"OPTIONS">>) -> options;
method_atom(Other)         -> binary_to_atom(string:lowercase(Other), utf8).
