classdef TMS < handle
% TMS controls Magventure TMS system (developed under X100).
%
% Usage syntax:
%  T = TMS; % Connect to TMS and return handle for later use
%  T.load('myParams.mat'); % load pre-saved stimulation parameters
%  T.enable; % or T.disable; Enable/Disable it like pressing the button at TMS
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
    curDirs = ["Normal" "Reverse"]
    wvForms = ["Monophasic" "Biphasic" "Halfsine" "Biphasic Burst"]
    models = ["R30" "X100" "R30+Option" "X100+Option" "R30+Option+Mono" "MST"];
    modes = ["Standard" "Power" "Twin" "Dual"];
    coils = containers.Map([60 72], {"Cool-B65" "C-B60"}); % can add more
    TCs = ["Sequence" "External Trig" "Ext Seq. Start" "Ext Seq. Cont"]
    pages = ["Main" "Timing" "Trig" "Config" "" "Download" "Protocol" "MEP" ""  "" "" "" ...
         "Service" "" "Treatment" "Treat Select" "Service2" "" "Calculator"]
    IPIs = flip([0.5:0.1:10 10.5:0.5:20 21:100]) % for X100 BiphasicBurst
    BARatios = 0.2:0.05:5;
  end
  properties (Hidden, SetAccess=private)
    port(1,1)
    raw9(1,9) uint8 % store parameters for setParam9()
    debug(1,1) struct % for debug
  end
  properties (SetAccess=private)
    % File name from which the parameters are loaded
    filename = "Default";
    
    % Indicate if stimulator is enabled
    enabled(1,1) logical
    
    % Stimulation amplitude in percent
    amplitude(1,2)
    
    % Coil temperature as shown on the stimulator
    temperature(1,1)
    
    % Realized di/dt in A/µs, as shown on the device
    didt(1,2)
    
    % One of "Monophasic" "Biphasic" or "BiphasicBurst"
    waveform(1,1) = "Biphasic"
    
    % Current direction: "Normal" or "Reverse"
    currentDirection(1,1) = "Normal"
    
    % Number of pulses in a burst: 2 to 5
    burstPulses(1,1)=2
    
    % Pulse B/A Ratio. Will be adjusted to supported value
    BARatio(1,1) =1    

    % Inter pulse interval in ms. Will be adjusted to supported value
    IPI(1,1) =10
    
    % Timing control options
    TimingControl(1,1) = "Sequence"    

    % DelayInputTrig, DelayOutputTrig, ChargeDelay in ms
    delays(1,3)

    % MEP related parameters
    % MEP(1,1) struct

    % Some info about the stimulator, like Model, SerialNo, Mode, etc.
    info = struct("Model", "", "Mode", "", "CoilType", "")
  end
  properties
    % Parameters related train: settable directly
    train = trainParams
  end

  methods
    function self = TMS() % constructor
      % T = TMS; % Connect to Magventure TMS
      persistent OBJ CLN % store it for only single instance
      if ~isempty(OBJ) && isvalid(OBJ), self = OBJ; return; end
      warning("off", "serialport:serialport:ReadWarning");
      for port = flip(serialportlist("available"))
        p = serialport(port, 38400, "Timeout", 0.3);
        p.write([254 1 0 0 255], 'uint8');
        pause(0.1);
        if p.NumBytesAvailable<13, delete(p); continue; else, break; end
      end
      % if ~isvalid(p), OBJ = self; return; end % test without device connected
      assert(exist('p','var') && isvalid(p), "Failed to connect to TMS machine.");
      self.port = p;
      configureCallback(p, "byte", 8, @(~,~)decodeBytes(self));
      CLN = onCleanup(@()delete(p));
      OBJ = self;
      self.resync;
    end

    function firePulse(self)
      % Start single pulse stimulation
      if ~self.enabled, error("Need to enalbe"); end
      self.serialCmd([3 1]);
    end

    function fireTrain(self)
      % Start train or burst stimulation
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
      tc = find(self.TCs==self.TimingControl)-1;
      % no control for RampUp/RampUpTrains?
      self.serialCmd([11 1 tc typecast(swapbytes(b),'uint8') S.PriorWarningSound]);
      self.serialCmd([11 0]); % sync
    end

    function setCurrentDirection(self, curDir)
      % T.setCurrentDirection("Normal"); % "Normal" or "Reverse"
      if nargin<2 || ~ismember(curDir, self.curDirs)
        error('CurrentDirection must be "Normal" or "Reverse".');
      end
      self.raw9(3) = find(curDir==self.curDirs)-1;
      self.setParam9;
    end

    function setWaveform(self, wvForm)
      % T.setWaveform("Biphasic"); % "Monophasic" "Biphasic" or "BiphasicBurst"
      if nargin<2 || ~ismember(wvForm, self.wvForms)
        error("Waveform must be one of %s.", join(self.wvForms, ', '));
      end
      if wvForm=="Halfsine", error("Halfsine not supported for model X100"); end
      self.raw9(4) = find(wvForm==self.wvForms)-1;
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
      [self.IPI, dev] = self.closestVal(ipi, self.IPIs);
      if dev>0.1, warning("Actual IPI is %g", self.IPI); end
      self.setParam9;
    end

    function setBARatio(self, ratio)
      % T.setBARatio(1); % set Pulse B/A Ratio
      if nargin<2, error("Need to provide IPI input"); end
      [self.BARatio, dev] = self.closestVal(ratio, self.BARatios);
      if dev>0.1, warning("Actual BARatio is %g", self.BARatio); end
      self.setParam9;
    end

    function setPage(self, page)
      % T.setPage("Protocol"); % switch to a page on device
      if nargin<2 || ~ismember(page, self.pages)
        error("Page input must be one of %s.", join(self.pages, ', '));
      end
      self.serialCmd([7 find(page==self.pages) 0]);
    end

    function setDelay(self, in3)
      % T.setDelay([0 0 100]); % set 3 delays: in, out trigger and charge dealy in ms.
      %  delayInputTrig: delay to start stimulation after trigger in
      %  delayOutputTrig: delay to send trigger after stimulation (can be negative)
      %  chargeDelay: delay to wait before recharging
      if nargin<2 || numel(in3)~=3, error("Input must be 3 delays in ms"); end
      in3(1) = self.closestVal(in3(1), [0:0.1:10 11:100 110:10:6500]);
      in3(2) = self.closestVal(in3(2), [-100:-10 -9.9:0.1:10 11:100]);
      in3(3) = self.closestVal(in3(3), [0:10:100 125:25:4000 4050:50:12000]);
      p16 = uint16(in3(:)'.*[10 10 1]);
      self.serialCmd([10 1 typecast(swapbytes(p16),'uint8')]);
      self.serialCmd([10 0]);
    end

    function resync(self)
      % Update the parameters from stimuluator, in case changed at stimulator
      self.serialCmd(5); % basic info
      self.serialCmd([9 0]); % burst parameters etc
      self.serialCmd([10 0]); % delays
      self.serialCmd([11 0]); % train
      self.serialCmd([12 0]); % page, nStimuli
    end

    function save(self, fileName)
      % T.save("./myParams.mat"); 
      % Save parameters to a file for future sessons to load
      if nargin<2 || isempty(fileName)
        [fNam, pNam] = uiputfile("*.mat", "Specify a file to save", self.filename+".mat");
        if isnumeric(fNam), return; end
        fileName = fullfile(pNam, fNam);
      end
      O = warning("off", 'MATLAB:structOnObject');
      cln = onCleanup(@()warning(O));
      T0 = struct(self);
      T0 = rmfield(T0, 'port');
      T0.train = struct(T0.train);  % wont rely on trainParams, also for load
      save(fileName, '-struct', 'T0');
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
        self.raw9(3) = find(T0.currentDirection==T0.curDirs)-1;
        self.raw9(4) = find(T0.waveform==T0.wvForms)-1;
        self.raw9(5) = 5-T0.burstPulses;
        self.IPI = T0.IPI;
        self.BARatio = T0.BARatio;
        self.TimingControl = T0.TimingControl;
        self.delays = T0.delays;
        self.train = T0.train; % setter assigns only 5 fields
      else % .CG3 file
        ch = fileread(fileName);
        getval = @(k)str2double(regexp(ch,"(?<="+k+"=)\d+","match","once"));
        self.raw9(2:5) = [getval('Mode') getval('Current Direction') ...
            getval('Wave Form') 5-getval('Burst Pulses')];
        self.IPI = getval('Inter Pulse Interval')/10;
        self.BARatio = getval('Pulse BA Ratio')/100;
        self.TimingControl = self.TCs{getval('Timing Control')+1};
        self.train.RepRate = getval('Rep Rate')/10;
        self.train.PulsesInTrain = getval('Pulses in train');
        self.train.NumberOfTrains = getval('Number of Trains');
        self.train.ITI = getval('Inter Train Interval')/10;
        self.train.PriorWarningSound = getval('Prior Warning Sound');
        self.train.RampUp = getval('RampUp')/100;
        self.train.RampUpTrains = getval('RampUpTrains');
        % getval('Trig Output'); % 1
        self.delays = [getval('Delay Input')/10 getval('Delay Output')/10 getval('Charge Delay')];
        % getval('Auto Discharge Time'); % 5 / 10
      end
      [~, self.filename] = fileparts(fileName);
      self.setIPI(self.IPI);
      self.setDelay(self.delays);
      self.setTrain;
    end

    function set.train(self, S) % S can be struct or trainParams
      d = setdiff(fieldnames(S), fieldnames(self.train));
      if ~isempty(d), error("Unknown parameters: %s", strjoin(d, ', ')); end
      if isfield(S, 'RepRate') && self.train.RepRate ~= S.RepRate
        if self.waveform=="Biphasic Burst", rates = [0.1:0.1:1 2:20]; %#ok
        else, rates = [0.1:0.1:1 2:100];
        end
        [val, dev] = self.closestVal(S.RepRate, rates); % pps
        self.train.RepRate = val;
        if dev>0.1, warning("RepRate adjusted to %g", val); end
      end
      if isfield(S, 'PulsesInTrain') && self.train.PulsesInTrain ~= S.PulsesInTrain
        [val, dev] = self.closestVal(S.PulsesInTrain, [1:1000 1100:100:2000]);
        self.train.PulsesInTrain = val;
        if dev>0.1, warning("PulsesInTrain adjusted to %i", val); end
      end
      if isfield(S, 'NumberOfTrains') && self.train.NumberOfTrains ~= S.NumberOfTrains
        [val, dev] = self.closestVal(S.NumberOfTrains, 1:500);
        self.train.NumberOfTrains = val;
        if dev>0.1, warning("NumberOfTrains adjusted to %i", val); end
      end
      if isfield(S, 'ITI') && self.train.ITI ~= S.ITI
        [val, dev] = self.closestVal(S.ITI, 0.1:0.1:300);
        self.train.ITI = val;
        if dev>0.1, warning("ITI adjusted to %g", val); end
      end
      if isfield(S, 'PriorWarningSound')
        self.train.PriorWarningSound = logical(S.PriorWarningSound);
      end
      if isfield(S, 'RampUp') && self.train.RampUp ~= S.RampUp
        [val, dev] = self.closestVal(S.RampUp, 0.7:0.05:1);
        self.train.RampUp = val;
        if dev>0.1, warning("RampUp adjusted to %g", val); end
      end
      if isfield(S, 'RampUpTrains') && self.train.RampUpTrains ~= S.RampUpTrains
        [val, dev] = self.closestVal(S.RampUpTrains, 1:10);
        self.train.RampUpTrains = val;
        if dev>0.1, warning("RampUpTrains adjusted to %i", val); end
      end
      if isfield(S, 'isRunning') && ~isstruct(S)
        self.train.isRunning = S.isRunning; % assigning inside class only
      end
      try TMS_GUI("update"); catch, end % update TotalTime
    end    
  end

  methods (Hidden)
    function serialCmd(self, bytes)
      self.port.write([254 numel(bytes) bytes self.CRC8(bytes) 255], 'uint8');
      self.debug = struct('dt', datetime, 'sent', bytes, 'received', []);
    end

    function setParam9(self) % Shortcut to set parameters via commandID=9
      self.raw9([7 6]) = typecast(uint16(self.IPI*10), 'uint8');
      self.raw9([9 8]) = typecast(uint16(self.BARatio*100), 'uint8');
      self.serialCmd([9 1 self.raw9]);
      self.serialCmd([9 0]); % sync
    end

    function decodeBytes(self)
      % Update parameters from stimulator: 8-byte callback
      % TrigOutput enable/disable, CoilTypeDisplay on/off not in b(3) of 5/9/10/11/12
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
        if b(end)~=255 || b(end-1)~=self.CRC8(b(3:end-2))
          warning("Corrupted data?"); disp(b); continue;
        end
        if isempty(self.debug.received)
          self.debug.dt = seconds(datetime-self.debug.dt);
          self.debug.received = b(3:end-2);
        end
        iBits = @(i,j)bitget(b(j),i)*2.^(0:numel(i)-1)'+1;
        switch b(3)
          case {0 5} % Localite sends 5 twice a seocnd
            self.info.Mode = self.modes(iBits(1:2, 4));
            self.waveform = self.wvForms(iBits(3:4, 4));
            self.enabled = bitget(b(4), 5);
            self.info.Model = self.models(iBits(6:8, 4));
            self.info.SerialNo = b(5:7)*256.^[2 1 0]';
            self.temperature = b(8);
            try self.info.CoilType = self.coils(b(9));
            catch, self.info.CoilType = string(b(9));
            end
            self.amplitude = b(10:11);
          case 1
            self.amplitude = b(4:5);
            self.info.Mode = self.modes(iBits(1:2, 6));
            self.waveform = self.wvForms(iBits(3:4, 6));
            self.enabled = bitget(b(6), 5);
            self.info.Model = self.models(iBits(6:8, 6));
          case 2
            self.didt = b(4:5);
            self.info.Mode = self.modes(iBits(1:2, 6));
            self.waveform = self.wvForms(iBits(3:4, 6));
            self.enabled = bitget(b(6), 5);
            self.info.Model = self.models(iBits(6:8, 6));
          case {3 6}
            self.temperature = b(4);
            self.info.Mode = self.modes(iBits(1:2, 6));
            self.waveform = self.wvForms(iBits(3:4, 6));
            self.enabled = bitget(b(6), 5);
            self.info.Model = self.models(iBits(6:8, 6));
          % case 4 % MEP
          %   self.MEP.maxAmplitude = b(4:7)*256.^(3:-1:0)'; % in µV
          %   self.MEP.minAmplitude = b(8:11)*256.^(3:-1:0)';
          %   self.MEP.maxTime = b(12:15)*256.^(3:-1:0)'; % in µs
          case 8
            self.train.isRunning = b(5);
            self.info.Mode = self.modes(iBits(1:2, 6));
            self.waveform = self.wvForms(iBits(3:4, 6));
            self.enabled = bitget(b(6), 5);
            self.info.Model = self.models(iBits(6:8, 6));
          case 9
            self.raw9 = b(5:13); % for setParam9
            self.info.Model = self.models(b(5)+1);
            self.info.Mode = self.modes(b(6)+1);
            self.currentDirection = self.curDirs(b(7)+1);
            self.waveform = self.wvForms(b(8)+1);
            self.burstPulses = 5 - b(9);
            if self.waveform == "Biphasic Burst"
              try self.IPI = self.IPIs(b(10)+1); catch, end % b(11) for other modes?
              self.BARatio = 5 - b(12)*0.05;
            end
          case 10
            outDelay = double(typecast(uint8(b([8 7])), 'int16')) / 10;
            self.delays = [b(5:6)*[256 1]'/10 outDelay b(9:10)*[256 1]'];
          case 11
            self.TimingControl = self.TCs(b(5)+1);
            self.train.RepRate = b(6:7)*[256 1]'/10;
            self.train.PulsesInTrain = b(8:9)*[256 1]';
            self.train.NumberOfTrains = b(10:11)*[256 1]';
            self.train.ITI = b(12:13)*[256 1]'/10;
            self.train.PriorWarningSound = logical(b(14));
            self.train.RampUp = b(15)/100;
            self.train.RampUpTrains = b(16);
          case 12 % not used so far
            % self.train.NumberOfTrains = b(4:5)*[256 1]';
            % b(7:9)*256.^[2 1 0]': PulsesInTrain * NumberOfTrains
            self.info.nStimuli = b(12:13)*[256 1]'; % b(10:11) too?
            self.info.page = self.pages(b(16));
        end
      end
      try TMS_GUI("update"); catch, end
    end

    % Override/hide inherited methods: cleaner for usage & doc
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

  methods (Static, Hidden)
    function rst = CRC8(bytes)
      b = arrayfun(@(a)bitget(a,1:8), bytes, 'UniformOutput', false);
      b = [false logical(cell2mat(b)) false(1,8)];
      poly8 = logical([1 0 0 1 1 0 0 0 1]); % x^8 + x^5 + x^4 + 1
      rst = b(1:9);
      for i = 10:numel(b)
        rst = [rst(2:end) b(i)];
        if rst(1), rst = xor(rst, poly8); end
      end
      rst = rst(2:9) * 2.^(0:7)';
    end

    function [val, dev] = closestVal(val, vals)
      [dev, id] = min(abs(val-vals));
      dev = dev/val; % ratio
      val = vals(id);
    end
  end
end
