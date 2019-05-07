%Clear the workspace to start the program 
close all
clear
clc

%% TO DO
% - Wheel calibration
% - Write docs for initializeBotState, sendInitialState, sendInstruction
% - Make a config file for all settings instead of hard-coding them

%% Variables in this code that are affected by variables in the Arduino code
% time_step (in EKF) should be the same as movementDuration in the 'duino 
% code 
% pingBeaconDelay is dependent on BEACON_TIMEOUT_THRESHOLD in the 'duino
% code

%% RUNTIME PARAMETERS
% Recompiles pingBeacon.c on the RPi once during setup. Do this if you have
% made changes to pingBeacon.c
recompilePingBeaconCode = false;
enableDebuggingRPi = false; 
% Enable debugging for this script and related functions
debug = true;
% Max x and y coordinates of the grid in meters
MAX_X = 5.12;
MAX_Y = 5.12;
% END RUNTIME PARAMETERS

%% OLD LOCALIZATION SETUP (remove or revise, not functional)
%rpi = raspi('130.15.101.192','pi','swep2018');      % New RPi 3
%rpi = raspi('130.15.101.119','pi','apsc200');      % Old RPi 1
% Where the relevant files for firing the beacons are stored on the RPi
%pingBeaconPath = '/home/pi/Desktop/apsc200devRPi';
% IR and US GPIO pins on the RPi for each beacon. 
% For beacon #i, beaconGPIO(i) = [IR_PIN_i, US_PIN_i];
%beaconGPIO = [17, 27; 
%               10,  9;
%               19, 26;
%               25,  8; 
%               20, 21];     


% EKF setup
% Beacon information
% beaconLocations = [1.5,0; 0.5,0; 0,0.5; 1.5,0; 2.5,0];   % [x1,y1;x2,y2,...]
% Initial error covariance matrix
% errorCovMat = 1*eye(3,3);   % [3x3] since the state is of dimension 3 

% localizeThisIteration = true;
% pingBeaconDelay = 1.5; 
% % Recompile the pingBeacon.c code on the RPi if necessary
% if (recompilePingBeaconCode)
%     pingBeaconRecompile(pingBeaconPath, enableDebuggingRPi);
% end
% END OLD LOCALIZATION SETUP

%% XBEE SETUP
% Set up the Xbee connection
xbeeSerial = serial('COM8','Terminator','CR', 'Timeout', 2);
% END XBEE SETUP

%% BOT SETUP
% Call the initializeBotState to get list of bots being worked with, and
% their states
[position, tagString, heading] = initializeBotState(MAX_X, MAX_Y);
% Send initial positions to bots
sendInitialState(xbeeSerial, position, tagString, heading);

%% WHEEL CALIBRATION
%See if the user wants to calibrate the robots wheels
calibrate = input('Would you like to calibrate the wheels (y/n)? ', 's');
if (calibrate == 'Y' || calibrate == 'y')
    fopen(xbeeSerial);
    fwrite(xbeeSerial,'C');
    fwrite(xbeeSerial,'C');
    fwrite(xbeeSerial,'C');
    fclose(xbeeSerial);
    for i=1:length(bots)
        [leftInputSlope, leftInputIntercept, rightInputSlope, rightInputIntercept]...
            = WheelCalibration(xbeeSerial, bots(i), botTagLower(i));
    end
else
    leftInputSlope = 13;
    leftInputIntercept = 90;
    rightInputSlope = 13;
    rightInputIntercept = 90;
end
% END WHEEL CALIBRATION

%% 
%Create Sensor and Position variables for each robot
position = zeros(length(bots), 3);
oldPosition = position;
% Estimate/predict next position (depending on if we localize or not)
[position, errorCovMat] = PositionCalc(botTagLower, beaconLocations,...
    errorCovMat, xbeeSerial, rpi, localizeThisIteration, beaconGPIO,...
    pingBeaconPath, pingBeaconDelay, debug, oldPosition);

nextPosition = getNextPosition(algorithm, bots, position);
error = zeros(3*length(bots),1);


exitCounter = 0;
index = 1;

%% Main loop
while (true) 
    localizeThisIteration = true;
    %see if any of the robots are its next position
    for i= 1:length(bots)
        check = checkPosition(position(i,:),nextPosition(i,:));
        if(check == true)
            nextPosition = getNextPosition(algorithm, bots, position);
        end
        %check to see if the robot's new position is its current position
        check = checkPosition(position(i,:),nextPosition(i,:));
        if(check == true)
            exitCounter = exitCounter + 1;
        end
    end
    
    %if all of the new positions match the robots' old position, exit the
    %program
    if(exitCounter == length(bots))
        break;
    end

    %%%%%CONTROL SECTION%%%%%
    % Determine motor inputs based off of controller 
  
    AdjustPosition(xbeeSerial, bots, position, ...
        nextPosition, index, error, leftInputSlope, leftInputIntercept, ...
        rightInputSlope, rightInputIntercept);


    % start all the robots to start moving after giving them motor inputs
    fopen(xbeeSerial);
    fwrite(xbeeSerial, '1');
    fclose(xbeeSerial);

    %%%%%NAVIGATION AND ESTIMATION SECTION%%%%%        
    %calculate the new position of the robot
    oldPosition = position;
    [position, errorCovMat] = PositionCalc(botTagLower, beaconLocations, ...
        errorCovMat, xbeeSerial, rpi, localizeThisIteration, beaconGPIO, ...
        pingBeaconPath, pingBeaconDelay, debug, oldPosition);
    
    index = index + 1;

end

disp("All robots should be optimally arranged.");
