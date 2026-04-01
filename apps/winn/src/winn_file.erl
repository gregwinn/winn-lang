-module(winn_file).
-export([read/1, 'read!'/1, write/2, 'write!'/2, append/2,
         'exists?'/1, delete/1, mkdir/1, list/1, read_lines/1]).

%% File.read(path) -> {:ok, binary} | {:error, reason}
read(Path) when is_binary(Path) ->
    file:read_file(Path);
read(Path) when is_list(Path) ->
    file:read_file(Path).

%% File.read!(path) -> binary (raises on error)
'read!'(Path) ->
    case read(Path) of
        {ok, Bin} -> Bin;
        {error, Reason} -> error({file_read_error, Path, Reason})
    end.

%% File.write(path, data) -> ok | {:error, reason}
write(Path, Data) when is_binary(Path) ->
    file:write_file(Path, Data);
write(Path, Data) when is_list(Path) ->
    file:write_file(Path, Data).

%% File.write!(path, data) -> ok (raises on error)
'write!'(Path, Data) ->
    case write(Path, Data) of
        ok -> ok;
        {error, Reason} -> error({file_write_error, Path, Reason})
    end.

%% File.append(path, data) -> ok | {:error, reason}
append(Path, Data) ->
    file:write_file(Path, Data, [append]).

%% File.exists?(path) -> true | false
'exists?'(Path) when is_binary(Path) ->
    filelib:is_file(binary_to_list(Path));
'exists?'(Path) when is_list(Path) ->
    filelib:is_file(Path).

%% File.delete(path) -> ok | {:error, reason}
delete(Path) when is_binary(Path) ->
    file:delete(binary_to_list(Path));
delete(Path) when is_list(Path) ->
    file:delete(Path).

%% File.mkdir(path) -> ok | {:error, reason}
mkdir(Path) when is_binary(Path) ->
    filelib:ensure_path(binary_to_list(Path));
mkdir(Path) when is_list(Path) ->
    filelib:ensure_path(Path).

%% File.list(dir) -> {:ok, [binary]} | {:error, reason}
list(Dir) when is_binary(Dir) ->
    list(binary_to_list(Dir));
list(Dir) when is_list(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} -> {ok, [list_to_binary(F) || F <- Files]};
        {error, Reason} -> {error, Reason}
    end.

%% File.read_lines(path) -> {:ok, [binary]} | {:error, reason}
read_lines(Path) ->
    case read(Path) of
        {ok, Bin} -> {ok, binary:split(Bin, <<"\n">>, [global])};
        {error, Reason} -> {error, Reason}
    end.
