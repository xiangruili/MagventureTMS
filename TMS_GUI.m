function TMS_GUI(varargin)
% TMS_GUI shows and controls the Magventure TMS system. 
% 
% While TMS class works independently in code or command line, TMS_GUI is only an
% interface to show and control the stimulator through TMS class.
% 
% The control panel contains help information for each parameter and item. By
% hovering mouse on an item for a second, the help will show up.
% 
% The Coil Status panel is information only, and the coil temperature and di/dt
% will update after stimulation is applied.
% 
% The Basic Control contains Amplitude, Mode, Waveform and Current Direction. The
% Burst Parameter panel is active only for Waveform of Biphasic Burst.
% 
% Any Basic and Burst parameter change will be effective immediately at the
% stimulator, while the Train parameters will be sent only after "Set Train"
% button is pressed.
%
% The "Motor Threshold" button will start motor threshold estimation. See help
% for motorThreshold for details.
%
% From File menu, the parameters can be saved to a file, so they can be loaded
% for the future sessions. The "Load" function will send all parameters to the
% stimulator. Then once the desired amplitude is set, it is ready to fire a
% "Single pulse" or "Start Train".
% 
% From Serial menu, one can Resync status from the stimulator, in case a
% parameter is changed at the stimulator (strongly discouraged). One can also
% Disconnect the serial connection to the stimulator, and this is necessary if
% another program, e.g. E-Prime, will trigger the stimulation after all
% parameters are set.
% 
%  See also motorThreshold
 
% 250106 xiangrui.li@gmail.com
 
fh = findall(0, 'Type', 'figure', 'Tag', 'MagventureGUI');
if isempty(fh) && nargin, return; end
if isempty(fh), fh = createGUI; end
T = TMS;
hs = guidata(fh);
[~, fName] = fileparts(T.filename);
if isobject(T.port) && isvalid(T.port), fh.Name = "Magventure "+T.Model+" "+fName;
else, fh.Name = "NotConnected "+fName;
end
hs.enabled.Visible = OnOff(T.enabled);
hs.amplitude.Value = T.amplitude(1);
hs.mode.Items = T.modes.values;
hs.mode.Value = T.mode;
hs.waveform.Items = T.wvForms.values;
hs.waveform.Value = T.waveform;
hs.currentDirection.Items = T.curDirs.values;
hs.currentDirection.Value = T.currentDirection;
hs.burstPulses.Value = T.burstPulses;
hs.IPI.Value = T.IPI;
hs.IPI.Limits = T.IPIs([end 1]);
hs.CoilType.Value = T.info.CoilType;
hs.temperature.Value = T.temperature;
hs.didt.Value = T.didt(1);
hs.RepRate.Value = T.train.RepRate;
hs.RepRate.Limits = T.RATEs([1 end]);
hs.PulsesInTrain.Value = T.train.PulsesInTrain;
hs.NumberOfTrains.Value = T.train.NumberOfTrains;
hs.ITI.Value = T.train.ITI;
hs.PriorWarningSound.Value = T.train.PriorWarningSound;
hs.TotalTime.Value = T.train.TotalTime;
 
if T.train.isRunning, hs.fireTrain.Text = "Stop Train";
else, hs.fireTrain.Text = "Start Train";
end
 
set([hs.fire hs.fireTrain], "Enable", OnOff(T.enabled && T.amplitude(1)>0));
try hs.IPI.Parent.Enable = OnOff(T.waveform == "Biphasic Burst"); end %#ok
 
if T.temperature>40, hs.temperature.BackgroundColor = 'r';
else, hs.temperature.BackgroundColor = [1 1 1]*0.9;
end

%% show trace continuously
function EMG_check(~, ~)
clear RTBoxADC;
RTBoxADC('channel', 'dif', 200);
RTBoxADC;
fh = figure(3);
fh.Position = [52 472 1200 420];

%% st = matlab.lang.OnOffSwitchState(tf);
function st = OnOff(tf) % needed for some Matlab version, like 2020b
if tf, st = "on"; else, st = "off"; end

