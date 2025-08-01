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
hs.mode.Items = T.MODEs.values;
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
hs.trainTime.Value = T.trainTime;
set([hs.fire hs.fireTrain], "Enable", T.enabled && T.amplitude(1)>0);
 
if T.trainRunning, c = 'Stop Train'; else, c = 'Start Train'; end
hs.fireTrain.Text = c;
 
if T.waveform=="Biphasic Burst", st = 'on'; else, st = 'off'; end
hs.IPI.Parent.Enable = st;
 
if T.temperature>40, clr = 'r'; else, clr = [1 1 1]*0.9; end
hs.temperature.BackgroundColor = clr;

%% callback for most UI components
function guiCallback(h, ~, tag)
T = TMS;
if tag == "enable", T.enabled = ~T.enabled;
elseif tag == "disconnect"; T.disconnect; set(ancestor(h,'figure'), 'Name', 'NotConnected');
elseif ismethod(T, tag), T.(tag);
elseif isprop(T, tag), T.(tag) = h.Value;
elseif isfield(T.train, tag), T.train.(tag) = h.Value;
else, disp(h); error("Undefined callback");
end

%% add label to left of a uicontrol, give it same tooltip
function lbl = addLabel(h, label)
lbl = uilabel(h.Parent, 'Text', label, 'Tooltip', h.Tooltip, 'Horizontal', 'Right');
pos = h.Position;
lbl.Position = [1 pos(2) pos(1)-6 pos(4)];

%% Create GUI
function fh = createGUI()
% Create uifigure and hide until all components are created
fh = uifigure('Visible', 'off', 'AutoResizeChildren', 'off', 'Name', '', ...
    'Position', [100 100 490 406], 'Resize', 'off', 'Tag', 'MagventureGUI');
try fh.Icon =  [fileparts(mfilename) '/TIcon.png']; catch, end

CLN = onCleanup(@()set(fh,'Visible','on')); % Show figure after done or error

cb = @(tag){@guiCallback tag};
hFile = uimenu(fh, 'Text', '&File');
uimenu(hFile, 'Label', '&Load', 'MenuSelectedFcn', cb("load"), ...
    'Tooltip', 'Load and set parameters from .mat/.json/.CG3 file to stimulator');
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
 
% char(0x23FB) for power button
h = uibutton(fh, 'push', 'Text', char(11096), 'FontSize', 14, 'Position', [94 362 32 32], ...
    'ButtonPushedFcn', cb("enable"), 'Tooltip', 'Push to enable/disable stimulation');
 
hs.fire = uibutton(fh, 'push', 'ButtonPushedFcn', cb("firePulse"), 'FontWeight', 'bold', ...
    'Text', 'Trig', 'Tooltip', {'Trigger a pulse or burst'}, 'Position', [136 362 98 32]);
 
uibutton(fh, 'push', 'ButtonPushedFcn', @(~,~)motorThreshold, 'Text', 'Motor Threshold', ...
    'Tooltip', {'Start motor threshold estimate'}, 'Position', [136 322 98 32]);

uibutton(fh, 'push', 'ButtonPushedFcn', @(~,~)RTBoxADCd, 'Text', 'EMG Check', ...
    'Tooltip', {'Show continuous EMG trace'}, 'Position', [31 322 88 32]);

% Basic Control
hPanel = uipanel(fh, 'Title', 'Basic Control', 'FontWeight', 'bold', 'Position', [31 130 206 180]);
 
hs.amplitude = uispinner(hPanel, 'Limits', [0 100], 'RoundFractionalValues', 'on', ...
    'ValueChangedFcn', cb("amplitude"), 'Position',  [143 130 53 22], ...
    'Tooltip', 'Stimulation amplitude in percent');
addLabel(hs.amplitude, 'Amplitude (%)');

h.Tooltip = {'Stimulator mode other than "Standard" only available for MagOption'};
hs.mode = uidropdown(hPanel, 'Position', [112 100 84 22],  'Items', "Standard", ...
    'Value', 'Standard', 'BackgroundColor',  [1 1 1], 'ValueChangedFcn', cb("mode"), ...
    'Tooltip', 'Stimulator mode other than "Standard" only available for MagOption');
addLabel(hs.mode, 'Mode');

hs.currentDirection = uidropdown(hPanel, 'Items', ["Normal" "Reverse"], ...
    'Value', 'Normal', 'Position',  [116 70 80 22], 'BackgroundColor',  [1 1 1], ...
    'ValueChangedFcn', cb("currentDirection"));
addLabel(hs.currentDirection, 'Current Direction');

hs.waveform = uidropdown(hPanel, 'Position', [86 40 110 22], 'Items', "Biphasic", ...
    'Value', 'Biphasic', 'BackgroundColor',  [1 1 1], 'ValueChangedFcn', cb("waveform"));
addLabel(hs.waveform, 'Waveform');

hs.BARatio = uieditfield(hPanel, 'numeric', 'Position', [160 10 36 22], ...
    'Limits', [0.2 5], 'Value', 1, 'ValueChangedFcn', cb("BARatio"), ...
    'Tooltip', 'Amplitude ratio of Pulse B over Pulse A for Twin mode');
