function [flows,CapTot,TXbitsTot,THTot,lastSlotSim,lastSelFlow,varargout] = main(varargin)
% MAIN - This is the main runnable in the Project. The code is built as a
% Discrete Event Simulator (DES) that emulates a 5G Base Station (BS)
% operating in the millimeter wave band. The code iterates over the
% following steps:
%
%  1. Generate 5G traffic closely ressembling the real traffic based on
%     information extracted from Data Bases. 
%  2. Generate traffic flow (in Throughput) per time slot and per user. 
%  3. Allocate users per time slot based on their application demands
%     packet deadline to meet required latency) and the throughput 
%     necessary based on step 2.
%  4. Configure subarrays (antenna sets) at the BS and allocate them to the
%     users to transmit concurrently. We apply an evolutionary algorithm known
%     as Particle-Swarm-Optimization (PSO) to obtain the optimal solution.
%  5. Evaluate the PER using standard-compliant frame and mmWave channel.
%  6. Update traffic flow and iterate back to step 1.
%
% Syntax:  [flows,TXbitsTot,THTot,lastSlotSim,lastSelFlow,varargout] = main([])
%          [flows,TXbitsTot,THTot,lastSlotSim,lastSelFlow,varargout] = ...
%                         main(runnable,conf,problem,flows)
%
% Inputs:
%    conf [optional] - struct containint configuration in data/config_test.dat
%    problem [optional] - struct containint configuration in data/metaproblem_test.dat
%    flows [optional] - Array of structs of length equal to the number of
%            users. For each user, each flow (belonging to each packet) is
%            characterized by the amount of bits that needs to be delivered. The
%            amount of bits are distributed uniformly across the slots until
%            reaching the deadline. Thus, the variable flows contains four features:
%            - slots:     For each flow, the slots across it.
%            - TH:        The average throughput demanded for that flow over the slots
%                         indicated in the slots field.
%            - remaining: We set the remaining field of the flow to be the value of
%                         the Payload.
%            - deadlines: The deadline of the actual packet in slot ID. 
%                         This is used in the future to set priorities.
%            - failed:    Mark whether the flow has failed to be served before the
%                         deadline (0 or 1).
%            - success:   Mark whether the flow has been succesfully served before the
%                         deadline (0 or 1).
%            - maxSlot:   Maximum deadline slot used as simulation time or Tsym in
%                         the system in case trafficType is 'dataSet'.
%
% Outputs:
%    flows - Updated structure from input flows.
%    CapTot - Total capacity achieved throughout the execution.
%    TXbitsTot - Total number of transmitted bits in the execution.
%    THTot - Throguhput achieved in the execution per user.
%    lastSlotSim - Last slot id in the simulation before return.
%    lastSelFlow - Last selected flow per user in the simulation.
%    baseFlow [optional] - Description
%
% Example:
%    [flows,TXbitsTot,THTot,lastSlotSim,lastSelFlow,varargout] = main;
%    main_plotting(problem,TXbitsTot,THTot,baseFlows,lastSelFlow);
%
% Other m-files required: Requires most of the o_*, s_* and f_* functions
% Subfunctions: Calls most of the o_*, s_* and f_* functions
% MAT-files required: Most of the included in data/
%
% See also: main_runnable , main_plotting, CBG_solveit
%
%------------- BEGIN CODE --------------

%% Check correct number of input arguments. If none, then set-up default
% parameters from configuration functions
if (nargin==3)
    % Check inputted parameters have the correct format and assign values
    % in current function if every requirement is met
    if ~isstruct(varargin{1}) || any( structfun(@isempty, varargin{1}) )
        error('ERROR: 1st input parameter should be a non-empty struct ' + ...
            'contaitning the configuration parameters of heuristics\n');
    elseif ~isstruct(varargin{2}) || any( structfun(@isempty, varargin{1}) )
        error('ERROR: 2nd input parameter should be a non-empty struct ' + ...
            'contaitning the configuration parameters of heuristics\n');
    elseif ~isstruct(varargin{3})
        error('ERROR: 3rd input parameter should be a non-empty struct\n');
    elseif isstruct(varargin{3})
        for k = 1:length(varargin{3})
            if any( structfun(@isempty, varargin{3}(k)) )
                error('ERROR: 3rd input parameter should be a non-empty struct ' + ...
                    'contaitning the PHY-flow information\n');
            end
        end
    end
    % Rename input variables
    conf = varargin{1};
    problem = varargin{2};
    flows = varargin{3};
    if problem.DEBUG
        fprintf('Main: Parameters extracted from runnable. Running main...\n');
    end
