function motorThreshold(startAmp)
% Start to measure motor threshold.
%  The optional input is the start amplitude for the threshold estimation. If
%  not provided, the current amplitude on the stimulator will be used if it is
%  greater than 30, otherwise 65 will be the starting amplitude.
% 
% When asked if you see motor response, click "Yes" or "No" (or key press y or
% n), and the amplitude will be adjusted accordingly for the next trial. In case
% you are unsure for a response, or the stimulation target needs to be adjusted,
% click "Retry" (or key press r) to keep the amplitude unchanged for the next
% trial. The code will set the default choice based on the trace, and you can
% press Spacebar if the default choice is correct.
% 
% When the estimate converges, the protocol will stop, and threshold will be
% shown on the title of the figure, as well as in Command Window.
% 
% Closing the figure will stop the test.

% 250330 v1 by Xiangrui.Li at gmail.com

T = TMS;
if nargin>1
    amp = startAmp;
else
    amp = T.amplitude(1);
    if amp<30, amp = 65; end
end
T.enabled = true;
step = 4; btn0 = ''; i = 1;

RTBoxADCd('flush');
[y, ms] = RTBoxADCd('read'); % 288 samples (80 ms) at 3600Hz
iBase = ms>50; iResp = ms>20 & ms<50;

fh = figure(77); clf;
res = get(0, 'ScreenSize');
set(fh, 'Position', [40 res(4)-440 1200 400],  'Name', 'Motor Threshold Test', ...
    'ToolBar', 'none', 'MenuBar', 'none', 'NumberTitle', 'off', 'Resize', 'off', ...
    'Color', 'w', 'WindowKeyPressFcn', @key_cb);
ax = axes(fh, "Position", [0.05 0.15 0.82 0.7], 'Box', 'off');
h = plot(ax, ms, bandpass(y)); h.LineWidth = 1;
xlim([-5 80]); xlabel('ms'); xticks(0:10:80); 
ylim([-1 1]*3); 
ax.YAxis.Visible = 'off';
ax.Box = 'off';
hold on; plot(ax, -5*[1 1], [0.8 1.8], '-k', 'LineWidth', 2); text(-4.5, 1.3, '1mV');
mouse_cb = @(o,~) set(fh, 'UserData', o.String);
p = [fh.Position(3)-72 fh.Position(4)-120 48 24];
hs(4) = uicontrol(fh, 'Style', 'text', 'string', 'Motor Response?', 'FontSize', 10,  ...
    'Position', [p(1)-56 p(2) p(3)+72 p(4)], 'BackgroundColor','w', 'HorizontalAlignment',  'right');
p(2) = p(2) - 50; hs(1) = uicontrol(fh, 'Style', 'pushbutton', 'Position', p, 'Callback', mouse_cb, 'string', 'Yes');
p(2) = p(2) - 50; hs(2) = uicontrol(fh, 'Style', 'pushbutton', 'Position', p, 'Callback', mouse_cb, 'string', 'No');
p(2) = p(2) - 50; hs(3) = uicontrol(fh, 'Style', 'pushbutton', 'Position', p, 'Callback', mouse_cb, 'string', 'Retry');
set(hs, 'Visible', 'off');

while 1
    T.amplitude = amp;
    pause(2+rand*2);
    T.firePulse;

    y = RTBoxADCd('read');
    y(33:end) = bandpass(y(33:end)); % leave trigger artifact
    try h.YData = y; drawnow; catch, return; end

    ratio = std(y(iResp)) / std(y(iBase));
    if ratio>3, dft = 1;
    elseif i<2, dft = 3;
    elseif ratio<1.2, dft = 2;
    else, dft = 3;
    end
    fh.UserData = '';
    set(hs, 'Visible', 'on');
    figure(fh); uicontrol(hs(dft)); drawnow;
    while isvalid(fh) && isempty(fh.UserData), pause(0.1); end
    if ~isvalid(fh)
        fprintf(2, 'Motor threshold test stopped.\n');
        return;
    end
    set(hs, 'Visible', 'off');
    btn = fh.UserData;
    if btn=="Retry", continue; end
    if btn=="Yes"
        if step<1, thre = amp;   break; else, amp = amp - step; end
    elseif btn=="No"
        if step<1, thre = amp+1; break; else, amp = amp + step; end
    end
    if ~isempty(btn0) && ~isequal(btn, btn0), step = step-1; end
    fprintf(" Trial %2i: amp=%2i, response=%s\n", i, T.amplitude(1), btn);
    btn0 = btn; i = i + 1;
end
title(ax, sprintf(" Motor threshold is %i\n", thre));

function y = bandpass(y)
n = numel(y);
y = fft(y);
i = round([5 500]/3600*n + 1);
y([1:i(1) i(2):n+2-i(2) n+2-i(1):n]) = 0;
y = real(ifft(y));

function key_cb(fh, evt)
if     evt.Key == "y", fh.UserData = "Yes";
elseif evt.Key == "n", fh.UserData = "No";
elseif evt.Key == "r", fh.UserData = "Retry";
end
