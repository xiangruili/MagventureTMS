function motorThreshold(startAmp)
% Start to measure motor threshold.
%  The optional input is the start amplitude for the threshold estimation. If
%  not provided, the current amplitude on the stimulator will be used if it is
%  greater than 30, otherwise 65 will be the starting amplitude.
% 
% When the popup dialog asks if you see motor response, click "Yes" or "No", and
% the amplitude will be adjusted accordingly for the next trial. In case you are
% unsure if there is a response, or the stimulation target needs to be adjusted,
% click "Retry" to keep the amplitude unchanged for the next trial. The code will
% set the default choice based on the trace, and you can press Enter key if the
% default choice is correct.
% 
% When the estimate converges, the protocol will stop, and threshold will be
% shown on the title of the figure.
% 
% Closing the dialog will stop the test.

% 250330 v1 by Xiangrui.Li@gmail.com

T = TMS;
if nargin>1
    amp = startAmp;
else
    amp = T.amplitude(1);
    if amp<30, amp = 65; end
end
T.enabled = true;
step = 4; btn0 = ''; i = 1;

clear RTBoxADC;
dur = 0.08;
RTBoxADC('duration', dur);
RTBoxADC('channel', 'dif', 200);
RTBoxADC('Start'); pause(dur+0.05);
[y, t] = RTBoxADC('read');
iSig = t>0.01; iBase = t>0.05; iResp = t>0.02 & t<0.05;

figure(77); clf;
res = get(0, 'ScreenSize');
set(gcf, 'Position', [40 res(4)-440 1200 400],  'Name', 'Motor Threshold', ...
  'ToolBar', 'none', 'MenuBar', 'none', 'NumberTitle', 'off');
h = plot(t*1000, y); h.LineWidth = 1;
ms = dur*1000; xlim([-5 ms]); xlabel('ms'); xticks(0:10:ms); 
ylim([-1 1]*3); yticks([]);
hold on; plot(-4*[1 1], [0.8 1.8], '-k', 'LineWidth', 2); text(-3, 1.3, '1mV');

while 1
    T.amplitude = amp;
    pause(2+rand*2);
    T.firePulse;

    RTBoxADC('Start'); pause(dur+0.05);
    y = detrend(RTBoxADC('read') * 1000);
    y(iSig) = bandpass(y(iSig), [5 500], 3600); % leave trigger artifact
    figure(77); h.YData = y; drawnow;

    ratio = std(y(iResp)) / std(y(iBase));
    if ratio>3, def = "Yes";
    elseif i<2, def = "Retry";
    elseif ratio<1.2, def = "No";
    else, def = "Retry";
    end
    btn = questdlg("See motor response?", "Question", "Yes", "No", "Retry", def);
    if isempty(btn)
        break;
    elseif btn=="Retry"
        continue;
    elseif btn=="Yes"
        if step<1, thre = amp;   break; else, amp = amp - step; end
    elseif btn=="No"
        if step<1, thre = amp+1; break; else, amp = amp + step; end
    end
    if ~isempty(btn0) && ~isequal(btn, btn0), step = step-1; end
    fprintf(" Trial %2i: amp=%2i, response=%s\n", i, T.amplitude(1), btn);
    btn0 = btn; i = i + 1;
end
if isempty(btn), fprintf(2, 'Motor threshold test stopped.\n');
else, title(h.Parent, sprintf(" Motor threshold is %i\n", thre));
end

function x = bandpass(x, band, fs)
% Apply bandpass filter to signal x (row or column vector).
% The band input is [hp lp] in Hz, and fs is sampling rate in Hz
%  y = bandpass(x, [5 500], fs); % hp=5Hz, lp=500Hz
%  y = bandpass(x, [0 500], fs); % lowpass only
%  y = bandpass(x, [5 inf], fs); % highpass only

n = numel(x);
x = fft(x);
i = round(band/fs*n + 1);
x([1:i(1) n+2-i(1):n]) = 0; % always remove mean: cufoff too steep? 
if i(2)>1 && i(2)<n, x(i(2):n+2-i(2)) = 0; end
x = real(ifft(x));