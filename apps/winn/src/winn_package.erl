%% winn_package.erl
%% Package manager for Winn — install, remove, and manage packages.
%% Packages are repos with a package.json manifest and Winn source.

-module(winn_package).
-export([add/1, remove/1, list/0, install/0,
         read_manifest/1, read_project_packages/0,
         get_module_mappings/0]).

-define(PACKAGES_DIR, "_packages").
-define(MANIFEST, "package.json").
-define(REGISTRY_FILE, ".winn_packages.json").

%% ── Public API ───────────────────────────────────────────────────────────────

%% Add a package by name or github:user/repo
add(Name) ->
    {Source, PkgName} = parse_source(Name),
    io:format("  Adding ~s...~n", [PkgName]),
    case fetch_package(Source, PkgName) of
        {ok, PkgDir} ->
            case read_manifest(PkgDir) of
                {ok, Manifest} ->
                    %% Copy Winn source files to project
                    install_package_files(PkgDir, Manifest),
                    %% Add Erlang deps to rebar.config
                    install_erlang_deps(Manifest),
                    %% Register in .winn_packages.json
                    register_package(Manifest),
                    %% Add to project package.json
                    add_to_project_manifest(Manifest),
                    ModName = maps:get(<<"module">>, Manifest, PkgName),
                    io:format("  \e[32m✓\e[0m Installed ~s (~s module)~n", [PkgName, ModName]),
                    ok;
                {error, Reason} ->
                    io:format("  Error reading package manifest: ~p~n", [Reason]),
                    {error, Reason}
            end;
        {error, Reason} ->
            io:format("  Error fetching package: ~p~n", [Reason]),
            {error, Reason}
    end.

remove(Name) ->
    BinName = to_binary(Name),
    Registry = read_registry(),
    case maps:get(BinName, Registry, undefined) of
        undefined ->
            io:format("  Package ~s is not installed.~n", [Name]),
            {error, not_installed};
        _Entry ->
            %% Remove from registry
            NewRegistry = maps:remove(BinName, Registry),
            write_registry(NewRegistry),
            %% Remove from project manifest
            remove_from_project_manifest(BinName),
            %% Remove source files
            PkgDir = filename:join(?PACKAGES_DIR, Name),
            os:cmd("rm -rf " ++ PkgDir),
            io:format("  \e[32m✓\e[0m Removed ~s~n", [Name]),
            ok
    end.

list() ->
    Registry = read_registry(),
    case maps:size(Registry) of
        0 ->
            io:format("  No packages installed.~n"),
            ok;
        _ ->
            io:format("~n  Package       Version   Module~n"),
            io:format("  ────────────────────────────────~n"),
            maps:foreach(fun(Name, Entry) ->
                Version = maps:get(<<"version">>, Entry, <<"??">>),
                Module  = maps:get(<<"module">>, Entry, Name),
                io:format("  ~ts  ~ts  ~ts~n",
                    [pad(binary_to_list(Name), 14),
                     pad(binary_to_list(Version), 10),
                     Module])
            end, Registry),
            io:format("~n"),
            ok
    end.

install() ->
    case read_project_packages() of
        {ok, Packages} ->
            maps:foreach(fun(Name, _Version) ->
                add(binary_to_list(Name))
            end, Packages),
            ok;
        {error, _} ->
            io:format("  No package.json found.~n"),
            {error, no_manifest}
    end.

%% ── Module mappings for codegen ─────────────────────────────────────────────

get_module_mappings() ->
    Registry = read_registry(),
    maps:fold(fun(_Name, Entry, Acc) ->
        Module = maps:get(<<"module">>, Entry, undefined),
        ErlMod = maps:get(<<"erlang_module">>, Entry, undefined),
        case {Module, ErlMod} of
            {undefined, _} -> Acc;
            {_, undefined} -> Acc;
            {M, E} ->
                [{binary_to_atom(M, utf8), binary_to_atom(E, utf8)} | Acc]
        end
    end, [], Registry).

%% ── Package fetching ────────────────────────────────────────────────────────

parse_source("github:" ++ Repo) ->
    {github, Repo};
parse_source(Name) ->
    %% Default: try github gregwinn/winn-<name>
    {github, "gregwinn/winn-" ++ Name}.

fetch_package(github, Repo) ->
    PkgDir = filename:join(?PACKAGES_DIR, filename:basename(Repo)),
    ok = filelib:ensure_path(?PACKAGES_DIR),
    case filelib:is_dir(PkgDir) of
        true ->
            %% Already fetched — pull latest
            os:cmd("cd " ++ PkgDir ++ " && git pull --quiet 2>&1"),
            {ok, PkgDir};
        false ->
            Url = "https://github.com/" ++ Repo ++ ".git",
            Cmd = "git clone --depth 1 --quiet " ++ Url ++ " " ++ PkgDir ++ " 2>&1",
            case os:cmd(Cmd) of
                [] -> {ok, PkgDir};
                Output ->
                    case filelib:is_dir(PkgDir) of
                        true  -> {ok, PkgDir};
                        false -> {error, {clone_failed, Output}}
                    end
            end
    end.

