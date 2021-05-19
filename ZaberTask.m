function ZaberTask       
global BpodSystem

%% Setup (runs once before the first trial)
MaxTrials = 10000; % Set to some sane value, for preallocation

TrialTypes = ceil(rand(1,MaxTrials)*4);

%--- Define parameters and trial structure
S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
if isempty(fieldnames(S))  % If chosen settings file was an empty struct, populate struct with default settings
    % Define default settings here as fields of S (i.e S.InitialDelay = 3.2)
    % Note: Any parameters in S.GUI will be shown in UI edit boxes. 
    % See ParameterGUI plugin documentation to show parameters as other UI types (listboxes, checkboxes, buttons, text)
    S.GUI = struct;
    S.GUI.SoundDuration = 1;
    S.GUI.SoundFreq = 2000;
    S.GUI.PostSoundDelay = 1;
    S.GUI.MotorTime = 0.5;
    S.GUI.ResponseTime = 2;
    S.GUI.TasteTime = .15;
    S.GUI.DrinkTime = 2;
end
SF = 50000;
W = BpodWavePlayer('COM69');
W.SamplingRate = SF;
Sound = GenerateSineWave(SF, S.GUI.SoundFreq, S.GUI.SoundDuration);
W.loadWaveform(1, Sound);
LightPulseDuration = 10;
LightWaveform = ones(1, 10*SF)*5;
W.loadWaveform(2, LightWaveform);
LoadSerialMessages('WavePlayer1', {['P' 3 0], ['P' 4 1]});

%--- Initialize plots and start USB connections to any modules
BpodParameterGUI('init', S); % Initialize parameter GUI plugin

BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_MoveZaber';

%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials
    disp(['Trial# ' num2str(currentTrial) ' TrialType: ' num2str(TrialTypes(currentTrial))])
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    
    %--- Typically, a block of code here will compute variables for assembling this trial's state machine
    Thisvalve = ['Valve' num2str(TrialTypes(currentTrial))];
    
    
    %--- Assemble state machine
    sma = NewStateMachine();
    sma = SetGlobalCounter(sma, 1, 'Port1In', 5); % Arguments: (sma, CounterNumber, TargetEvent, Threshold)
    sma = AddState(sma, 'Name', 'SoundOn', ... % This example state does nothing, and ends after 0 seconds
        'Timer', S.GUI.SoundDuration,...
        'StateChangeConditions', {'Tup', 'MyDelay'},...
        'OutputActions', {'WavePlayer1', 1}); 
    sma = AddState(sma, 'Name', 'MyDelay', ... % This example state does nothing, and ends after 0 seconds
        'Timer', S.GUI.PostSoundDelay,...
        'StateChangeConditions', {'Tup', 'TriggerMovement'},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'TriggerMovement', ... % This example state does nothing, and ends after 0 seconds
        'Timer', S.GUI.MotorTime,...
        'StateChangeConditions', {'Tup', 'WaitForLicks'},...
        'OutputActions', {'SoftCode', 1});
    
    sma = AddState(sma, 'Name', 'WaitForLicks', ... % This example state does nothing, and ends after 0 seconds
        'Timer', S.GUI.ResponseTime,...
        'StateChangeConditions', {'Tup', 'RetractZaber', 'GlobalCounter1_End', 'DeliverTaste'},...
        'OutputActions', {'GlobalCounterReset', 1});
    
    sma = AddState(sma, 'Name', 'DeliverTaste', ... % This example state does nothing, and ends after 0 seconds
        'Timer', S.GUI.TasteTime,...
        'StateChangeConditions', {'Tup', 'Drinking'},...
        'OutputActions', {Thisvalve, 1});
    sma = AddState(sma, 'Name', 'Drinking', ... % This example state does nothing, and ends after 0 seconds
        'Timer', S.GUI.DrinkTime,...
        'StateChangeConditions', {'Tup', 'RetractZaber'},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'RetractZaber', ... % This example state does nothing, and ends after 0 seconds
        'Timer', 0,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'SoftCode', 2});
    sma = AddState(sma, 'Name', 'ITI', ... % This example state does nothing, and ends after 0 seconds
        'Timer', 0.5,...
        'StateChangeConditions', {'Tup', '>exit'},...
        'OutputActions', {});
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device
    RawEvents = RunStateMatrix; % Run the trial and return events
    
    %--- Package and save the trial's data, update plots
    if ~isempty(fieldnames(RawEvents)) % If you didn't stop the session manually mid-trial
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
        
        %--- Typically a block of code here will update online plots using the newly updated BpodSystem.Data
        
    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end