classdef TMS < handle
% TMS controls Magventure TMS system (tested under X100).
%
% Usage syntax:
%  T = TMS; % Connect to TMS and return handle for later use
%  T.load('myParams.mat'); % load pre-saved stimulation parameters
%  T.enable; % Enable it like pressing the button at stimulator
%  T.setAmplitude(40); % set amplitude to 40%
%  T.firePulse; % send a single pulse stimulation
%
%  T.setWaveform("Biphasic Burst"); % set burst mode
%  T.setBurstPulses(3); % set number of pulses in a burst, 2 to 5
%  T.setIPI(20); % set inter pulse interval in ms
%  T.setTrain("RepRate", 50, 'PulsesInTrain', 3, 'NumberOfTrains', 20, 'ITI', 8)
%  T.fireTrain;	% Start train/burst stimulation
% 
%  See also motorThreshold as an example

% 241228 xiangrui.li@gmail.com, first working version

  properties (Hidden, Constant)
    models = dict(["R30" "X100" "R30+Option" "X100+Option" "R30+Option+Mono" "MST"])
    TCs = dict(["Sequence" "External Trig" "Ext Seq. Start" "Ext Seq. Cont"])
    pages = dict(["Main" "Timing" "Trig" "Config" "Download" "Protocol" "MEP" "Service" ...
        "Treatment" "Treat Select" "Service2" "Calculator"], [1:4 6:8 13 15:17 19])
  end
  properties (Hidden, SetAccess=private, Transient)
    port(1,1)
    raw9(1,9) uint8 % store parameters for setParam9()
    modes = dict(["Standard" "Power" "Twin" "Dual"])
    curDirs = dict(["Normal" "Reverse"])
    wvForms = dict(["Monophasic" "Biphasic" "Halfsine" "Biphasic Burst"])
    IPIs = flip([0.5:0.1:10 10.5:0.5:20 21:100])
    RATEs = [0.1:0.1:1 2:100]
  end
  properties (SetObservable, AbortSet, SetAccess=private)
    % Stimulator model
    Model(1,1) = ""

    % Stimulator mode: "Standard" "Power" "Twin" or "Dual", depending on model
    mode(1,1) = "Standard"
    
    % Wave form: "Monophasic" "Biphasic" "HalfSine" or "Biphasic Burst"
    waveform(1,1) = "Biphasic"    
  end
  properties (SetAccess=private)
    % Current direction: "Normal" or "Reverse" if avaiable
    currentDirection(1,1) = "Normal"
    
    % Number of pulses in a burst: 2 to 5
    burstPulses(1,1) = 2
    
    % Pulse B/A Ratio. Will be adjusted to supported value
    BARatio(1,1) = 1    

    % Inter pulse interval in ms. Will be adjusted to supported value
    IPI(1,1) = 10
        
    % Indicate if stimulator is enabled
    enabled(1,1) logical
    
    % Stimulation amplitude in percent
    amplitude(1,2)
    
    % Coil temperature as shown on the stimulator
    temperature(1,1)
    
    % Realized di/dt in A/µs, as shown on the device
    didt(1,2)
    
    % Timing control options
    TimingControl(1,1) = "Sequence"    

    % DelayInputTrig, DelayOutputTrig, ChargeDelay in ms
    delays(1,3)

    % MEP related parameters
    MEP(1,1) struct

    % File name from which the parameters are loaded
    filename = "";

    % Some info about the stimulator,like SerialNo, Connected coil, etc.
    info = struct("CoilType", "")

    % TMS.m version
    version = "2025.05.30"
  end
  properties
    % Parameters related to train: settable directly
    train = struct( ...
      'RepRate', 1, ... % Number of pulses per second in each train
      'PulsesInTrain', 5, ... % Number of pulses or bursts in each train
      'NumberOfTrains', 2, ... % Number of Trains in the sequence
      'ITI', 1, ... % Inter Train Interval in seconds
      'PriorWarningSound', false, ... % sound warning before each train?
      'RampUp', 1, ... % A factor 0.7-1.0 setting the level for the first Train
      'RampUpTrains', 10, ... % Number of trains during which the Ramp up function is active
      'isRunning', false, ... % Indicate if train sequence is running
      'TotalTime', "00:09") % Total time to run the sequence, based on train parameters
  end

  methods
    function self = TMS() % constructor
      % T = TMS; % Connect to Magventure stimulator
      persistent OBJ CLN % store it for only single instance
      if ~isempty(OBJ) && isvalid(OBJ), self = OBJ; return; end
      warning("off", "serialport:serialport:ReadWarning");
      for port = flip(serialportlist("available"))
        p = serialport(port, 38400, "Timeout", 0.3);
        p.write([254 1 0 0 255], 'uint8');
        pause(0.1);
        if p.NumBytesAvailable<13, delete(p); continue; else, break; end
      end
      addlistener(self, {'Model' 'mode' 'waveform'}, 'PostSet', @(~,~)setScales(self));
      OBJ = self;
      if ~exist('p','var') || ~isvalid(p)
          fprintf(2, " Failed to connect to TMS machine.\n"); return;
      end
      configureCallback(p, "byte", 8, @(~,~)decodeBytes(self));
      self.port = p;
      CLN = onCleanup(@()delete(p));
      self.resync;
    end

    function firePulse(self)
      % Start single pulse or single burst stimulation
      if ~self.enabled, error("Need to enalbe"); end
      self.serialCmd([3 1]);
    end

    function fireTrain(self)
      % Start train stimulation
      if ~self.enabled, error("Need to enalbe"); end
      self.setPage("Timing");
      self.serialCmd(4);
    end

    function enable(self, toEnable)
      % T.enable; % enable TMS so it's ready to fire
      if nargin<2, toEnable = 1; end
      self.serialCmd([2 toEnable]);
    end

    function disable(self)
      % T.disable; % disable TMS to avoid accidental stimulation
      self.enable(0);
    end

    function setAmplitude(self, amp)
      % T.setAmplitude(40); % set amplitude in percent after T.enable()
      self.serialCmd([1 uint8(amp)]);
    end

    function setTrain(self, varargin)
      % T.setTrain("RepRate", 50, 'PulsesInTrain', 2, 'NumberOfTrains', 20, 'ITI', 8, 'PriorWarningSound', true);
      % Input: parameters in a struct or in key/value pairs:
      %  RepRate: number of pulses per second
      %  PulsesInTrain: number of pulses in each train
      %  NumberOfTrains: number of trains in the sequence
      %  ITI: seconds between last pulse and 1st pulse in next train
      %  PriorWarningSound: if true, a beep will be on before each train
      if nargin>1
        try S = struct(varargin{:});
        catch, error("Parameters must be in a struct or in key/value pairs.");
        end
        self.train = S; % setter do the check work
      end
      self.setPage("Timing"); % show error in case of invalid parameters
      S = self.train;
      b = uint16([S.RepRate*10 S.PulsesInTrain S.NumberOfTrains S.ITI*10]);
      tc = key(self.TCs, self.TimingControl);
      % no control for RampUp/RampUpTrains?
      self.serialCmd([11 1 tc typecast(swapbytes(b),'uint8') S.PriorWarningSound]);
      self.serialCmd([11 0]); % sync
    end

    function setMode(self, mode)
      % T.setMode("Standard"); % "Standard" "Power" "Twin" or "Dual"
      k = key(self.modes, mode);
      if isempty(k), error('Valid mode input: %s.', list(self.modes)); end
      self.raw9(2) = k;
      self.setParam9;
    end

    function setCurrentDirection(self, curDir)
      % T.setCurrentDirection("Normal"); % "Normal" or "Reverse" if available
      k = key(self.curDirs, curDir);
      if isempty(k), error('Valid CurrentDirection input: %s.', list(self.curDirs)); end
      self.raw9(3) = k;
      self.setParam9;
    end

    function setWaveform(self, wvForm)
      % T.setWaveform("Biphasic"); % "Monophasic" "Biphasic" "Halfsine" or "Biphasic Burst"
      k = key(self.wvForms, wvForm);
      if isempty(k), error("Valid Waveform input: %s.", list(self.wvForms)); end
      self.raw9(4) = k;
      self.setParam9;
    end

    function setBurstPulses(self, nPulse)
      % T.setBurstPulses(3); % number of pulses in a burst, 2 to 5
      if nargin<2 || ~isscalar(nPulse) || ~ismember(nPulse, 2:5)
        error("BurstPulses must be 2, 3, 4 or 5.");
      end
      self.raw9(5) = 5-nPulse;
      self.setParam9;
    end

    function setIPI(self, ipi)
      % T.setIPI(20); % set inter pulse interval in ms
      if nargin<2, error("Need to provide IPI input"); end
      [self.IPI, dev] = closestVal(ipi, self.IPIs);
      if dev>0.1, warning("Actual IPI is %g", self.IPI); end
      self.setParam9;
    end

    function setBARatio(self, ratio)
      % T.setBARatio(1); % set Pulse B/A Ratio
      [self.BARatio, dev] = closestVal(ratio, 0.2:0.05:5);
      if dev>0.1, warning("Actual BARatio is %g", self.BARatio); end
      self.setParam9;
    end

    function setPage(self, page)
      % T.setPage("Timing"); % switch to a page on device
      k = key(self.pages, page);
      if isempty(k), error("Valid Page input: %s.", list(self.pages)); end
      self.serialCmd([7 k 0]);
    end

    function setDelay(self, in3)
      % T.setDelay([0 0 100]); % set 3 delays: in, out trigger and charge delay in ms.
      %  delayInputTrig: delay to start stimulation after trigger in
      %  delayOutputTrig: delay to send trigger after stimulation (can be negative)
      %  chargeDelay: delay to wait before recharging
      if nargin<2 || numel(in3)~=3, error("Input must be 3 delays in ms"); end
      in3(1) = closestVal(in3(1), [0:0.1:10 11:100 110:10:6500]);
      in3(2) = closestVal(in3(2), [-100:-10 -9.9:0.1:10 11:100]);
      in3(3) = closestVal(in3(3), [0:10:100 125:25:4000 4050:50:12000]);
      p16 = uint16(in3(:)'.*[10 10 1]);
      self.serialCmd([10 1 typecast(swapbytes(p16),'uint8')]);
      self.serialCmd([10 0]);
    end

    function resync(self)
      % Update the parameters from stimulator, in case changes at stimulator
      self.serialCmd(5); % basic info
      self.serialCmd([9 0]); % burst parameters etc
      self.serialCmd([10 0]); % delays
      self.serialCmd([11 0]); % train
      self.serialCmd([12 0]); % page, nStimuli
    end

    function save(self, fileName)
      % T.save("./myParams.mat"); 
      % Save parameters to a file for future sessions to load
      if nargin<2 || isempty(fileName)
        [pNam, fNam] = fileparts(self.filename);
        [fNam, pNam] = uiputfile("*.mat", "Specify a file to save", fullfile(pNam, fNam));
        if isnumeric(fNam), return; end
        fileName = fullfile(pNam, fNam);
      end
      O = warning("off", 'MATLAB:structOnObject'); T0 = struct(self); warning(O);
      save(fileName, "-struct", "T0", "mode", "currentDirection", "waveform", ...
          "burstPulses", "IPI", "BARatio", "TimingControl", "delays", "train");
    end

    function load(self, fileName)
      % T.load("./myParams.mat"); 
      % Load and set parameters in .mat or .CG3 file to the stimuluator
      if nargin<2 || isempty(fileName)
        [fNam, pNam] = uigetfile('*.CG3;*.mat', 'Select a file to load');
        if isnumeric(fNam), return; end
        fileName = fullfile(pNam, fNam);
      end
      if endsWith(fileName, '.mat', 'IgnoreCase', true) % .mat file
        T0 = load(fileName);
        if ~isfield(T0, "burstPulses"), error("Invalid parameter file"); end
        self.raw9(2) = key(self.modes, T0.mode);
        self.raw9(3) = key(self.curDirs, T0.currentDirection);
        self.raw9(4) = key(self.wvForms, T0.waveform);
        self.raw9(5) = 5 - T0.burstPulses;
        self.IPI = T0.IPI;
        self.BARatio = T0.BARatio;
        self.TimingControl = T0.TimingControl;
        self.delays = T0.delays;
        self.train = T0.train;
      else % .CG3 file
        ch = fileread(fileName);
        getval = @(k)str2double(regexp(ch,"(?<="+k+"=)\d+","match","once"));
        self.raw9(2:5) = [getval('Mode') getval('Current Direction') ...
            getval('Wave Form') 5-getval('Burst Pulses')];
        self.IPI = getval('Inter Pulse Interval')/10;
        self.BARatio = getval('Pulse BA Ratio')/100;
        self.TimingControl = val(self.TCs, getval('Timing Control'));
        S.RepRate = getval('Rep Rate')/10;
        S.PulsesInTrain = getval('Pulses in train');
        S.NumberOfTrains = getval('Number of Trains');
        S.ITI = getval('Inter Train Interval')/10;
        S.PriorWarningSound = getval('Prior Warning Sound');
        S.RampUp = getval('RampUp')/100;
        S.RampUpTrains = getval('RampUpTrains');
        self.train = S;
        % getval('Trig Output'); % 1
        self.delays = [getval('Delay Input')/10 getval('Delay Output')/10 getval('Charge Delay')];
        % getval('Auto Discharge Time'); % 5 / 10
      end
      self.filename = fileName;
      self.setIPI(self.IPI);
      self.setDelay(self.delays);
      self.setTrain;
      self.resync;
    end

    function set.train(self, S)
      d = setdiff(fieldnames(S), fieldnames(self.train));
      if ~isempty(d), error("Unknown parameters: %s", strjoin(d, ', ')); end
      if isfield(S, 'RepRate') && self.train.RepRate ~= S.RepRate
        [val, dev] = closestVal(S.RepRate, self.RATEs); %#ok pps
        self.train.RepRate = val;
        if dev>0.1, warning("RepRate adjusted to %g", val); end
      end
      if isfield(S, 'PulsesInTrain') && self.train.PulsesInTrain ~= S.PulsesInTrain
        [val, dev] = closestVal(S.PulsesInTrain, [1:1000 1100:100:2000]);
        self.train.PulsesInTrain = val;
        if dev>0.1, warning("PulsesInTrain adjusted to %i", val); end
      end
      if isfield(S, 'NumberOfTrains') && self.train.NumberOfTrains ~= S.NumberOfTrains
        [val, dev] = closestVal(S.NumberOfTrains, 1:500);
        self.train.NumberOfTrains = val;
        if dev>0.1, warning("NumberOfTrains adjusted to %i", val); end
      end
      if isfield(S, 'ITI') && self.train.ITI ~= S.ITI
        [val, dev] = closestVal(S.ITI, 0.1:0.1:300);
        self.train.ITI = val;
        if dev>0.1, warning("ITI adjusted to %g", val); end
      end
      if isfield(S, 'PriorWarningSound')
        self.train.PriorWarningSound = logical(S.PriorWarningSound);
      end
      if isfield(S, 'RampUp') && self.train.RampUp ~= S.RampUp
        [val, dev] = closestVal(S.RampUp, 0.7:0.05:1);
        self.train.RampUp = val;
        if dev>0.1, warning("RampUp adjusted to %g", val); end
      end
      if isfield(S, 'RampUpTrains') && self.train.RampUpTrains ~= S.RampUpTrains
        [val, dev] = closestVal(S.RampUpTrains, 1:10);
        self.train.RampUpTrains = val;
        if dev>0.1, warning("RampUpTrains adjusted to %i", val); end
      end
      if isfield(S, 'isRunning')
        self.train.isRunning = S.isRunning;
      end
      S = self.train;
      secs = ((S.PulsesInTrain-1)/S.RepRate + S.ITI) * S.NumberOfTrains - S.ITI;
      self.train.TotalTime = sprintf("%02d:%02.0f", fix(secs/60), rem(secs,60));
      if exist('TMS_GUI', 'file')==2, TMS_GUI("update"); end % before "Set Train"
    end    
  end

  methods (Hidden)
    function serialCmd(self, bytes)
      % fprintf('Sent%s\n', sprintf(' %02X', bytes)); % for debug
      bytes = [254 numel(bytes) bytes CRC8(bytes) 255];
      try self.port.write(bytes, 'uint8'); catch, end
    end

    function setParam9(self) % Shortcut to set parameters via commandID=9
      self.raw9([7 6]) = typecast(uint16(self.IPI*10), 'uint8');
      self.raw9([9 8]) = typecast(uint16(self.BARatio*100), 'uint8');
      self.serialCmd([9 1 self.raw9]);
      self.serialCmd([9 0]); % sync
    end

    function setScales(self) % PostSet listener for [model mode waveform]
      if self.Model == "X100"
        self.modes = dict("Standard");
        self.curDirs = dict(["Normal" "Reverse"]);
        self.wvForms = dict(["Monophasic" "Biphasic" "Biphasic Burst"], [0 1 3]);
        if self.waveform == "Biphasic Burst", self.RATEs = [0.1:0.1:1 2:20];
        else, self.RATEs = [0.1:0.1:1 2:100];
        end
      elseif self.Model == "X100+Option"
        self.modes = dict(["Standard" "Power" "Twin" "Dual"]);
        self.curDirs = dict(["Normal" "Reverse"]);
        self.wvForms = dict(["Monophasic" "Biphasic" "Halfsine" "Biphasic Burst"]);
        if ismember(self.mode, ["Twin" "Dual"])
          self.wvForms = dict(["Monophasic" "Biphasic" "Halfsine"]);
          if self.waveform == "Monophasic", self.RATEs = [0.1:0.1:1 2:5];
          else, self.RATEs = [0.1:0.1:1 2:50];
          end
        elseif self.waveform == "Biphasic Burst"
          self.RATEs = [0.1:0.1:1 2:20];
        end
      elseif self.Model == "R30"
        self.modes = dict("Standard");
        self.curDirs = dict("Normal");
        self.wvForms = dict("Biphasic", 1);
        self.RATEs = [0.1:0.1:1 2:30];
      elseif self.Model == "R30+Option"
        self.modes = dict(["Standard" "Twin" "Dual"], [0 2 3]);
        self.curDirs = dict("Normal");
        self.wvForms = dict(["Monophasic" "Biphasic"]);
        if ismember(self.mode, ["Twin" "Dual"]), self.RATEs = [0.1:0.1:1 2:5];
        else, self.RATEs = [0.1:0.1:1 2:30];
        end
      else
        warning("Scales for %s is not supported for now.", self.Model);
        return;
      end

      self.IPIs = flip([0.5:0.1:10 10.5:0.5:20 21:100]);
      if contains(self.Model, "+Option") && ismember(self.mode, ["Twin" "Dual"])
        if self.waveform == "Monophasic", i0 = 2; else, i0 = 1; end
        self.IPIs = flip([i0:0.1:10 10.5:0.5:20 21:100 110:10:500 550:50:1000 1100:100:3000]);
      end
    end

    function decodeBytes(self)
      % Update parameters from stimulator: 8+ bytes callback
      % TrigOutput enable/disable, CoilTypeDisplay on/off not in b(3) of 0:3 5 8:12
      n = 0;
      while 1
        pause(0.05);
        n1 = self.port.NumBytesAvailable;
        if n==n1, break; else, n = n1;  end
      end
      if n<8, return; end
      bytes = self.port.read(n, 'uint8');
      i0 = find(bytes==254);
      for i = 1:numel(i0)
        try b = bytes(i0(i):i0(i)+bytes(i0(i)+1)+3); catch, continue; end
        % valid packet: [254 numel(b)-4 b(3:end-2) CRC8(b(3:end-2)) 255]
        if b(end)~=255 || b(end-1)~=CRC8(b(3:end-2))
          warning("Corrupted data?"); disp(b); continue;
        end
        % fprintf('    %s\n', sprintf(' %02X', b(3:end-2))); % for debug
        iBits = @(i,j)bitget(b(j),i)*2.^(0:numel(i)-1)';
        switch b(3)
          case {0 5} % Localite sends 5 twice a second
            self.Model = val(self.models, iBits(6:8, 4)); % Model first for b(3)==[0 5]
            self.mode = val(self.modes, iBits(1:2, 4));
            self.waveform = val(self.wvForms, iBits(3:4, 4));
            self.enabled = bitget(b(4), 5);
            self.info.SerialNo = b(5:7)*256.^[2 1 0]';
            self.temperature = b(8);
            coils = dict(["Cool-B65" "C-B60"], [60 72]); % add/update pairs
            if any(coils.keys==b(9)), self.info.CoilType = val(coils, b(9));
            else, self.info.CoilType = string(b(9));
            end
            self.amplitude = b(10:11);
          case 1
            self.amplitude = b(4:5);
            self.mode = val(self.modes, iBits(1:2, 6));
            self.waveform = val(self.wvForms, iBits(3:4, 6));
            self.enabled = bitget(b(6), 5);
            % self.Model = val(self.models, iBits(6:8, 6));
          case 2
            self.didt = b(4:5);
            self.mode = val(self.modes, iBits(1:2, 6));
            self.waveform = val(self.wvForms, iBits(3:4, 6));
            self.enabled = bitget(b(6), 5);
            % self.Model = val(self.models, iBits(6:8, 6));
          case {3 6} % b(5)=0x48?
            self.temperature = b(4);
            self.mode = val(self.modes, iBits(1:2, 6));
            self.waveform = val(self.wvForms, iBits(3:4, 6));
            self.enabled = bitget(b(6), 5);
            % self.Model = val(self.models, iBits(6:8, 6));
          case 4
            self.MEP.maxAmplitude = b(4:7)*256.^(3:-1:0)'; % in µV
            self.MEP.minAmplitude = b(8:11)*256.^(3:-1:0)';
            self.MEP.maxTime = b(12:15)*256.^(3:-1:0)'; % in µs
          case 8 % b(4)=2 3 4?
            self.train.isRunning = b(5);
            self.mode = val(self.modes, iBits(1:2, 6));
            self.waveform = val(self.wvForms, iBits(3:4, 6));
            self.enabled = bitget(b(6), 5);
            % self.Model = val(self.models, iBits(6:8, 6));
          case 9
            self.raw9 = b(5:13); % for setParam9
            % self.Model = val(self.models, b(5));
            self.mode = val(self.modes, b(6));
            self.currentDirection = val(self.curDirs, b(7));
            self.waveform = val(self.wvForms, b(8));
            self.burstPulses = 5 - b(9);
            if self.waveform == "Biphasic Burst"
              self.IPI = self.IPIs(b(11)*256+b(10)+1);
            end
            if contains(self.Model, "+Option")
              self.BARatio = 5 - b(12)*0.05;
            end
          case 10
            outDelay = double(typecast(uint8(b([8 7])), 'int16')) / 10;
            self.delays = [b(5:6)*[256 1]'/10 outDelay b(9:10)*[256 1]'];
          case 11
            self.TimingControl = val(self.TCs, b(5));
            S.RepRate = b(6:7)*[256 1]'/10;
            S.PulsesInTrain = b(8:9)*[256 1]';
            S.NumberOfTrains = b(10:11)*[256 1]';
            S.ITI = b(12:13)*[256 1]'/10;
            S.PriorWarningSound = b(14);
            S.RampUp = b(15)/100;
            S.RampUpTrains = b(16);
            self.train = S;
          case 12
            % self.train.NumberOfTrains = b(4:5)*[256 1]';
            % b(7:9)*256.^[2 1 0]': PulsesInTrain * NumberOfTrains
            self.info.nStimuli = b(12:13)*[256 1]'; % b(10:11) too?
            self.info.page = val(self.pages, b(16));
          otherwise, warning("Unknown b(3)=%i", b(3)); % 7
        end
      end
      if exist('TMS_GUI', 'file')==2, TMS_GUI("update"); end
    end

    % Override to hide inherited methods: cleaner for usage & doc
    function lh = addlistener(varargin); lh=addlistener@handle(varargin{:}); end
    function lh = listener(varargin); lh=listener@handle(varargin{:}); end
    function p = findprop(varargin); p = findprop@handle(varargin{:}); end
    function lh = findobj(varargin); lh = findobj@handle(varargin{:}); end
    function TF = eq(varargin); TF = eq@handle(varargin{:}); end
    function TF = ne(varargin); TF = ne@handle(varargin{:}); end
    function TF = lt(varargin); TF = lt@handle(varargin{:}); end
    function TF = le(varargin); TF = le@handle(varargin{:}); end
    function TF = gt(varargin); TF = gt@handle(varargin{:}); end
    function TF = ge(varargin); TF = ge@handle(varargin{:}); end
    function notify(varargin); notify@handle(varargin{:}); end
    function delete(obj); delete@handle(obj); end
  end
end

function rst = CRC8(bytes)
  % Compute CRC8 (Dallas/Maxim) checksum using the polynomial x^8 + x^5 + x^4 + 1
  persistent C8 % cache CRC8 for 0:255
  if isempty(C8)
    C8 = zeros(1, 256, 'uint8');
    poly8 = 0b100011001; % LE
    for c = 1:255
      a = uint16(c);
      for i = 1:8
        if bitget(a,1), a = bitxor(a, poly8); end
        a = bitshift(a, -1);
      end
      C8(c+1) = a;
    end
  end
  rst = C8(1);
  for b = uint8(bytes), rst = C8(1+double(bitxor(rst,b))); end
end

function [val, dev] = closestVal(val, vals)
  % Return the closest value for val inside vals, and the deviation
  [dev, id] = min(abs(val-vals));
  dev = dev/val; % ratio
  val = vals(id);
end

function d = dict(vals, keys)
  % struct working with early Matlab without dictionary
  if nargin<2, keys = 0:numel(vals)-1; end % default 0:n-1
  d.keys = uint8(keys);
  d.values = vals; % string array
end
function v = val(d, key), v = d.values(key == d.keys); end
function k = key(d, val), k = d.keys(val == d.values); end
function L = list(d), L = '"'+join(d.values, '", "')+'"'; end
