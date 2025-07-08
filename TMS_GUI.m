function TMS_GUI(varargin)
% TMS_GUI shows and controls the Magventure TMS system. 
% 
% While TMS class works independently in script or command line, TMS_GUI is only
% an interface to show and control the stimulator through TMS class.
% 
% The control panel contains help information for each parameter and item. By
% hovering mouse onto an item for a second, the help will show up.
% 
% The Coil Status panel is information only, and the coil temperature and di/dt
% will update after stimulation is applied.
% 
% The Basic Control panel contains common basic parameters. The Burst Parameter
% panel is active only for Waveform of Biphasic Burst. The Train Control panel
% contains the parameters for train stimulation.
% 
% All parameter change will be effective immediately at the stimulator.
%
% The "Motor Threshold" button will start motor threshold estimation. See help
% for motorThreshold/m for details.
%
% From File menu, the parameters can be saved to a file, so they can be loaded
% for the future sessions. The "Load" function will send all parameters to the
% stimulator. Then once the desired amplitude is set, it is ready to "Trig" a
% pulse/burst or "Start Train". This is the easy and safe way to set up all
% parameters.
% 
% From Serial menu, one can Resync status from the stimulator, in case any
% parameter is changed at the stimulator (strongly discouraged). One can also
% Disconnect the serial connection to the stimulator, as this is necessary if
% another program, e.g. E-Prime, will trigger the stimulation.
% 
%  See also motorThreshold
 
% 250106 started by xiangrui.li@gmail.com
 
fh = findall(0, 'Type', 'figure', 'Tag', 'MagventureGUI');
if isempty(fh) && nargin, return; end
if isempty(fh), fh = createGUI; end
T = TMS;
hs = guidata(fh);
[~, fName] = fileparts(T.filename);
if isobject(T.port) && isvalid(T.port), fh.Name = "Magventure "+T.Model+" "+fName;
else, fh.Name = "NotConnected "+fName;
end
hs.enabled.Visible = T.enabled;
hs.amplitude.Value = T.amplitude(1);
hs.mode.Items = T.modes.values;
hs.mode.Value = T.mode;
hs.waveform.Items = T.wvForms.values;
hs.waveform.Value = T.waveform;
hs.currentDirection.Items = T.curDirs.values;
hs.currentDirection.Value = T.currentDirection;
hs.burstPulses.Value = T.burstPulses;
hs.BARatio.Value = T.BARatio;
set([hs.BARatio hs.BARatioL], 'Enable', T.mode=="Twin");
hs.IPI.Value = T.IPI;
hs.IPI.Limits = T.IPIs([end 1]);
hs.CoilType.Value = T.info.CoilType;
hs.temperature.Value = T.temperature;
hs.didt.Value = sprintf('%i  %i', T.didt);
hs.RepRate.Value = T.train.RepRate;
hs.RepRate.Limits = T.RATEs([1 end]);
hs.PulsesInTrain.Value = T.train.PulsesInTrain;
hs.NumberOfTrains.Value = T.train.NumberOfTrains;
hs.ITI.Value = T.train.ITI;
hs.PriorWarningSound.Value = T.train.PriorWarningSound;
hs.trainTime.Value = T.info.trainTime;
set([hs.fire hs.fireTrain], "Enable", T.enabled && T.amplitude(1)>0);
 
if T.info.trainRunning, c = 'Stop Train'; else, c = 'Start Train'; end
hs.fireTrain.Text = c;
 
if T.waveform=="Biphasic Burst", st = 'on'; else, st = 'off'; end
hs.IPI.Parent.Enable = st;
 
if T.temperature>40, clr = 'r'; else, clr = [1 1 1]*0.9; end
hs.temperature.BackgroundColor = clr;

%% show trace continuously
function EMG_check(~, ~)
clear RTBoxADC;
RTBoxADC('channel', 'dif', 200);
RTBoxADC;
fh = figure(3);
fh.Position = [52 472 1200 420];

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
try fh.Icon =  [fileparts(mfilename) '/TIcon.png']; catch, end

CLN = onCleanup(@()set(fh,'Visible','on')); % Show figure after done or error

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
    'HorizontalAlignment', 'center', 'BackgroundColor', 'r', 'Position', [31 362 62 32]);
