%% winn_auth_fake_repo.erl
%% In-memory test double for winn_repo, used by winn_auth_tests to exercise the
%% Auth service (register/login/current_user) without a live database.
%%
%% Mirrors the winn_repo return shapes exactly:
%%   insert/2     -> {ok, RecordMap}   (atom keys, with an auto-assigned `id`)
%%   get/2 (id)   -> {ok, RecordMap} | {error, not_found}
%%   get/3 (field)-> {ok, RecordMap} | {error, not_found}
%%   delete/1     -> ok               (by `id`, like winn_repo:delete/1)
%%
%% Holds both users and auth tokens (fields don't collide), so it backs the whole
%% Auth flow. Inject it via:  winn_config:put(auth, repo_module, winn_auth_fake_repo).
-module(winn_auth_fake_repo).
-export([reset/0, insert/2, get/2, get/3, delete/1]).

-define(TAB, winn_auth_fake_repo_tab).

%% Clear all rows (call in each test's setup).
reset() ->
    ensure(),
    ets:delete_all_objects(?TAB),
    ok.

insert(_Schema, Attrs) when is_map(Attrs) ->
    ensure(),
    %% Monotonic id so deletes never free an id a later insert could reuse.
    Id  = erlang:unique_integer([positive, monotonic]),
    Rec = Attrs#{id => Id},
    ets:insert(?TAB, {Id, Rec}),
    {ok, Rec}.

delete(#{id := Id}) ->
    ensure(),
    ets:delete(?TAB, Id),
    ok;
delete(_) ->
    {error, not_a_schema_struct}.

get(_Schema, Id) ->
    ensure(),
    case ets:lookup(?TAB, Id) of
        [{_, Rec}] -> {ok, Rec};
        []         -> {error, not_found}
    end.

get(_Schema, Field, Value) ->
    ensure(),
    Matches = [Rec || {_, Rec} <- ets:tab2list(?TAB),
                      maps:get(Field, Rec, undefined) =:= Value],
    case Matches of
        [Rec | _] -> {ok, Rec};
        []        -> {error, not_found}
    end.

ensure() ->
    case ets:whereis(?TAB) of
        undefined -> ets:new(?TAB, [named_table, public, set]);
        _         -> ?TAB
    end.
