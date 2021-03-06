%% @doc dripline_jumpstart is a process that gets the dripline ball
%%		rolling.  it is responsible for pulling all of the starting
%%		data from the database and informing dripling_conf_mgr.
%%		it exports a single function, go/0, and returns 'ok' on 
%%		successful startup.  Only in the case of a configuration 
%%		failure that means dripline cannot run at all should it return
%%		an error.
-module(dripline_jumpstart).
-export([go/0]).

-spec go() -> ok | {error, term()}.
go() ->
	ServerConnection = dripline_conn_mgr:get(),
	ok = configure_channels(ServerConnection),
	ok = configure_instruments(ServerConnection),
	ok = configure_loggers(ServerConnection).

%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% internal functions %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%

%%---------------------------------------------------------------------%%
%% @doc configure_channels gets all of the channel documents from the 
%%		database and transforms them into channel_data structures.  it 
%%		then populates the conf_mgr with channels.
%% @tod should report errors
%% @end
%%---------------------------------------------------------------------%%
-spec configure_channels(any()) -> ok.
configure_channels(SConn) ->	
	{ok, Db} = couchbeam:open_db(SConn,"dripline_conf"),
	{ok, AllInstr} = couchbeam_view:fetch(Db,{"objects","instruments"}),
	{ok, AllChannels} = couchbeam_view:fetch(Db,{"objects","channels"}),
	generate_channel_conf(AllChannels,AllInstr).

generate_channel_conf(ChViewRes,InViewRes) ->
	[StrippedCh,StrippedIn] = lists:map(fun(X) -> 
						    strip_values(X) 
					    end, 
					    [ChViewRes,InViewRes]),
	generate_st_channel_conf(StrippedCh,StrippedIn).
generate_st_channel_conf([],_) ->
	ok;
generate_st_channel_conf([H|T],Instr) ->
    InstrId = props:get(instrument,H),
    case get_call_data(InstrId,Instr) of
	    {ok, [Name,Model]} ->
		CD0 = dripline_ch_data:new(),
		CD1 = dripline_ch_data:set_field(instr,Name,CD0),
		CD2 = dripline_ch_data:set_field(model,Model,CD1),
		ChName = props:get(name,H),
		CD3 = dripline_ch_data:set_field(id,ChName,CD2),
		Locator = props:get(locator,H),
	    Hooks = props:get(post_hooks,H,[]),
	    AtomicHooks = lists:map(fun dripline_util:binary_to_atom/1, Hooks),
	    CD4 = dripline_ch_data:set_field(post_hook, AtomicHooks, CD3),
		CD5 = dripline_ch_data:set_field(locator,Locator,CD4),
	    ChType = dripline_util:binary_to_atom(props:get(sensor_type,H,<<"dmm_dc">>)),
	    CD6 = dripline_ch_data:set_field(type,ChType,CD5),
		ok = dripline_conf_mgr:add_channel(CD6),
		generate_st_channel_conf(T,Instr);
	    {error, _E}=Err ->
		Err
	end.
get_call_data(_,[]) ->
	{error,instrument_not_found};
get_call_data(Id,[In|Ins]) ->
	case props:get(name,In) of 
	    Id ->
		Model = props:get('instrument_model',In),
		{ok, [Id,Model]};
	    _NotId ->
		get_call_data(Id,Ins)
	end.

%%---------------------------------------------------------------------%%
%% @doc configure_loggers gets all of the loggers from the database and
%%		starts them.  it also populates the conf_mgr with the Pid info.
%% @todo should report errors
%% @end
%%---------------------------------------------------------------------%%
-spec configure_loggers(any()) -> ok.
configure_loggers(SConn) ->
	{ok, Db} = couchbeam:open_db(SConn,"dripline_conf"),
	{ok, AllLoggers} = couchbeam_view:fetch(Db,{"objects","loggers"}),
	generate_loggers_conf(AllLoggers).

generate_loggers_conf(LgViewRes) ->
	StrippedLoggers = strip_values(LgViewRes),
	generate_st_loggers_conf(StrippedLoggers).
generate_st_loggers_conf([]) ->
	ok;
generate_st_loggers_conf([H|T]) ->
	TgtChan = props:get(channel,H),
	Interval = props:get(interval,H),
	NumInterval = strip_interval(Interval),
	case dripline:start_logging(TgtChan,NumInterval) of
		ok ->
			generate_st_loggers_conf(T);
	    Other ->
			%% error report here
		error_logger:error_msg("error logging ~p: ~p",[TgtChan,Other]),
			generate_st_loggers_conf(T)
	end.

%%---------------------------------------------------------------------%%
%% @doc configure_instruments gets all of the instruments from the 
%%		database and populates the conf_mgr with their information.
%% @todo should report errors
%% @end
%%---------------------------------------------------------------------%%
-spec configure_instruments(any()) -> ok.
configure_instruments(SConn) ->
	{ok, Db} = couchbeam:open_db(SConn,"dripline_conf"),
	{ok, AllInstr} = couchbeam_view:fetch(Db,{"objects","instruments"}),
	generate_instr_conf(AllInstr).

generate_instr_conf(AllInstr) ->
	StrippedInstr = strip_values(AllInstr),
	generate_st_instr_conf(StrippedInstr).
generate_st_instr_conf([]) ->
	ok;
generate_st_instr_conf([H|T]) ->
	InstrId = props:get(name,H),
	InstrBus = props:get(bus,H),
	InstrModule = props:get('instrument_model',H),
	InstrMethods = props:get(supports,H),
	Data = dripline_instr_data:new(),
	Data0 = dripline_instr_data:set_id(InstrId,Data),
	Data1 = dripline_instr_data:set_bus(InstrBus,Data0),
	Data2 = dripline_instr_data:set_supports(InstrMethods,Data1),
	Data3 = dripline_instr_data:set_module(InstrModule,Data2),
	dripline_conf_mgr:add_instr(Data3),
	generate_st_instr_conf(T).

%%---------------------------------------------------------------------%%
%% @doc strip_values strips the value field from a list of documents.
%% @end
%%---------------------------------------------------------------------%%
strip_values(L) ->
	lists:map(fun(X) -> props:get(value,X) end, L).

%%---------------------------------------------------------------------%%
%% @doc strip_interval strips a numeric interval from a binary string.
%% @end
%%---------------------------------------------------------------------%%
strip_interval(B) ->
	L = erlang:binary_to_list(B),
	{N,[]} = string:to_integer(L),
	N.