%% callback for most UI components
function guiCallback(h, ~, tag)
T = TMS;
if tag == "enable", T.enabled = ~T.enabled;
elseif ismethod(T, tag), T.(tag);
elseif isprop(T, tag), T.(tag) = h.Value;
elseif isfield(T.train, tag), T.train.(tag) = h.Value;
else, disp(h); error("Undefined callback");
end
if ~isvalid(T), fh = ancestor(h, "figure"); fh.Name = "NotConnected"; end
 
%% Create GUI
function fh = createGUI()
% Create uifigure and hide until all components are created
fh = uifigure('Visible', 'off', 'AutoResizeChildren', 'off', 'Name', '', ...
    'Position', [100 100 489 406], 'Resize', 'off', 'Tag', 'MagventureGUI');
CLN = onCleanup(@()set(fh,'Visible','on')); % Show figure after done or error
try fh.Icon = fullfile(fileparts(mfilename('fullpath')), 'CoilIcon.png'); end %#ok

cb = @(tag){@guiCallback tag};
hFile = uimenu(fh, 'Text', '&File');
uimenu(hFile, 'Label', '&Load', 'MenuSelectedFcn', cb("load"), ...
    'Tooltip', 'Load and set parameters from .mat or .CG3 file to stimulator');
uimenu(hFile, 'Label', '&Save', 'MenuSelectedFcn', cb("save"), ...
    'Tooltip', 'Save parameters for future to load from');
hSeri = uimenu(fh, 'Text', '&Serial');
uimenu(hSeri, 'Label', '&Resync', 'MenuSelectedFcn', cb("resync"), ...
    'Tooltip', 'Update parameters from stimulator');
uimenu(hSeri, 'Label', '&Disconnect', 'MenuSelectedFcn', cb("disconnect"), ...
    'Tooltip', 'Disconnect to allow other app to connect');
hHelp = uimenu(fh, 'Text', '&Help');
uimenu(hHelp, 'Text', 'Help about TMS class', 'MenuSelectedFcn', 'doc TMS');
uimenu(hHelp, 'Text', 'Help about TMS_GUI', 'MenuSelectedFcn', 'doc TMS_GUI');
 