elseif (nargin==0)
    % No parameters were inputted to the main
    % Clear workspace
    clear; clc; close all;
    addpath('UTILITIES','-end');  % Add utilities folder at the end of search path
    addpath('code-systems','-end');  % Add system's folder at the end of search path
    addpath('code-beamforming','-end');  % Add beamforming folder at the end of search path
    addpath('code-wirelessEmulation','-end');  % Add channel folder at the end of search path
    addpath('data','-end');  % Add data folder at the end of search path
    % Load configuration
    problem = o_read_input_problem('metaproblem_test.dat');
    conf = o_read_config('config_test.dat');
    % Input parameters
    [problem,~,flows] = f_configuration(conf, problem);  % Struct with configuration parameters
%     baseFlows = flows;
    % Copy initial flows for plotting purposes (to see progression of sim)
    varargout{1} = flows;  % baseFlows: for printing purposes at the end of execution
    fprintf('Main: Parameters ovewritten in Main. Running main...\n');
else
    error('ERROR: The number of input parameters should be either 0 or 3\n' + ...
    'Please, check the parameter formatting on the description of this function.\n');
end

%% Main simulator - MAIN SECTION
Tsym = problem.Tsym;
Tslot = problem.Tslot;
refine = problem.refine;
% Represent the time (in slot ID) throughout the execution. It is the even
% in our DES
t = 1;
TXbitsTot = [];
THTot = [];
CapTot = [];
lastSelFlow = zeros(problem.nUsers,1);  % For printing purposes at the end of execution
selFlow = zeros(problem.nUsers,1);  % Inizialization
while(t<Tsym)
    if(problem.DEBUG);  fprintf('** SLOT ID: %d\n',t);  end
    % Distribute Flow accross users. Either we aggregate or disaggregate
    % overlapping flows in the current slot. Select the current flow for
    % each user
    [flows,selFlow] = f_distFlow(t,flows,Tslot,selFlow,problem.FLAGagg);
    % Compute priorities. As of now, priorities are computed as the inverse
    % of the time_to_deadline (for simplicity)
    if any(selFlow)~=0
        [combIds,combTH] = f_candidateSet(t,flows,selFlow);
        % Iterate over t
        for k = 1:length(combIds)
            % Retrieve user set to be scheduled and remove 0s from the set
            candSet = combIds(k,:);
            candSet = candSet(candSet~=0);
            candTH = combTH(k,:);