hs.enabled = uilabel(fh, 'Text', 'Enabled', 'FontWeight', 'bold', 'Visible', 'off', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', 'g', 'Position', [31 362 62 32]);
 
h = uibutton(fh, 'push');
h.Text = char(11096); % char(0x23FB) for power button
h.FontSize = 14;
h.Position = [94 362 32 32];
h.ButtonPushedFcn = cb("enable");
h.Tooltip = {'Push to enable/disable stimulation'};
 
hs.fire = uibutton(fh, 'push', 'ButtonPushedFcn', cb("firePulse"), ...
    'FontWeight', 'bold', 'Text', 'Trig', ...
    'Tooltip', {'Trigger a pulse or burst'}, 'Position', [158 362 98 32]);
 
uibutton(fh, 'push', 'ButtonPushedFcn', @(~,~)motorThreshold, 'Text', 'Motor Threshold', ...
    'Tooltip', {'Start motor threshold estimate'}, 'Position', [158 322 98 32]);

uibutton(fh, 'push', 'ButtonPushedFcn', @EMG_check, 'Text', 'EMG Check', ...
    'Tooltip', {'Show continuous EMG trace'}, 'Position', [31 322 88 32]);

% Coil panel
hPanel = uipanel(fh, 'TitlePosition', 'centertop', 'Title', 'Coil Status', ...
    'FontWeight', 'bold', 'Position', [280 267 182 122]);
 
% coil type
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [13 70 77 22];
h.Text = 'Type/Number';
hs.CoilType = uieditfield(hPanel, 'text', 'Position', [95 70 77 22], ...
    'Editable', 'off', 'BackgroundColor', [0.9 0.9 0.9], ...
    'Tooltip', {'Connected coil type or number'});
 
% temperature
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [14 40 121 22];
h.Text = 'Temperature (°C)';
h.Tooltip = {'Coil temperature in Celsius'};
hs.temperature = uieditfield(hPanel, 'numeric', 'Editable', 'off', ...
    'BackgroundColor', [0.9 0.9 0.9], 'Tooltip', h.Tooltip, 'Position', [141 40 31 22]);
 
% didt
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [2 10 112 22];
h.Text = 'Realized di/dt (A/µs)';
h.Tooltip = {'Coil current gradient'};
hs.didt = uieditfield(hPanel, 'text', 'Editable','off', 'Tooltip',  h.Tooltip, ...
    'BackgroundColor', [0.9 0.9 0.9], 'Position', [116 10 56 22], 'HorizontalAlignment', 'right');
 
% Basic panel
hPanel = uipanel(fh);
hPanel.TitlePosition = 'centertop';
hPanel.Title = 'Basic Control';
hPanel.FontWeight = 'bold';
hPanel.Position = [31 130 230 178];
 
% amplitude
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [78 125 80 22];
h.Text = 'Amplitude (%)';
h.Tooltip = {'Stimulation amplitude in percent'};
hs.amplitude = uispinner(hPanel, 'Limits', [0 100], 'RoundFractionalValues', 'on', ...
    'ValueChangedFcn', cb("amplitude"), 'Tooltip', h.Tooltip, 'Position',  [167 125 53 22]);
 
% mode
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [47 97 80 22];
h.Text = 'Mode';
h.Tooltip = {'Stimulator mode value other than "Standard" only available for MagOption'};
hs.mode = uidropdown(hPanel, 'Position', [136 97 84 22],  'Items', "Standard", ...
    'Value', 'Standard', 'BackgroundColor',  [1 1 1], 'ValueChangedFcn', cb("mode"));

% Current Direction
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [36 69 96 22];
h.Text = 'Current Direction';
hs.currentDirection = uidropdown(hPanel, 'Items', ["Normal" "Reverse"], ...
    'Value', 'Normal', 'Position',  [140 69 80 22], 'BackgroundColor',  [1 1 1], ...
    'ValueChangedFcn', cb("currentDirection"));

% Waveform
h = uilabel(hPanel);
h.HorizontalAlignment = 'right';
h.Position = [44 40 59 22];
h.Text = 'Waveform';
hs.waveform = uidropdown(hPanel, 'Position', [110 40 110 22], 'Items', "Biphasic", ...
    'Value', 'Biphasic', 'BackgroundColor',  [1 1 1], 'ValueChangedFcn', cb("waveform"));

% BARatio
hs.BARatioL = uilabel(hPanel);
hs.BARatioL.Position = [96 10 86 22];
hs.BARatioL.Text = 'Pulse B/A Ratio';
hs.BARatioL.Tooltip = 'Amplitude ratio of Pulse B over Pulse A for Twin mode';
hs.BARatio = uieditfield(hPanel, 'numeric');
hs.BARatio.Limits = [0.2 5];
hs.BARatio.Tooltip = hs.BARatioL.Tooltip;
hs.BARatio.Position = [184 10 36 22];
hs.BARatio.Value = 1;
hs.BARatio.ValueDisplayFormat = '%.2g';
hs.BARatio.ValueChangedFcn = cb("BARatio");

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
trainPanel.Position = [280 22 182 231];
 
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
hs.PriorWarningSound = uicheckbox(trainPanel, 'Tooltip', h.Tooltip, 'Text', '', ...
    'Position', [146 71 22 22], 'Value', true, 'ValueChangedFcn', cb("PriorWarningSound"));
 
% trainTime
h = uilabel(trainPanel);
h.HorizontalAlignment = 'right';
h.Position = [15 43 80 22];
h.Text = 'Total Time';
h.Tooltip = {'Total time to run the sequence, based on above parameters'};
hs.trainTime = uieditfield(trainPanel, 'text', 'Editable', 'off', ...
    'BackgroundColor', [0.9 0.9 0.9], 'Tooltip', h.Tooltip, 'Value', '00:14', ...
    'Position', [102 43 56 22], 'HorizontalAlignment', 'right');
 
hs.fireTrain = uibutton(trainPanel, 'push');
hs.fireTrain.ButtonPushedFcn = cb("fireTrain");
hs.fireTrain.Tooltip = {'Start / Stop train sequence'};
hs.fireTrain.Position = [51 10 80 22];
hs.fireTrain.Text = 'Start Train';

guidata(fh, hs);
%%