uilabel(fh, 'Text', 'Disabled', 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', 'r', 'Position', [31 354 62 32]);
hs.enabled = uilabel(fh, 'Text', 'Enabled', 'FontWeight', 'bold', 'Visible', 'off', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', 'g', 'Position', [31 354 62 32]);
 
h = uibutton(fh, 'push');
h.Text = char(11096); % char(0x23FB) for power button
h.FontSize = 14;
h.Position = [94 354 32 32];
h.ButtonPushedFcn = cb("enable");
h.Tooltip = {'Push to enable/disable stimulation'};
 
hs.fire = uibutton(fh, 'push', 'ButtonPushedFcn', cb("firePulse"), ...
    'FontWeight', 'bold', 'Text', 'Single Pulse', ...
    'Tooltip', {'Fire a pulse or burst'}, 'Position', [158 354 98 32]);
 
uibutton(fh, 'push', 'ButtonPushedFcn', @(~,~)motorThreshold, 'Text', 'Motor Threshold', ...
    'Tooltip', {'Start motor threshold estimate'}, 'Position', [158 310 98 32]);

uibutton(fh, 'push', 'ButtonPushedFcn', @EMG_check, 'Text', 'EMG Check', ...
    'Tooltip', {'Show continuous EMG trace'}, 'Position', [31 310 88 32]);

% Coil panel
hPanel = uipanel(fh, 'TitlePosition', 'centertop', 'Title', 'Coil Status', ...
    'FontWeight', 'bold', 'Position', [296 267 171 122]);
 
% coil type
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [3 69 77 22];
h.Text = 'Type/Number';
hs.CoilType = uieditfield(hPanel, 'text', 'Position', [85 69 77 22], ...
    'Editable', 'off', 'BackgroundColor', [0.9 0.9 0.9], ...
    'Tooltip', {'Connected coil type or number'});
 
% temperature
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [4 38 121 22];
h.Text = 'Temperature (°C)';
h.Tooltip = {'Coil temperature in Celsius'};
hs.temperature = uieditfield(hPanel, 'numeric', 'Editable', 'off', ...
    'BackgroundColor', [0.9 0.9 0.9], 'Tooltip', h.Tooltip, 'Position', [131 38 31 22]);
 
% didt
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [12 10 113 22];
h.Text = 'Realized di/dt (A/µs)';
h.Tooltip = {'Coil current gradient'};
hs.didt = uieditfield(hPanel, 'numeric', 'Editable','off', 'Tooltip',  h.Tooltip, ...
    'BackgroundColor', [0.9 0.9 0.9], 'Position', [131 10 31 22]);
 
% Basic panel
hPanel = uipanel(fh);
hPanel.TitlePosition = 'centertop';
hPanel.Title = 'Basic Control';
hPanel.FontWeight = 'bold';
hPanel.Position = [31 135 230 152];
 
% amplitude
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [78 95 80 22];
h.Text = 'Amplitude (%)';
h.Tooltip = {'Stimulation amplitude in percent'};
hs.amplitude = uispinner(hPanel, 'Limits', [0 100], 'RoundFractionalValues', 'on', ...
    'ValueChangedFcn', cb("amplitude"), 'Tooltip', h.Tooltip, 'Position',  [167 95 53 22]);
 
% mode
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [47 67 80 22];
h.Text = 'Mode';
h.Tooltip = {'Stimulator mode value other than "Standard" only available for MagOption'};
hs.mode = uidropdown(hPanel, 'Position', [136 67 84 22],  'Items', "Standard", ...
    'Value', 'Standard', 'BackgroundColor',  [1 1 1], 'ValueChangedFcn', cb("mode"));

% Waveform
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [44 39 59 22];
h.Text = 'Waveform';
hs.waveform = uidropdown(hPanel, 'Position', [110 39 110 22], 'Items', "Biphasic", ...
    'Value', 'Biphasic', 'BackgroundColor',  [1 1 1], 'ValueChangedFcn', cb("waveform"));

% Current Direction
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [36 10 96 22];
h.Text = 'Current Direction';
hs.currentDirection = uidropdown(hPanel, 'Items', ["Normal" "Reverse"], ...
    'Value', 'Normal', 'Position',  [140 10 80 22], 'BackgroundColor',  [1 1 1], ...
    'ValueChangedFcn', cb("currentDirection"));
 
% Burst Panel
hPanel = uipanel(fh);
hPanel.TitlePosition = 'centertop';
hPanel.Title = 'Burst Parameters';
hPanel.FontWeight = 'bold';
hPanel.Position = [31 22 230 93];
hPanel.Tooltip = {'Only active with Waveform of "Biphasic Burst"'};
 
% burstPulses
h = uilabel(hPanel, 'HorizontalAlignment', 'right', 'Position', [102 42 72 22], ...
    'Text', 'Burst Pulses', 'Tooltip', {'Number of pulses in a burst'});
hs.burstPulses = uispinner(hPanel, 'Limits', [2 5], 'RoundFractionalValues', 'on', ...
    'ValueChangedFcn', cb("burstPulses"), 'Tooltip', h.Tooltip, 'Position', [181 42 42 22]);
 
% IPI
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [54 11 132 22];
h.Text = 'Inter Pulse Interval (ms)';
h.Tooltip = {'Duration between the beginning of the first pulse to the beginning of the second pulse'};
hs.IPI = uieditfield(hPanel, 'numeric', 'Limits', [0.5 100], 'ValueChangedFcn', cb("IPI"), ...
    'Tooltip', h.Tooltip, 'Position', [192 11 31 22], 'Value', 10);
 
% Train Panel
trainPanel = uipanel(fh);
trainPanel.TitlePosition = 'centertop';
trainPanel.Title = 'Train Control';
trainPanel.FontWeight = 'bold';
trainPanel.Tooltip = {'Train parameters only sent to stimulator after "Set Train"'};
trainPanel.Position = [296 22 171 231];
 
% RepRate
h = uilabel(trainPanel);
h.HorizontalAlignment = 'right';
h.Tooltip = {'Number of pulses per second'};
h.Position = [28 183 90 22];
h.Text = 'Rep. Rate (pps)';
hs.RepRate = uieditfield(trainPanel, 'numeric');
hs.RepRate.Limits = [0.1 100];
hs.RepRate.Tooltip = h.Tooltip;
hs.RepRate.Position = [125 183 36 22];
hs.RepRate.Value = 1;
hs.RepRate.ValueDisplayFormat = '%.4g';
hs.RepRate.ValueChangedFcn = cb("RepRate");
 
% PulsesInTrain
h = uilabel(trainPanel);
h.HorizontalAlignment = 'right';
h.Tooltip = {'Number of pulses or bursts in each train'};
h.Position = [34 155 84 22];
h.Text = 'Pulses in Train';
hs.PulsesInTrain = uieditfield(trainPanel, 'numeric');
hs.PulsesInTrain.Limits = [1 2000];
hs.PulsesInTrain.RoundFractionalValues = 'on';
hs.PulsesInTrain.Tooltip = h.Tooltip;
hs.PulsesInTrain.Position = [125 155 36 22];
hs.PulsesInTrain.Value = 5;
hs.PulsesInTrain.ValueChangedFcn = cb("PulsesInTrain");
 
% NumberOfTrains
h = uilabel(trainPanel);
h.HorizontalAlignment = 'right';
h.Position = [21 127 97 22];
h.Text = 'Number of Trains';
h.Tooltip = {'Total amount of trains arriving in one sequence'};
hs.NumberOfTrains = uieditfield(trainPanel, 'numeric');
hs.NumberOfTrains.Limits = [1 500];
hs.NumberOfTrains.RoundFractionalValues = 'on';
hs.NumberOfTrains.Tooltip = h.Tooltip;
hs.NumberOfTrains.Position = [125 127 36 22];
hs.NumberOfTrains.Value = 3;
hs.NumberOfTrains.ValueChangedFcn = cb("NumberOfTrains");
 
% ITI
h = uilabel(trainPanel);
h.HorizontalAlignment = 'right';
h.Position = [1 99 119 22];
h.Text = 'Inter Train Interval (s)';
h.Tooltip = {'The time interval between two trains described as'; ...
    'the time period between the last pulse in the first'; ...
    'train to the first pulse in the next train'};
hs.ITI = uieditfield(trainPanel, 'numeric');
hs.ITI.Limits = [0.1 300];
hs.ITI.Tooltip = h.Tooltip;
hs.ITI.Position = [125 99 36 22];
hs.ITI.Value = 1;
hs.ITI.ValueDisplayFormat = '%.4g';
hs.ITI.ValueChangedFcn = cb("ITI");
 
% PriorWarningSound
h = uilabel(trainPanel);
h.HorizontalAlignment = 'right';
h.Position = [2 71 138 22];
h.Text = 'Prior Warning Sound';
h.Tooltip =  {'When on, a beep will sound 2 seconds before each train'};
hs.PriorWarningSound = uicheckbox(trainPanel);
hs.PriorWarningSound.Tooltip = h.Tooltip;
hs.PriorWarningSound.Text = '';
hs.PriorWarningSound.Position = [146 71 22 22];
hs.PriorWarningSound.Value = true;
hs.PriorWarningSound.ValueChangedFcn = cb("PriorWarningSound");
 
% TotalTime
h = uilabel(trainPanel);
h.HorizontalAlignment = 'right';
h.Position = [15 43 80 22];
h.Text = 'Total Time';
h.Tooltip = {'Total time to run the sequence, based on above parameters'};
hs.TotalTime = uieditfield(trainPanel, 'text');
hs.TotalTime.Editable = 'off';
hs.TotalTime.BackgroundColor = [0.9 0.9 0.9];
hs.TotalTime.Tooltip = h.Tooltip;
hs.TotalTime.Position = [102 43 56 22];
hs.TotalTime.Value = '00:17';
hs.TotalTime.HorizontalAlignment = 'right';
 
hs.fireTrain = uibutton(trainPanel, 'push');
hs.fireTrain.ButtonPushedFcn = cb("fireTrain");
hs.fireTrain.Tooltip = {'Start / Stop train sequence'};
hs.fireTrain.Position = [92 10 64 22];
hs.fireTrain.Text = 'Start Train';
 
hs.setTrain = uibutton(trainPanel, 'push');
hs.setTrain.ButtonPushedFcn = cb("setTrain");
hs.setTrain.Tooltip = {'Send train parameters to stimulator '};
hs.setTrain.Position = [12 10 64 22];
hs.setTrain.Text = 'Set Train';

guidata(fh, hs);
%%