%             candTH(candTH~=0) = [];
            %% CONFIGURE BEAMFORMING (LCMV, CBF, HEURISTICS, DUMMY)
            problem.MinObjF = candTH/problem.Bw;
            problem.MaxObjF = Inf(1,length(candSet));
            if conf.MinObjFIsSNR;     problem.MinObjF = 2.^problem.MinObjF - 1;
            end
            % Evaluate SINR using BF algorithm
            if strcmp(problem.BFalgorithm,'CBF') && ~isempty(candSet)
                % Conventional Beamforming (CBF)
                [~,W,arrayHandle,~,~,candSetUpd] = f_conventionalBF(problem,conf,candSet,refine);
                [~,~,~,SNRList]  = f_BF_results(W,arrayHandle,candSetUpd,problem,conf,problem.PLOT_DEBUG);
            elseif strcmp(problem.BFalgorithm,'LCMV') && ~isempty(candSet)
                % Linearly Constrained Minimum Variance (LCMV)
                [W,~,arrayHandle,~,~,candSetUpd] = f_conventionalBF(problem,conf,candSet,refine);
                [~,~,~,SNRList]  = f_BF_results(W,arrayHandle,candSetUpd,problem,conf,problem.PLOT_DEBUG);
            elseif strcmp(problem.BFalgorithm,'HEU') && ~isempty(candSet)
                % Heuristics with LCMV as main BF
                [~,W,~,~,~,~] = CBG_solveit(problem,conf,candSet);
                [~,~,~,SNRList]  = f_BF_results(W,arrayHandle,candSet,problem,conf,problem.PLOT_DEBUG);
            elseif strcmp(problem.BFalgorithm,'HEU-LCMV') && ~isempty(candSet)
                % Heuristics with LCMV as main BF and initial ant location
                [W_init,~,arrayHandle,~,~,candSetUpd] = f_conventionalBF(problem,conf,candSet,refine);
                problem.initialW = W_init;
                [~,W,~,~,~,~] = CBG_solveit(problem,conf,candSetUpd);
                [~,~,~,SNRList]  = f_BF_results(W,arrayHandle,candSet,problem,conf,problem.PLOT_DEBUG);
            elseif strcmp(problem.BFalgorithm,'table-LCMV') && ~isempty(candSet)
                SNRList = repmat(problem.SINR_LCMV,length(candSet),1);
                candSetUpd = candSet;
            elseif strcmp(problem.BFalgorithm,'table-CBF') && ~isempty(candSet)
                SNRList = repmat(problem.SINR_CBF,length(candSet),1);
                candSetUpd = candSet;
            elseif strcmp(problem.BFalgorithm,'table-HEU') && ~isempty(candSet)
                SNRList = repmat(problem.SINR_HEU,length(candSet),1);
                candSetUpd = candSet;
            elseif strcmp(problem.BFalgorithm,'dummy') && ~isempty(candSet)
                [~,SNRList,~] = f_heuristicsDummy(problem.MinObjF,conf.MinObjFIsSNR,problem.MCSPER.snrRange);
            end
            % Update Candidate list
            [~,idx] = intersect(candSet,candSetUpd);
            %% EVALUATE PERFORMANCE - MCS, PER AND FLOW UPDATE
            % Whether to take the tentative TH or give it a another round
            threshold = 0.7;  % Represents the ratio between the demanded 
                              % and the tentative achievable TH
            % Select MCS for estimated SNR
            [MCS,PER,RATE] = f_selectMCS(candSet(idx),SNRList,problem.targetPER,problem.MCSPER,problem.mcsPolicy,problem.DEBUG);  %#ok
            if ~any(RATE./candTH(idx))<threshold
                % Compute bits that can be transmitted and map it with the 
                % bits remaining to be transmitted
                TBitsIter = zeros(1,problem.nUsers);  % Reality - bits
                THIter = zeros(1,problem.nUsers);  % Reality - throughput
                for id = candSet(idx)
                    rate = RATE(candSet(idx)==id);  % in bps
                    estTXbits = rate.*Tslot.*1e-3;  % Achievable transmit bits
                    % Bits transmitted in slot
                    TBitsIter(1,id) = min(flows(id).remaining(selFlow(id)) , estTXbits);
                    % Throughput achieved in slot
                    THIter(1,id) = min(TBitsIter(1,id)./(Tslot.*1e-3) , rate);
                end
                % Evaluate PER
                finalSet = f_PERtentative(candSet(idx),PER);
%                 finalSet = f_PER(candSet, problem, W, TXbits, MCS, problem.fullChannels, arrayHandle);
                if ~isempty(finalSet)
                    TBitsIter(setdiff(candSet,finalSet)) = 0;
                    THIter(setdiff(candSet,finalSet)) = 0;
                end
                % Append results to global final variable
                TXbitsTot = [TXbitsTot ; TBitsIter];               %#ok<AGROW>
                THTot = [THTot ; THIter];                       %#ok<AGROW>
                % Update remaining bits to be sent upon tx success
                flows = f_updateFlow(t,flows,selFlow,finalSet,THIter,candSet,Tslot,problem.DEBUG);
                lastSelFlow(selFlow~=0) = selFlow(selFlow~=0);
                % Exit the for loop - we have served in this time slot,
                % there's no way back even though some pkts didn't make it
                break;
            else
                TXbitsTot = [TXbitsTot ; zeros(1,problem.nUsers)];   %#ok<AGROW>
                THTot = [THTot ; zeros(1,problem.nUsers)];           %#ok<AGROW>
            end
        end
    else
        TXbitsTot = [TXbitsTot ; zeros(1,problem.nUsers)];   %#ok<AGROW>
        THTot = [THTot ; zeros(1,problem.nUsers)];           %#ok<AGROW>
    end
    % Increment variable event in DES
    t = t + 1;
end

% Extra output parameter
lastSlotSim = t - 1;

% Generate report
f_generateReport(flows,problem.DEBUG);

% Plotting
if problem.PLOT_DEBUG
    main_plotting(problem,TXbitsTot,THTot,baseFlows,lastSelFlow);
end


%EOF
