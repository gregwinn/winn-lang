%% winn_core_emit.erl
%% Compiles a Core Erlang module (cerl tree) into a .beam binary file.
%%
%% Uses compile:forms/2 with the `from_core` option, which bypasses the
%% Erlang front-end and feeds the Core Erlang directly to the backend.

-module(winn_core_emit).
-export([emit/2, emit_to_binary/1]).

%% Compile a Core Erlang module and write the .beam to OutDir.
%% Returns {ok, BeamFilePath} or {error, Reason}.
emit(CerlModule, OutDir) ->
    case emit_to_binary(CerlModule) of
        {ok, ModName, Binary} ->
            BeamFile = filename:join(OutDir, atom_to_list(ModName) ++ ".beam"),
            case file:write_file(BeamFile, Binary) of
                ok             -> {ok, BeamFile};
                {error, Reason} -> {error, {write_failed, BeamFile, Reason}}
            end;
        {error, _} = Err ->
            Err
    end.

%% Compile a Core Erlang module to a binary. Returns {ok, ModName, Binary}
%% or {error, {compile_failed, Errors}}.
emit_to_binary(CerlModule) ->
    Opts = [from_core, return_errors, return_warnings],
    case compile:forms(CerlModule, Opts) of
        {ok, ModName, Binary, _Warnings} ->
            {ok, ModName, Binary};
        {ok, ModName, Binary} ->
            {ok, ModName, Binary};
        {error, Errors, _Warnings} ->
            {error, {compile_failed, Errors}};
        error ->
            {error, {compile_failed, unknown}}
    end.
