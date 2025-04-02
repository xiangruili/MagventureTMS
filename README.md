# Magventure TMS Control from Matlab (version 2025.04.01)
[![View xiangruili/dicm2nii on File Exchange](https://www.mathworks.com/matlabcentral/images/matlab-file-exchange.svg)](https://www.mathworks.com/matlabcentral/fileexchange/180628-magventuretms)
[![Open in MATLAB Online](https://www.mathworks.com/images/responsive/global/open-in-matlab-online.svg)](https://matlab.mathworks.com/open/github/v1?repo=xiangruili/MagventureTMS)

# TMS
Object-oriented code to fully control the Magventure TMS.
This requires the serial port connection between TMS stimulator and the host computer. 
A USB to serrial adaptor is needed if the computer has no built-in serial port.

# TMS_GUI
GUI to control Magventure stimulator using TMS.m object.

# motorThreshold
Estimate motor threshold using TMS.m object. Also serve as a code example to control the stimulator.
This requires RTBox (https://github.com/xiangruili/RTBox), which needs
 Psychtoolbox (http://psychtoolbox.org/), for the ADC part. One may replace
 the ADC part with other ADC toolbox, so avoid the dependence.
