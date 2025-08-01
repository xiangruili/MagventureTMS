function varargout = RTBoxADCd(cmd)
% Simple version of RTBoxADC to do one-shot of differential 288 samples or oscilliscope.
% The signal input are DB25 pin 1 and 2 for RTBox v5 and higher.
% Sampling rate: 3600; gain: 200.
% 
% RTBoxADCd; % Show trace in oscilliscope if no input argument
% RTBoxADCd('start'); % start 288-sample ADC conversion and return immediately
% vol = RTBoxADCd('read'); % start conversion, wait and return 288 samples

% 250727 Xiangrui.Li at gmail.com (write it using MATLAB serialport)

persistent s CLN
if isempty(s)
    for port = serialportlist('available')
        try p = serialport(port, 115200, 'Timeout', 0.3); catch, continue; end
        p.write('R', 'char'); % in case in ADC
        p.write('X', 'char'); pause(0.1);
        if p.NumBytesAvailable>20, break; else, delete(p); end
    end
    if ~exist('p', 'var') || ~isvalid(p)
        error(' Failed to find valid RTBox.');
    else
        b = p.read(21, "char");
        if ~contains(b, ["v5" "v6"])
            error(' RTBoxADCd works only for RTBox version 5 and above.');
        end
    end
    p.write('G', 'char') % jump into ADC function
    p.write([67 75], 'uint8'); pause(0.1) % differential ADC1-ADC0 gain=200, vref=5
    % p.write([70 2]); pause(0.1) % rate=3600, default
    p.write([110 1 32], 'uint8'); % 3600*0.08 = 288 samples

    s = p;
    CLN = onCleanup(@()delete(p));
end

if nargout>1, varargout{2} = (0:287)/3.6; end % time in ms
if nargin<1 % osciliiscope
    fh = figure(3); clf;
    res = get(0, 'ScreenSize');
    set(fh, 'Position', [40 res(4)-440 1200 400],  'Name', 'RTBox ADC', 'Resize', 'off', ...
        'ToolBar', 'none', 'MenuBar', 'none', 'NumberTitle', 'off');
    t = (1:7200)/3600;
    h = plot(t, zeros(1,7200));
    ylim([-1 1]*5); yticks([]); xlabel("Seconds")
    hold on; plot([1 1]*0.05, [3.6 4.6], '-k', 'LineWidth', 2); text(0.06, 4.1, '1mV');
    s.UserData = h;
    configureCallback(s, "byte", 5, @updateScope);
    s.flush();
    s.write(2, 'uint8');
elseif cmd == "start" % Start conversion
    s.write(2, 'uint8');
elseif cmd == "flush"
    n = s.NumBytesAvailable;
    while 1
        n1 = s.NumBytesAvailable;
        if n1 == n, break; else, n = n1; pause(0.02); end
    end
    s.flush();
elseif cmd == "read"
    s.write(2, 'uint8'); % Start conversion
    pause(0.08);
    for i = 1:4
        if s.NumBytesAvailable<360, pause(0.02);
        else, break;
        end
    end
    N = floor(s.NumBytesAvailable/5) * 5;
    b = s.read(N, 'uint8');
    varargout{1} = byte2vol(b);
else
    error("Unknown input for RTBoxADCd")
end


%% callback when NumBytesAvailable>5
function updateScope(s, ~)
persistent i count
if isempty(i), i = 0; count = 0; end
if ~isvalid(s.UserData) % figure closed
    configureCallback(s, "off");
    i = 0; count = 0;
    return;
end
N = floor(s.NumBytesAvailable/5);
if N<1, return; end
b = s.read(N*5, 'uint8');
N = N * 4;
count = count + N;
if count>=288, s.write(2, 'uint8'); count = 0; end % start conversion again
vol = byte2vol(b);
ind = (1:N) + i;
ind = mod(ind-1, 7200) + 1;
s.UserData.YData(ind) = vol;
i = ind(end);


%% bytes (multiple of 5) to mV conversion
function vol = byte2vol(b)
b = reshape(b, 5, []);
vol = bitand(b(5,:), [3 12 48 192]') .* [256 64 16 4]';
vol = vol + b(1:4, :);
vol = vol(:);
vol(vol>511) = vol(vol>511)-1024;
vol = vol/20.48; % mV: 1000/200*2/1024*5
