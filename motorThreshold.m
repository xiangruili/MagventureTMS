function motorThreshold(startAmp)
% Start to measure motor threshold.
%  The optional input is the start amplitude for the threshold estimation. If
%  not provided, the current amplitude on the stimluator will be used if it is
%  greater than 30, otherwise 60 will be the start amplitude.
% 
% When the popup window asks if motor response is seen, click "Yes" or "No", and
% the amplitude will be adjusted accordingly for next trial. In case it is
% unsure if there is a response, or the stimulation target needs to be adjusted,
% click "Retry" to keep the amplitude unchanged for next trial. The code will
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
    if amp<30, amp = 60; end
end
T.enable;
step = 4; btn0 = ''; i = 1;

clear RTBoxADC;
dur = 0.08;
RTBoxADC('duration', dur);
RTBoxADC('channel', 'dif', 200);
RTBoxADC('Start'); pause(dur+0.05);
[y, t] = RTBoxADC('read');
iBase = t>0.05; iResp = t>0.02 & t<0.05;

figure(77); clf;
res = get(0, 'ScreenSize');
set(gcf, 'Position', [40 res(4)-440 1200 400],  'Name', 'Motor Threshold', ...
  'ToolBar', 'none', 'MenuBar', 'none', 'NumberTitle', 'off');
h = plot(t*1000, y);
ms = dur*1000; xlim([-5 ms]); xlabel('ms'); xticks(0:10:ms); 
ylim([-1 1]*3); yticks([]);
hold on; plot(-4*[1 1], [0.8 1.8], '-k', 'LineWidth', 2); text(-3, 1.3, '1mV');

while 1
    T.setAmplitude(amp);
    pause(2+rand*2);
    T.firePulse;

    RTBoxADC('Start'); pause(dur+0.05);
    y = detrend(RTBoxADC('read') * 1000);
    figure(77); h.YData = y; drawnow;

    ratio = std(y(iResp)) / std(y(iBase));
    if ratio>3, def = "Yes";
    elseif i<2, def = "Retry";
    elseif ratio<1.2, def = "No";
    else, def = "Retry";
    end
    btn = questdlg("See motor response?", "Question", "Yes", "No", "Retry", def);
    if isempty(btn)
        fprintf(2, 'Motor threshold test stopped.\n');
        return;
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
title(h.Parent, sprintf(" Motor threshold is %i\n", thre));
