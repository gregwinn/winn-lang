%% winn_router.erl
%% Cowboy handler that dispatches HTTP requests to Winn router modules.
%%
%% A Winn router module defines:
%%   routes/0      -> [{Method, PathPattern, HandlerFun}]
%%   middleware/0  -> [MiddlewareFunName]  (optional)
%%
%% Each handler takes a conn map and returns a conn map.
%% Each middleware takes (conn, next) where next is a fun(conn) -> conn.

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
            %% Build middleware chain with handler at the end.
            Handler = fun(C) -> RouterModule:HandlerFun(C) end,
            Chain = build_chain(RouterModule, Handler),
            ResultConn = Chain(Conn),
            FinalReq = maps:get(req, ResultConn, Req),
            {ok, FinalReq, State};
        nomatch ->
            Req2 = cowboy_req:reply(404,
                #{<<"content-type">> => <<"application/json">>},
                jsone:encode(#{<<"error">> => <<"not found">>}), Req),
            {ok, Req2, State}
    end.

%% ── Middleware chain ────────────────────────────────────────────────────

%% Build a chain of middleware funs wrapping the handler.
%% If the router exports middleware/0, use it; otherwise just the handler.
build_chain(RouterModule, Handler) ->
    case erlang:function_exported(RouterModule, middleware, 0) of
        true ->
            MiddlewareNames = RouterModule:middleware(),
            build_chain_from_list(RouterModule, MiddlewareNames, Handler);
        false ->
            Handler
    end.

%% Fold middleware list right-to-left: last middleware wraps the handler,
%% first middleware is the outermost.
build_chain_from_list(_RouterModule, [], Handler) ->
    Handler;
build_chain_from_list(RouterModule, [cors | Rest], Handler) ->
    Inner = build_chain_from_list(RouterModule, Rest, Handler),
    CorsConfig = case erlang:function_exported(RouterModule, cors_config, 0) of
        true  -> RouterModule:cors_config();
        false -> #{}
    end,
    fun(Conn) -> winn_cors:middleware(Conn, Inner, CorsConfig) end;
build_chain_from_list(RouterModule, [MwName | Rest], Handler) ->
    Inner = build_chain_from_list(RouterModule, Rest, Handler),
    fun(Conn) -> RouterModule:MwName(Conn, Inner) end.

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