hs.BARatioL = addLabel(hs.BARatio, 'Pulse B/A Ratio');

% Burst Parameters
hPanel = uipanel(fh, 'Title', 'Burst Parameters', 'FontWeight', 'bold', 'Position', [31 22 206 90], ...
    'Tooltip', 'Only active with Waveform of "Biphasic Burst"');
 
hs.burstPulses = uispinner(hPanel, 'Limits', [2 5], 'RoundFractionalValues', 'on', ...
    'ValueChangedFcn', cb("burstPulses"), 'Position', [157 40 42 22], ...
    'Tooltip', 'Number of pulses in a burst');
addLabel(hs.burstPulses, 'Burst Pulses');
 
hs.IPI = uieditfield(hPanel, 'numeric', 'ValueChangedFcn', cb("IPI"), ...
    'Position', [163 10 34 22], 'Value', 10, ...
    'Tooltip', 'Duration between the beginning of the first pulse to the beginning of the second pulse');
addLabel(hs.IPI, 'Inter Pulse Interval (ms)');

% Coil Status
hPanel = uipanel(fh, 'Title', 'Coil Status', 'FontWeight', 'bold', 'Position', [256 270 206 122]);
 
hs.CoilType = uieditfield(hPanel, 'text', 'Position', [94 70 100 22], 'Editable', 'off', ...
    'BackgroundColor', [1 1 1]*0.9, 'HorizontalAlignment', 'right', ...
    'Tooltip', {'Connected coil type or number'});
addLabel(hs.CoilType, 'Type/Number');
 
hs.temperature = uieditfield(hPanel, 'numeric', 'Editable', 'off', 'Position', [163 40 31 22], ...
    'BackgroundColor', [1 1 1]*0.9, 'Tooltip', 'Coil temperature in Celsius');
addLabel(hs.temperature, 'Temperature (°C)');
 
hs.didt = uieditfield(hPanel, 'text', 'Editable','off', 'Tooltip',  'Coil current gradient', ...
    'BackgroundColor', [1 1 1]*0.9, 'Position', [138 10 56 22], 'HorizontalAlignment', 'right');
addLabel(hs.didt, 'Realized di/dt (A/µs)');
 
% Train Control
hPanel = uipanel(fh, 'Title', 'Train Control', 'FontWeight', 'bold', 'Position', [256 22 206 234]);
 
hs.RepRate = uieditfield(hPanel, 'numeric', 'Value', 1, 'Position', [158 183 36 22], ...
    'ValueChangedFcn', cb("RepRate"), 'Tooltip', 'Number of pulses per second');
addLabel(hs.RepRate, 'Rep. Rate (pps)');
 
hs.PulsesInTrain = uieditfield(hPanel, 'numeric', 'Limits', [1 2000], ...
    'RoundFractionalValues', 'on', 'Position', [158 155 36 22], 'Value', 5, ...
    'ValueChangedFcn', cb("PulsesInTrain"), ...
    'Tooltip', 'Number of pulses or bursts in each train');
addLabel(hs.PulsesInTrain, 'Pulses in Train');
 
hs.NumberOfTrains = uieditfield(hPanel, 'numeric', 'Limits', [1 500], 'Value', 3, ...
    'RoundFractionalValues', 'on', 'Position', [158 127 36 22], 'ValueChangedFcn', cb("NumberOfTrains"), ...
    'Tooltip', 'Total amount of trains arriving in one sequence');
addLabel(hs.NumberOfTrains, 'Number of Trains');
 
hs.ITI = uieditfield(hPanel, 'numeric', 'Limits', [0.1 300], 'Value', 1, ...
    'Position', [158 99 36 22], 'ValueChangedFcn', cb("ITI"), ...
    'Tooltip', {'The time interval between two trains described as'; ...
        'the time period between the last pulse in the first'; ...
        'train to the first pulse in the next train'});
addLabel(hs.ITI, 'Inter Train Interval (s)');

hs.PriorWarningSound = uicheckbox(hPanel, 'Text', '', 'Position', [176 71 22 22], ...
    'Value', true, 'ValueChangedFcn', cb("PriorWarningSound"), ...
    'Tooltip', 'When on, a beep will sound 2 seconds before each train');
addLabel(hs.PriorWarningSound, 'Prior Warning Sound');
 
hs.trainTime = uieditfield(hPanel, 'text', 'Editable', 'off', 'BackgroundColor', [1 1 1]*0.9, ...
    'Value', '00:14', 'Position', [138 43 56 22], 'HorizontalAlignment', 'right', ...
    'Tooltip','Total time to run the sequence, based on above parameters');
addLabel(hs.trainTime, 'Total Time');
 
hs.fireTrain = uibutton(hPanel, 'push', 'ButtonPushedFcn', cb("fireTrain"), ...
    'Tooltip', 'Start / Stop train sequence', 'Position', [51 10 92 22], 'Text', 'Start Train');

guidata(fh, hs);
%%
