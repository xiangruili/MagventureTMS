classdef TMS < handle
% TMS controls Magventure TMS system (tested under X100).
%
% Usage syntax:
%  T = TMS; % Connect to stimulator and return handle for later use
%  T.load('myParams.mat'); % load pre-saved stimulation parameters
%  T.enabled = 1; % Enable it like pressing the button at stimulator
%  T.amplitude = 60; % set amplitude to 60%
%  T.firePulse; % send a single pulse/burst stimulation
%
%  T.waveform = "Biphasic Burst"; % set wave form
%  T.burstPulses = 3; % set number of pulses in a burst, 2 to 5
%  T.IPI = 20; % set inter pulse interval in ms
%  T.train.RepRate= 5; % or T.train = struct('RepRate', 5, 'ITI', 8);
%   Here are important train parameters:
%     RepRate: number of pulses per second in each train
%     PulsesInTrain: number of pulses or bursts in each train
%     NumberOfTrains: number of trains in the sequence
%     ITI: Seconds between last pulse and first pulse in next train
%  T.fireTrain; % Start train of pulse/burst stimulation
% 
%  See also TMS motorThreshold

% Some commands are figured out by testing, but undocumented by MagVenture
% 241228 xiangrui.li@gmail.com, first working version
% 250718 last updated

  properties (Hidden, Constant)
    MODELs = dict(["R30" "X100" "R30+Option" "X100+Option" "R30+Option+Mono" "MST"])
    TCs = dict(["Sequence" "External Trig" "Ext Seq. Start" "Ext Seq. Cont"])
    PAGEs = dict(["Main" "Timing" "Trig" "Config" "Download" "Protocol" "MEP" "Service" ...
        "Treatment" "Treat Select" "Service2" "Calculator"], [1:4 6:8 13 15:17 19])
    p2save = ["mode" "currentDirection" "waveform" "burstPulses" "IPI" "BARatio" "delays" "CoilTypeDisplay"]
  end
  properties (Hidden, SetAccess=private)
    port(1,1) % serialport obj
    ExRate(1,1) logical % ExtendedRepRate with 0.1 step
    skipWrite = false % flag to skip serial write when true
  end
  properties (Hidden, Dependent)
    MODEs
    curDirs
    wvForms
    IPIs
    RATEs
  end
  properties
    % Show and control stimulator is enabled or disabled
    enabled(1,1) logical
    
    % Show and control stimulation amplitude in percent
    amplitude(1,2) {mustBeInRange(amplitude,0,100), mustBeInteger}
  end
  properties (SetAccess=private)
    % Realized di/dt in A/µs, as shown on the stimulator
    didt(1,2)

    % Coil temperature as shown on the stimulator
    temperature(1,1) = 21

    % Indidate if train sequence is running
    trainRunning(1,1) logical
    
    % Total time to run the sequence, based on train parameters
    trainTime = "00:14"

    % Information for MEP
    MEP(1,1) struct

    % Some info/status: SerialNo, Connected coil, etc.
    info = struct('CoilType', "")

    % File name from which the parameters are loaded
    filename(1,1) string = ""

    % % Protocol Setup: currently only read from .CG3 file
    % protocol = struct;

    % Stimulator model
    Model(1,1) string = "X100" % fake for Scales
  end
  properties (AbortSet)
    % Stimulator mode: "Standard" "Power" "Twin" or "Dual", depending on model
    mode(1,1) string = "Standard"

    % Current direction: "Normal" or "Reverse" if available
    currentDirection(1,1) string = "Normal"

    % Wave form: "Monophasic" "Biphasic" "HalfSine" or "Biphasic Burst"
    waveform(1,1) string = "Biphasic"

    % Pulse B/A Ratio. Will be adjusted to supported value
    BARatio(1,1) {mustBeInRange(BARatio,0.2,5)} = 1

    % Number of pulses in a burst: 2 to 5
    burstPulses(1,1) {mustBeMember(burstPulses,2:5)} = 2

    % Inter pulse interval in ms. Will be adjusted to supported value
    IPI(1,1) {mustBePositive} = 10

    % DelayInputTrig, DelayOutputTrig, ChargeDelay in ms
    delays(1,3)

    % Parameters related to train
    train = struct('TimingControl', "Sequence", 'RepRate', 1, ...
        'PulsesInTrain', 5, 'NumberOfTrains', 3, 'ITI', 1, ...
        'PriorWarningSound', true, 'RampUp', 1, 'RampUpTrains', 10)

    % Current page on the stimulator
    page(1,1) string = "Main"

    % Display coil type if true. For now must update manually if changed on Stimulator 
    CoilTypeDisplay(1,1) logical = true
  end

  methods
    function self = TMS()
      % T = TMS; % Connect to Magventure stimulator
      persistent OBJ CLN
      if ~isempty(OBJ) && isvalid(OBJ), self = OBJ; return; end % single instance
      for port = flip(serialportlist('available'))
        p = serialport(port, 38400, 'Timeout', 0.3);
        p.write([254 1 0 0 255], 'uint8');
        pause(0.1);
        if p.NumBytesAvailable<13, delete(p); continue; else, break; end
      end
      OBJ = self;
      CLN = onCleanup(@()self.disconnect);
      try
        self.port = p; % error if p not exist
        configureCallback(p, "byte", 8, @(~,~)read(self));
        self.resync;
      catch % warn rather than error so code can run with no connection
        fprintf(2, ' Failed to connect to stimulator.\n');
      end
    end

    function firePulse(self)
      % Start single pulse or single burst stimulation
      if ~self.enabled, error('Need to enable'); end
      self.write(3);
    end

    function fireTrain(self)
      % Start train stimulation
      if ~self.enabled, error('Need to enable'); end
      self.page = "Timing";
      self.write(4);
    end

    function fireProtocol(self)
      % Start stimulation in Protocol
      if ~self.enabled, error('Need to enable'); end
      self.page = "Protocol";
      self.write(4);
    end

    function out = get.MODEs(self)
      if self.Model == "R30+Option"
        out = dict(["Standard" "Twin" "Dual"], [0 2 3]);
      elseif self.Model == "X100+Option"
        out = dict(["Standard" "Power" "Twin" "Dual"]);
      else
        out = dict("Standard");
      end
    end
    
    function out = get.curDirs(self)
      if ismember(self.Model, ["R30" "R30+Option"]), out = dict("Normal");
      else, out = dict(["Normal" "Reverse"]);
      end
  end

    function out = get.wvForms(self)
      if self.Model == "R30"
        out = dict("Biphasic", 1);
      elseif self.Model == "R30+Option"
        out = dict(["Monophasic" "Biphasic"]);
      elseif self.Model == "X100"
        out = dict(["Monophasic" "Biphasic" "Biphasic Burst"], [0 1 3]);
      else
        out = dict(["Monophasic" "Biphasic" "Halfsine" "Biphasic Burst"]);
      end
    end

    function out = get.IPIs(self)
      if ismember(self.mode, ["Twin" "Dual"])
        if self.waveform == "Monophasic", i0 = 2; else, i0 = 1; end
        out = flip([i0:0.1:10 10.5:0.5:20 21:100 110:10:500 550:50:1000 1100:100:3000]);
      else
        out = flip([0.5:0.1:10 10.5:0.5:20 21:100]);
      end
    end
   
    function out = get.RATEs(self)
      LH = [1 100];
      if self.Model == "R30"
        if self.ExRate, LH = [20 30]; else, LH = [1 30]; end
      elseif self.Model == "R30+Option"
        if ismember(self.mode, ["Twin" "Dual"])
          if self.ExRate, LH = [5 0]; else, LH = [1 5]; end
        else, LH = [1 30];
        end
      elseif self.Model == "X100"
        if self.waveform == "Biphasic Burst"
          if self.ExRate, LH = [30 0]; else, LH = [1 20]; end
        else
          if self.ExRate, LH = [20 100]; end
        end
      elseif self.Model == "X100+Option"
        if self.waveform == "Biphasic Burst"
          if self.ExRate, LH = [20 0]; else, LH = [1 20]; end
        elseif ismember(self.mode, ["Twin" "Dual"])
          if self.waveform == "Monophasic"
            if self.ExRate, LH = [5 0]; else, LH = [1 5]; end
          else
            if self.ExRate, LH = [20 50]; else, LH = [1 50]; end
          end
        elseif self.ExRate, LH = [20 100];
        end
      end
      out = [0.1:0.1:LH(1) LH(1)+1:LH(2)];
    end

    function set.amplitude(self, amp)
      self.amplitude = amp;
      self.write([1 amp]);
    end

    function set.enabled(self, tf)
      self.enabled = tf;
      self.write([2 self.enabled]);
    end

    function set.mode(self, mode)
      k = key(self.MODEs, mode); %#ok<*MCSUP>
      if isempty(k), error('Valid mode input: %s.', list(self.MODEs)); end
      self.mode = mode;
      self.setParam9;
    end

    function set.currentDirection(self, curDir)
      k = key(self.curDirs, curDir);
      if isempty(k), error('Valid CurrentDirection input: %s.', list(self.curDirs)); end
      self.currentDirection = curDir;
      self.setParam9;
    end

    function set.waveform(self, wvForm)
      k = key(self.wvForms, wvForm);
      if isempty(k), error('Valid Waveform input: %s.', list(self.wvForms)); end
      self.waveform = wvForm;
      self.setParam9;
    end

    function set.burstPulses(self, nPulse)
      self.burstPulses = nPulse;
      self.setParam9;
    end

    function set.IPI(self, ipi)
      [self.IPI, dev] = closestVal(ipi, self.IPIs);
      if dev>0.001, fprintf(2, 'Actual IPI is %g\n', self.IPI); end
      self.setParam9;
    end

    function set.BARatio(self, ratio)
      [self.BARatio, dev] = closestVal(ratio, 0.2:0.05:5);
      if dev>0.001, fprintf(2, 'Actual BARatio is %g\n', self.BARatio); end
      self.setParam9;
    end

    function set.page(self, page)
      k = key(self.PAGEs, page);
      if isempty(k), error('Valid page input: %s.', list(self.PAGEs)); end
      self.page = page;
      self.write([7 k]);
      self.write([12 0]);
      if ~isequal(self.page, page)
          error('Failed to switch to page: %s', page);
      end
    end

    function set.delays(self, in3)
      in3(1) = closestVal(in3(1), [0:0.1:10 11:100 110:10:6500]);
      in3(2) = closestVal(in3(2), [-100:-10 -9.9:0.1:10 11:100]);
      in3(3) = closestVal(in3(3), [0:10:100 125:25:4000 4050:50:12000]);
      self.delays = in3;
      p16 = uint16([in3(1)*10 typecast(int16(in3(2)*10),'uint16') in3(3)]);
      self.write([10 1 typecast(swapbytes(p16),'uint8')]);
      self.write([10 0]);
    end

    function set.CoilTypeDisplay(self, tf) % set by user only for now
      self.CoilTypeDisplay = tf;
      self.write(0); % update info.CoilType
    end

    function set.train(self, S)
      S0 = self.train;
      d = setdiff(fieldnames(S), fieldnames(S0));
      if ~isempty(d), error('Unknown parameters: %s', strjoin(d, ', ')); end
      if isfield(S, 'TimingControl') && S0.TimingControl ~= S.TimingControl
        k = key(self.TCs, S.TimingControl);
        if isempty(k), error('Valid TimingControl: %s.', list(self.TCs)); end
        self.train.TimingControl = string(S.TimingControl);
      end
      if isfield(S, 'RepRate') && S0.RepRate ~= S.RepRate
        [val, dev] = closestVal(S.RepRate, self.RATEs); % pps
        self.train.RepRate = val;
        if dev>0.001, fprintf(2, 'RepRate adjusted to %g\n', val); end
      end
      if isfield(S, 'PulsesInTrain') && S0.PulsesInTrain ~= S.PulsesInTrain
        [val, dev] = closestVal(S.PulsesInTrain, [1:1000 1100:100:2000]);
        self.train.PulsesInTrain = val;
        if dev>0.001, fprintf(2, 'PulsesInTrain adjusted to %i\n', val); end
      end
      if isfield(S, 'NumberOfTrains') && S0.NumberOfTrains ~= S.NumberOfTrains
        [val, dev] = closestVal(S.NumberOfTrains, 1:500);
        self.train.NumberOfTrains = val;
        if dev>0.001, fprintf(2, 'NumberOfTrains adjusted to %i\n', val); end
      end
      if isfield(S, 'ITI') && S0.ITI ~= S.ITI
        [val, dev] = closestVal(S.ITI, 0.1:0.1:300);
        self.train.ITI = val;
        if dev>0.001, fprintf(2, 'ITI adjusted to %g\n', val); end
      end
      if isfield(S, 'PriorWarningSound')
        self.train.PriorWarningSound = logical(S.PriorWarningSound);
      end
      if isfield(S, 'RampUp') && S0.RampUp ~= S.RampUp
        [val, dev] = closestVal(S.RampUp, 0.7:0.05:1);
        self.train.RampUp = val;
        if dev>0.001, fprintf(2, 'RampUp adjusted to %g\n', val); end
      end
      if isfield(S, 'RampUpTrains') && S0.RampUpTrains ~= S.RampUpTrains
        [val, dev] = closestVal(S.RampUpTrains, 1:10);
        self.train.RampUpTrains = val;
        if dev>0.001, fprintf(2, 'RampUpTrains adjusted to %i\n', val); end
      end
      if isequal(S0, self.train), return; end % possible if partial struct input
      self.page = "Timing"; % save time for fireTrain()
      S = self.train;
      tc = key(self.TCs, S.TimingControl); % +self.ExtendedRepRate*16 % not settable
      b16 = quorem([S.RepRate*10 S.PulsesInTrain S.NumberOfTrains S.ITI*10], 256);
      % control for RampUp/RampUpTrains not working
      self.write([11 1 tc b16 S.PriorWarningSound S.RampUp*100 S.RampUpTrains]);
      self.write([11 0]); % sync
      secs = ((S.PulsesInTrain-1)/S.RepRate + S.ITI) * S.NumberOfTrains - S.ITI;
      self.trainTime = sprintf('%02d:%02d', quorem(ceil(secs), 60));
    end
    
    function resync(self)
      % Update the parameters from stimulator, in case changes at stimulator
      self.write(5); % basic info
      self.write([9 0]); % burst parameters etc
      self.write([10 0]); % delays
      self.write([11 0]); % train
      self.write([12 0]); % page, stimCount
    end

    function disconnect(self)
      % Release the associated serial port, so other app can connect.
      try self.port.delete; end
      try self.delete; end
    end

    function save(self, fName)
      % T.save('./myParams.mat'); % Save parameters to a file for future sessions to load
      if nargin<2 || isempty(fName)
        [pNam, fNam] = fileparts(self.filename);
        [fNam, pNam] = uiputfile('*.mat;*.json', 'Specify a file to save', fullfile(pNam, fNam));
        if isnumeric(fNam), return; end
        fName = fullfile(pNam, fNam);
      end
      for f = self.p2save, S.(f) = self.(f); end
      S.train = self.train;
      if endsWith(lower(fName), ".mat"), save(fName, '-struct', 'S'); return; end
      fid = fopen(fName, 'w'); % .json
      fprintf(fid, '%s', jsonencode(S, 'PrettyPrint', true));
      fclose(fid);
    end

    function load(self, fName)
      % T.load('./myParams.mat'); % Load parameters from .mat/.CG3/.json file to stimuluator
      if nargin<2 || isempty(fName)
        [fNam, pNam] = uigetfile('*.CG3;*.mat;*.json', 'Select a file to load');
        if isnumeric(fNam), return; end
        fName = fullfile(pNam, fNam);
      end
      self.skipWrite = true;
      if endsWith(upper(fName), '.CG3')
        ch = regexp(fileread(fName), '\[protocol Line \d', 'split');
        getval = @(k)str2double(regexp(ch{1},"(?<="+k+"=)\d+",'match','once'));
        self.mode = val(self.MODEs, getval('Mode'));
        self.currentDirection = val(self.curDirs, getval('Current Direction'));
        self.waveform = val(self.wvForms, getval('Wave Form'));
        try self.burstPulses = getval('Burst Pulses'); end % may be 0 if not used
        self.IPI = getval('Inter Pulse Interval')/10;
        self.BARatio = getval('Pulse BA Ratio')/100;
        self.delays = getval({'Delay Input Trig' 'Delay Output Trig' 'Charge Delay'}) ./ [10 10 1];
        self.CoilTypeDisplay = getval('Coil Type Display');
        S = struct('train', struct);
        S.train.TimingControl = val(self.TCs, getval('Timing Control'));
        S.train.RepRate = getval('Rep Rate')/10;
        S.train.PulsesInTrain = getval('Pulses in train');
        S.train.NumberOfTrains = getval('Number of Trains');
        S.train.ITI = getval('Inter Train Interval')/10;
        S.train.PriorWarningSound = getval('Prior Warning Sound');
        S.train.RampUp = getval('RampUp')/100;
        S.train.RampUpTrains = getval('RampUpTrains');
        % self.AutoDischargeTime = getval('Auto Discharge Time'); % 5 / 10
        % self.TrigOutput = getval('Trig Output'); % 1, Enable/Disable
        % self.TwinTrigOutput = getval('Twin Trig output'); % 0, Pulse A/B/A+B
        % self.TwinTrigInput = getval('Twin Trig Input'); % 0, Pulse A/A+B
        % self.PolarityInput = getval('Polarity Input'); % 0, Falling/Rising Edge
        % self.PolarityOutput = getval('Polarity output'); % 0
        % self.protocol = struct;
        % for i = 1:numel(ch)-1
        %   getval = @(k)str2double(regexp(ch{i+1},"(?<="+k+"=)\d+",'match','once'));
        %   self.protocol(i).Delay = getval('Delay'); % ms
        %   self.protocol(i).AmplitudeAGain = getval('Amplitude A Gain')/10;
        %   self.protocol(i).mode = val(self.MODEs, getval('Mode'));
        %   self.protocol(i).currentDirection = val(self.curDirs, getval('Current Direction'));
        %   self.protocol(i).waveform = val(self.wvForms, getval('Wave Form'));
        %   self.protocol(i).burstPulses = getval('Burst Pulses');
        %   self.protocol(i).IPI = getval('Inter Pulse Interval')/10;
        %   self.protocol(i).BARatio = getval('BA Ratio')/100;
        %   self.protocol(i).RepRate = getval('Repetition Rate')/10;
        %   self.protocol(i).PulsesInTrain = getval('Train Pulses'); % set NumberOfTrains=1?
        % end
      elseif endsWith(lower(fName), [".mat" ".json"])
        if endsWith(lower(fName), ".mat"),  S = load(fName);
        else, S = jsondecode(fileread(fName));
        end
        if ~isfield(S, 'IPI'), error('Invalid parameter file'); end
        for f = self.p2save, self.(f) = S.(f); end
      else, error('Unsupported file type');
      end
      self.filename = fName;
      self.skipWrite = false;
      self.setParam9;
      self.delays = self.delays + 1e-6;
      self.train = S.train;
      self.resync;
      if exist('TMS_GUI', 'file')==2, TMS_GUI('update'); end
    end
  end

  methods (Hidden)
    function write(self, bytes)
      % fprintf('Sent%s\n', sprintf(' %02X', bytes)); % for debug
      if self.skipWrite, return; end
      bytes = [254 numel(bytes) bytes CRC8(bytes) 255];
      try self.port.write(bytes, 'uint8'); end %#ok<*TRYNC> % quiet if fail
    end

    function setParam9(self) % Shortcut to set parameters via commandID=9
      b9 = zeros(1, 9, 'uint8');
      b9(1) = key(self.MODELs, self.Model);
      b9(2) = key(self.MODEs, self.mode);
      b9(3) = key(self.curDirs, self.currentDirection);
      b9(4) = key(self.wvForms, self.waveform);
      b9(5) = 5 - self.burstPulses;
      b9(6:7) = quorem(self.IPI*10, 256);
      b9(8:9) = quorem(self.BARatio*100, 256);
      self.write([9 1 b9]);
      self.write([9 0]); % sync
    end

    function read(self) % Update parameters from stimulator: 8+ bytes callback
      n = 0;
      while 1
        pause(0.05);
        n1 = self.port.NumBytesAvailable;
        if n==n1, break; else, n = n1;  end
      end
      if n<8, return; end
      self.skipWrite = true; % update properties without sending to stimulator
      byts = self.port.read(n, 'uint8');
      i0 = find(byts==254);
      WvForms = ["Monophasic" "Biphasic" "Halfsine" "Biphasic Burst"];
      for i = 1:numel(i0)
        try b = byts(i0(i):i0(i)+byts(i0(i)+1)+3); catch, continue; end
        % valid packet: [254 numel(b)-4 b(3:end-2) CRC8(b(3:end-2)) 255]
        if b(end)~=255 || b(end-1)~=CRC8(b(3:end-2))
          fprintf(2, 'Corrupted data?\n'); disp(b); continue;
        end
        % fprintf('    %s\n', sprintf(' %02X', b(3:end-2))); % for debug
        if b(3)==0 || b(3)==5
          bit2i = @(i)bitget(b(4),i)*2.^(0:numel(i)-1)';
          self.mode = val(self.MODEs, bit2i(1:2));
          self.waveform = WvForms(1+bit2i(3:4));
          self.enabled = bit2i(5);
          self.Model = val(self.MODELs, bit2i(6:8));
          self.info.SerialNo = b(5:7)*256.^[2 1 0]';
          self.temperature = b(8);
          self.setCoilType(b(9));
          self.amplitude = b(10:11);
          if b(3)==5 % Localite sends 5 twice a second
            % amplitudeOriginal = b(12:13);
            % self.protocol(1).AmplitudeAGain = b(14)/100;
            % self.page = val(self.PAGEs, b(16)); % not reliable for some
            self.trainRunning = b(17);
          end
        elseif any(b(3)==[1:3 6:8])
          if b(3)==1 % amplitude & enable/disable
            self.amplitude = b(4:5);
          elseif b(3)==2 % fire pulse/train/protocol
            self.didt = b(4:5);
          elseif b(3)==3 % enable/disable
            self.temperature = b(4);
            self.setCoilType(b(5));
          elseif b(3)==6 % only at Protocol page
            fprintf('amplitudeOriginal = %i %i\n', b(4:5));
          elseif b(3)==7 % only at Protocol page
            fprintf('protocol.AmplitudeAGain = %g %g\n', b(4:5)/100);
          elseif b(3)==8 % page change & train stim
            self.page = val(self.PAGEs, b(4));
            self.trainRunning = b(5);
          end
          bit2i = @(i)bitget(b(6),i)*2.^(0:numel(i)-1)';
          self.mode = val(self.MODEs, bit2i(1:2));
          self.waveform = WvForms(1+bit2i(3:4));
          self.enabled = bit2i(5);
          % self.Model = val(self.MODELs, bit2i(6:8));
        elseif b(3)==4
          self.MEP.maxAmplitude = b(4:7)*256.^(3:-1:0)'; % in µV
          self.MEP.minAmplitude = b(8:11)*256.^(3:-1:0)';
          self.MEP.maxTime = b(12:15)*256.^(3:-1:0)'; % in µs
        elseif b(3)==9 % basic param
          % self.Model = val(self.MODELs, b(5));
          self.mode = val(self.MODEs, b(6));
          self.currentDirection = val(self.curDirs, b(7));
          self.waveform = WvForms(1+b(8));
          self.burstPulses = 5 - b(9);
          if self.waveform=="Biphasic Burst", self.IPI = self.IPIs(b(11)*256+b(10)+1); end
          if self.mode=="Twin", self.BARatio = 5 - b(12)*0.05; end
        elseif b(3)==10 % delay
          outDelay = double(typecast(uint8(b([8 7])), 'int16')) / 10; % signed
          self.delays = [b(5:6)*[256 1]'/10 outDelay b(9:10)*[256 1]'];
        elseif b(3)==11 % Timing menu params
          S.TimingControl = val(self.TCs, rem(b(5),4));
          S.RepRate = b(6:7)*[256 1]'/10;
          S.PulsesInTrain = b(8:9)*[256 1]';
          S.NumberOfTrains = b(10:11)*[256 1]';
          S.ITI = b(12:13)*[256 1]'/10;
          S.PriorWarningSound = b(14);
          S.RampUp = b(15)/100;
          S.RampUpTrains = b(16);
          self.train = S; % assign once
          self.ExRate = bitget(b(5), 5);
        elseif b(3)==12
          % self.train.NumberOfTrains = b(4:5)*[256 1]';
          % b(7:9)*256.^[2 1 0]': PulsesInTrain * NumberOfTrains
          self.info.stimCount = b(12:13)*[256 1]'; % b(10:11) too?
          self.page = val(self.PAGEs, b(16));
        else, fprintf(2, 'Unknown b(3)=%s\n', num2str(b(3:end-2))); % 240,241
        end
      end
      self.skipWrite = false;
      if exist('TMS_GUI', 'file')==2, TMS_GUI('update'); end
    end

    function setCoilType(self, k)
      if ~self.CoilTypeDisplay, coil = "Hidden";
      elseif k==60, coil = "Cool-B65";
      elseif k==72, coil = "C-B60";
      % elseif k==72, coil = ""; % add more pairs
      else, coil = string(k);
      end
      self.info.CoilType = coil;
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
    function delete(varargin); delete@handle(varargin{:}); end
  end
end

function qr = quorem(nums, div)
  % Return quotient and remainder [q r q r ...] for scalar div
  qr = [fix(nums(:)'/div); rem(nums(:)',div)];
  qr = qr(:)';
end

function rst = CRC8(bytes)
  % Compute CRC8 (Dallas/Maxim) checksum for polynomial x^8 + x^5 + x^4 + 1
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
  vals = round(vals, 2); % 2 decimal digits enough for all parameters
  [dev, id] = min(abs(val-vals));
  dev = dev / abs(val); % ratio
  val = vals(id);
end

function d = dict(vals, keys)
  % struct working with early Matlab without dictionary
  if nargin<2, keys = 0:numel(vals)-1; end % default 0:n-1
  d = struct('keys', uint8(keys), 'values', vals); % uint8 & string array
end
function v = val(d, key), v = d.values(key == d.keys); end
function k = key(d, val), k = d.keys(val == d.values); end
function L = list(d), L = '"'+join(d.values, '", "')+'"'; end
