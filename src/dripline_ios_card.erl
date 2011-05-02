% dripline_ios_card.erl
% written by jared kofron <jared.kofron@gmail.com>
% a state machine which acts as a wrapper around a particular
% hardware card.  requests to go to cardA, cardB, etc are routed
% through this state machine.
-module(dripline_ios_card).
-behavior(gen_fsm).

% states!
-export([idle/2,idle/3]).

% gen_fsm exports
-export([start_link/2,init/1,terminate/3,code_change/4]).
-export([handle_info/3,handle_event/3,handle_sync_event/4]).

% states
idle(_Event, _From, StateData) ->
    {reply, ok, idle, StateData}.
idle(_Event, StateData) ->
    {next_state, idle, StateData}.

% gen_fsm exports
start_link(SlotName,CardModel) ->
    gen_fsm:start_link({local,SlotName},?MODULE,[SlotName,CardModel],[]).

init([SlotName,CardModel]) ->
    io:format("ios got slot name ~p with model ~p~n",[SlotName,CardModel]),
    {ok,idle,nodata}.

terminate(_Reason,_StateName,_StateData) ->
    ok.

handle_event(_Event,StateName,StateData) ->
    {next_state, StateName, StateData}.

handle_sync_event(_Event,_From,StateName,StateData) ->
    {reply, ok, StateName, StateData}.

handle_info(_Info, StateName, StateData) ->
    {next_state, StateName, StateData}.

code_change(_OldVsn,StateName,StateData,_Extra) ->
    {ok,StateName,StateData}.
