%% winn_agent.erl
%% Runtime helpers for Winn agents (stateful actors).
%% Agents are GenServers under the hood; this module provides
%% convenience functions for managing agent lifecycle.

-module(winn_agent).
-export([stop/1, stop/2]).

%% Stop an agent gracefully.
stop(Pid) ->
    gen_server:stop(Pid).

%% Stop an agent with a reason and timeout.
stop(Pid, Reason) ->
    gen_server:stop(Pid, Reason, 5000).
