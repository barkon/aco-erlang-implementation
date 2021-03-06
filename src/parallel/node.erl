-module (node).
-export ([initNodes/3, node/5]).

% evaporation coefficient
-define(EvaCo, 0.05).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%                Node                %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% INITIALIZE PHEROMONES MAP
initPheromones(N, Omit) -> initPheromones(N, Omit, N, #{}).
initPheromones(_, _, 0, Acc) -> Acc;
initPheromones(N, Omit, NodeNo, Acc) -> 
	if 
		Omit == NodeNo ->
			initPheromones(N, Omit, NodeNo - 1, Acc);
		true ->
			initPheromones(N, Omit, NodeNo - 1, maps:put(NodeNo, 1.0, Acc))
	end.

% INITIALIZE DISTANCETO MAP OF DISTANCES TO OTHER NODES
initDistanceTo(N, Omit, AdjTable) -> initDistanceTo(N, Omit, AdjTable, N, #{}).
initDistanceTo(_, _, _, 0, Acc) -> Acc;
initDistanceTo(N, Omit, AdjTable, NodeNo, Acc) -> 
	if 
		Omit == NodeNo ->
			initDistanceTo(N, Omit, AdjTable, NodeNo - 1, Acc);
		true ->
			Distance = maps:get({Omit,NodeNo}, AdjTable),
			initDistanceTo(N, Omit, AdjTable, NodeNo - 1, maps:put(NodeNo, Distance, Acc))
	end.

% INITIALIZE NODES
% 	RETURNS #{NodeNo => PID, ...}
%   FORMAT:	DistanceTo, Pheromones: #{NodeNo => value, ...}
initNodes(N, AdjTable, AntsQuantity) -> initNodes(N, N, AntsQuantity, AdjTable, #{}).
initNodes(_N, 0, _AntsQuantity, _AdjTable, Acc) -> Acc;
initNodes(N, NodeNo, AntsQuantity, AdjTable, Acc) -> 
	DistanceTo = initDistanceTo(N, NodeNo, AdjTable),
    Pheromones = initPheromones(N, NodeNo),
    Pid = spawn(node, node, [NodeNo, DistanceTo, Pheromones, AntsQuantity, 1]),
    initNodes(N, NodeNo - 1, AntsQuantity, AdjTable, maps:put(NodeNo, Pid, Acc)).
    
% NODE PROCESS MESSAGE HANDLING
node(NodeNo, DistanceTo, Pheromones, AntsQuantity, AntsThatPassedThrough) -> 
	receive
		{where, {Ant}} -> 
            Ant ! {decide, {DistanceTo, Pheromones}},
            node(NodeNo, DistanceTo, Pheromones, AntsQuantity, AntsThatPassedThrough);
        {update, {Next, Addition}} ->
            NewPheromoneValue = maps:get(Next, Pheromones) + Addition,
            UpdatedPheromones = maps:update(Next, NewPheromoneValue, Pheromones),
            case AntsThatPassedThrough rem AntsQuantity of
                0 -> 
                    self() ! {evaporate};
                _ -> 
                    ok
            end,
            node(NodeNo, DistanceTo, UpdatedPheromones, AntsQuantity, AntsThatPassedThrough + 1);
        {evaporate} ->
            Evaporate = fun(K, V, Acc) -> maps:put(K, (1 - ?EvaCo) * V, Acc) end,
            EvaporatedPheromones = maps:fold(Evaporate, #{}, Pheromones),
			node(NodeNo, DistanceTo, EvaporatedPheromones, AntsQuantity, AntsThatPassedThrough);
        {die} ->
                exit(kill);
		_ ->
			node(NodeNo, DistanceTo, Pheromones, AntsQuantity, AntsThatPassedThrough)
	end.