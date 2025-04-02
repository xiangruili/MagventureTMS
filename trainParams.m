classdef trainParams
  % A struct-like variable to store TMS train parameters
  properties
    % Number of pulses per second in each train
    RepRate(1,1) = 1

    % Number of pulses or bursts in each train
    PulsesInTrain(1,1) = 5

    % Number of Trains in the sequence
    NumberOfTrains(1,1) = 2

    % Inter Train Interval in seconds
    ITI(1,1) = 1

    % Control if a sound warning is presented 2 seconds before each train
    PriorWarningSound(1,1) logical

    % A factor 0.7-1.0 setting the level for the first Train
    RampUp(1,1) = 1

    % The number of trains during which the Ramp up function is active
    RampUpTrains(1,1) = 10

    % Indicate if train sequence is running
    isRunning(1,1) logical
  end

  properties (Dependent)
    % Total time to run the sequence, based on train parameters
    TotalTime(1,1) string
  end

  methods
    function tf = isfield(obj, nam) % works as struct
      tf = isprop(obj, nam);
    end

    function dur = get.TotalTime(obj)
      s = ((obj.PulsesInTrain-1)/obj.RepRate+obj.ITI)*obj.NumberOfTrains-obj.ITI;
      dur = string(duration(0, 0, s, "Format", "mm:ss"));
    end
  end
end
