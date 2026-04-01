-module(winn_regex).
-export(['match?'/2, replace/3, replace/4, scan/2, split/2,
         named_captures/2]).

%% Regex.match?("hello@example.com", "\\w+@\\w+\\.\\w+")
'match?'(String, Pattern) when is_binary(String), is_binary(Pattern) ->
    case re:run(String, Pattern, [unicode]) of
        {match, _} -> true;
        nomatch    -> false
    end.

%% Regex.replace("hello world", "\\w+", "X")
replace(String, Pattern, Replacement) ->
    replace(String, Pattern, Replacement, [global]).

replace(String, Pattern, Replacement, Opts) when is_binary(String), is_binary(Pattern), is_binary(Replacement) ->
    ReOpts = [unicode, {return, binary}] ++ Opts,
    re:replace(String, Pattern, Replacement, ReOpts).

%% Regex.scan("phone: 555-1234, fax: 555-5678", "\\d{3}-\\d{4}")
scan(String, Pattern) when is_binary(String), is_binary(Pattern) ->
    case re:run(String, Pattern, [global, unicode, {capture, first, binary}]) of
        {match, Matches} -> [M || [M] <- Matches];
        nomatch          -> []
    end.

%% Regex.split("a,b,,c", ",")
split(String, Pattern) when is_binary(String), is_binary(Pattern) ->
    re:split(String, Pattern, [unicode, {return, binary}]).

%% Regex.named_captures("2026-03-28", "(?P<year>\\d{4})-(?P<month>\\d{2})-(?P<day>\\d{2})")
named_captures(String, Pattern) when is_binary(String), is_binary(Pattern) ->
    case re:run(String, Pattern, [unicode, {capture, all_names, binary}]) of
        {match, Values} ->
            {namelist, Names} = re:inspect(re:compile(Pattern, [unicode]), namelist),
            maps:from_list(lists:zip(
                [list_to_atom(binary_to_list(N)) || N <- Names],
                Values
            ));
        nomatch -> #{}
    end.