%% ── Manifest reading ───────────────────────────────────────────────────────

read_manifest(PkgDir) ->
    ManifestPath = filename:join(PkgDir, ?MANIFEST),
    case file:read_file(ManifestPath) of
        {ok, Bin} ->
            try
                {ok, jsone:decode(Bin)}
            catch
                _:_ -> {error, invalid_json}
            end;
        {error, Reason} ->
            {error, {manifest_not_found, Reason}}
    end.

read_project_packages() ->
    case file:read_file(?MANIFEST) of
        {ok, Bin} ->
            try
                Manifest = jsone:decode(Bin),
                Packages = maps:get(<<"packages">>, Manifest, #{}),
                {ok, Packages}
            catch
                _:_ -> {error, invalid_json}
            end;
        {error, _} ->
            {error, no_manifest}
    end.

%% ── Installation helpers ────────────────────────────────────────────────────

install_package_files(PkgDir, _Manifest) ->
    SrcDir = filename:join(PkgDir, "src"),
    case filelib:is_dir(SrcDir) of
        true ->
            WinnFiles = filelib:wildcard(SrcDir ++ "/*.winn"),
            ok = filelib:ensure_path("src"),
            lists:foreach(fun(File) ->
                Dest = filename:join("src", filename:basename(File)),
                file:copy(File, Dest),
                io:format("  copied ~s~n", [Dest])
            end, WinnFiles);
        false ->
            ok
    end.

install_erlang_deps(Manifest) ->
    Deps = maps:get(<<"deps">>, Manifest, #{}),
    maps:foreach(fun(Name, Version) ->
        NameStr = binary_to_list(Name),
        VersionStr = binary_to_list(Version),
        winn_deps:add(NameStr, VersionStr)
    end, Deps).

%% ── Registry (.winn_packages.json) ──────────────────────────────────────────

read_registry() ->
    case file:read_file(?REGISTRY_FILE) of
        {ok, Bin} ->
            try jsone:decode(Bin) catch _:_ -> #{} end;
        {error, _} ->
            #{}
    end.

write_registry(Registry) ->
    Bin = jsone:encode(Registry, [{indent, 2}, {space, 1}]),
    file:write_file(?REGISTRY_FILE, Bin).

register_package(Manifest) ->
    Name = maps:get(<<"name">>, Manifest, <<"unknown">>),
    Registry = read_registry(),
    Entry = #{
        <<"version">> => maps:get(<<"version">>, Manifest, <<"0.0.0">>),
        <<"module">> => maps:get(<<"module">>, Manifest, Name),
        <<"erlang_module">> => maps:get(<<"erlang_module">>, Manifest,
            <<"winn_", Name/binary>>),
        <<"description">> => maps:get(<<"description">>, Manifest, <<>>)
    },
    NewRegistry = maps:put(Name, Entry, Registry),
    write_registry(NewRegistry).

%% ── Project manifest (package.json) ─────────────────────────────────────────

add_to_project_manifest(Manifest) ->
    PkgName = maps:get(<<"name">>, Manifest, <<"unknown">>),
    PkgVersion = maps:get(<<"version">>, Manifest, <<"0.0.0">>),
    ProjectManifest = case file:read_file(?MANIFEST) of
        {ok, Bin} -> try jsone:decode(Bin) catch _:_ -> #{} end;
        {error, _} -> #{}
    end,
    Packages = maps:get(<<"packages">>, ProjectManifest, #{}),
    NewPackages = maps:put(PkgName, PkgVersion, Packages),
    NewManifest = maps:put(<<"packages">>, NewPackages, ProjectManifest),
    Bin2 = jsone:encode(NewManifest, [{indent, 2}, {space, 1}]),
    file:write_file(?MANIFEST, Bin2).

remove_from_project_manifest(PkgName) ->
    case file:read_file(?MANIFEST) of
        {ok, Bin} ->
            try
                Manifest = jsone:decode(Bin),
                Packages = maps:get(<<"packages">>, Manifest, #{}),
                NewPackages = maps:remove(PkgName, Packages),
                NewManifest = maps:put(<<"packages">>, NewPackages, Manifest),
                Bin2 = jsone:encode(NewManifest, [{indent, 2}, {space, 1}]),
                file:write_file(?MANIFEST, Bin2)
            catch _:_ -> ok end;
        _ -> ok
    end.

%% ── Helpers ─────────────────────────────────────────────────────────────────

to_binary(S) when is_binary(S) -> S;
to_binary(S) when is_list(S)   -> list_to_binary(S);
to_binary(S) when is_atom(S)   -> atom_to_binary(S, utf8).

pad(Str, Width) ->
    Len = length(Str),
    case Len >= Width of
        true  -> Str;
        false -> Str ++ lists:duplicate(Width - Len, $\s)
    end.
