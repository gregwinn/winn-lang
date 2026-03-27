-module(winn_changeset).
-export([
    new/2,
    validate_required/2,
    validate_length/4,
    valid/1,
    errors/1,
    apply_changes/1
]).

%% Changeset: #{data => map(), changes => map(), errors => [], valid => bool()}

new(Data, Attrs) ->
    Changes = maps:fold(fun(K, V, Acc) ->
        case maps:get(K, Data, undefined) of
            V    -> Acc;
            _Old -> Acc#{K => V}
        end
    end, #{}, Attrs),
    #{data => Data, changes => Changes, errors => [], valid => true}.

validate_required(Changeset, Fields) ->
    #{changes := Changes, errors := Errors} = Changeset,
    NewErrors = lists:foldl(fun(Field, Acc) ->
        case maps:get(Field, Changes, undefined) of
            undefined -> [{Field, <<"can't be blank">>} | Acc];
            <<>>      -> [{Field, <<"can't be blank">>} | Acc];
            _         -> Acc
        end
    end, Errors, Fields),
    Changeset#{errors => NewErrors, valid => NewErrors =:= []}.

validate_length(Changeset, Field, min, Min) ->
    #{changes := Changes, errors := Errors} = Changeset,
    case maps:get(Field, Changes, undefined) of
        undefined -> Changeset;
        Val when is_binary(Val), byte_size(Val) < Min ->
            Msg = iolist_to_binary(["should be at least ", integer_to_binary(Min), " characters"]),
            Changeset#{errors => [{Field, Msg} | Errors], valid => false};
        _ -> Changeset
    end.

valid(#{valid := V}) -> V.
errors(#{errors := E}) -> E.
apply_changes(#{data := Data, changes := Changes}) ->
    maps:merge(Data, Changes).
