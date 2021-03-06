function [intervals,representations] = CalibrationviaEmbodiedMemory_cogsci(inputtype, perceptualnoise, locationinvariant, memorynoise, networknoise,showcolumnsgraph)
% example of a neural network implementation of Embodied Memory model of
% time perception.
%
% The basic idea is in a mature system the time interval since an event 
% is derived from of how blurry (some aspect of) the memory for
% the perceptual event has become. An immature system calibrates this
% mechanism using the predictable and repeatable signals from physical
% movements. These obey Fitt's law which is a direct analogue of the Scalar
% Property in interval timing. 
% In this version, a network is 1st trained to predict the length of an 
% interval from 1 distribution. Input is distribution of activations along
% a 1d vector and output is a log-scale counter (aka ATOM representation)
% 
% Caspar Addyman 2010
% caspar@onemonkey.org
% version 01 - 26 Sep 2010
% version 02 - 16 Dec 2010
% version 03 - 23 Jan 2011 - calibration version

clear all;
close all;

ANALYTIC_GAUSSIAN = 0;
FADING_GAUSSIAN = 1;

% Default settings
if nargin < 1, inputtype = 1; end   %what shape is input function
if nargin < 2, perceptualnoise = false; end         %is initial percept noisy    
if nargin < 3, locationinvariant = true; end        %is percept centred on input field?
if nargin < 4, memorynoise = true; end             %is memory representation noisy
if nargin < 5, networknoise  = true; end           %internal network noise
if nargin < 6, showcolumnsgraph = false; end         %show graph of results
if nargin < 7, showerrorsgraph = true; end         %show graph of results
if nargin < 8, trackdevelopment = true; end        %make note of weights at intervvals during learning     

includephasetwo = true;
phasecount = 2;

nBabies = 20;
NEpochs = 1;
NTrainingItems = 7000;
LearningRate = 0.02;
momentum = 0.001;

minInterval = 1; %1 second
maxInterval = 90; %90 seconds 
nHidNodes = 10;
inputWidth = 41;    %how wide is input vector?
outputWidth = 10;   %how wide is output vector

if networknoise
    networknoiserate = 0.06;
else
    networknoiserate = 0;
end
OutputLoopSize = 20; %used for finding mean & std of network outputs

%  
if memorynoise
    %two types
    %fixed amounts of noise added to all input nodes
    memorynoise_fixed_mean = 0.05;            
    memorynoise_fixed_sd = 0.02;             
    
    %relative noise, sd is proportional to activation
    memorynoise_proportional_sd = 0.03;       %added to all input nodes
end


%%%%%%%%%%%%%%%%%%% INPUTS %%%%%%%%%%%%%%%%%%%%%%%%
% what type of input (& test) distribution do we have? 
%
% we claim that memory is normal distribution that decays analogously to Fitt's law.
% so if width of stdev after K seconds is W, after 2K seconds it will be 2W
% therefore we need to specify a scale for both

modality{1}.inputType = inputtype;
modality{1}.inputWidth = inputWidth;
modality{1}.minInterval = minInterval;  
modality{1}.maxInterval = maxInterval; 
modality{1}.numIntervals = 33; 
modality{1}.memorywidthunit = 5; % W
modality{1}.memorytimeunit =20; % K  
modality{1}.Amplitude = 10;
modality{1}.spread_factor =  0.0045; % visual
modality{1}.leakage_factor = 0.0105;
modality{1}.self_excitation = 0.001;
modality{1}.lognormalIntervals = false; 
modality{1}.UseBODYMapRepresentation = true;
modality{1}.UseBODYbinaryout = true;

[modality{1}.Intervals, modality{1}.MemoryCurves] = getFadingGaussians(modality{1});
modality{1}.ATOMOutputs = ATOMrepresentation(modality{1}.Intervals',outputWidth,minInterval, maxInterval);
modality{1}.BODYOutputs = BODYMapRepresentation(modality{1}.Intervals',outputWidth,minInterval, maxInterval,false,modality{1}.UseBODYbinaryout);

%for the moment the second modality is same as first (but it really doesn't
%have to be)
modality{2} = modality{1};
modality{2}.memorywidthunit = 3.8; % W
modality{2}.memorytimeunit =12; % K  
modality{2}.spread_factor =  0.0048;
modality{2}.leakage_factor = 0.0105;
modality{2}.self_excitation = 0.001;
[modality{2}.Intervals, modality{2}.MemoryCurves] = getFadingGaussians(modality{2});
modality{2}.ATOMOutputs = ATOMrepresentation(modality{2}.Intervals',outputWidth,minInterval, maxInterval);
modality{2}.BODYOutputs = BODYMapRepresentation(modality{2}.Intervals',outputWidth,minInterval, maxInterval,false,modality{2}.UseBODYbinaryout);


%%%%%%%%% SIMULATE N Babies %%%%%%%%%%%%%%%%%%%%%%
% so we can average performance
Baby = cell(nBabies,1);
for babycounter = 1:nBabies

%%%%%%%%% PHASE 1 : PRE - TRAINING %%%%%%%%%%%%%%%%%%%%%%%
% learn to transform gaussian input in one modality into ATOM-like output 
% using back-propogation
% 
% nothing from second modality at this stage


% sample random intervals in the approriate range (1 to 90s).
% perhaps these ought to have a poisson distribution but don't at the moment
% can just randomly sample from the rows of allPossibleIntervals
Baby{babycounter}.Phase{1}.rows = randi([modality{1}.numIntervals],NTrainingItems,1);
Baby{babycounter}.Phase{1}.MemoryInputs = modality{1}.MemoryCurves(Baby{babycounter}.Phase{1}.rows, :);
Baby{babycounter}.Phase{1}.ATOMOutputs = modality{1}.ATOMOutputs(Baby{babycounter}.Phase{1}.rows,:);
Baby{babycounter}.Phase{1}.BODYOutputs = modality{1}.BODYOutputs(Baby{babycounter}.Phase{1}.rows,:);

if memorynoise
    [R,C] = size(Baby{babycounter}.Phase{1}.MemoryInputs);
    Baby{babycounter}.Phase{1}.NoisyInputs = Baby{babycounter}.Phase{1}.MemoryInputs + ...
                          memorynoise_proportional_sd * Baby{babycounter}.Phase{1}.MemoryInputs .* randn(R,C);
    Baby{babycounter}.Phase{1}.NoisyInputs = Baby{babycounter}.Phase{1}.NoisyInputs + ... 
                          memorynoise_fixed_mean + memorynoise_fixed_sd * rand(R,C);
else
    Baby{babycounter}.Phase{1}.NoisyInputs = Baby{babycounter}.Phase{1}.MemoryInputs;
end

if modality{1}.UseBODYMapRepresentation
%     [Baby{babycounter}.Phase{1}.wt1 Baby{babycounter}.Phase{1}.wt2] = local_srn(Baby{babycounter}.Phase{1}.NoisyInputs,Baby{babycounter}.Phase{1}.BODYOutputs,nHidNodes,LearningRate,NEpochs,1,networknoiserate, momentum, 1,trackdevelopment);     
    [Baby{babycounter}.Phase{1}.wt1 Baby{babycounter}.Phase{1}.wt2] = backprop(Baby{babycounter}.Phase{1}.NoisyInputs,Baby{babycounter}.Phase{1}.BODYOutputs,nHidNodes,LearningRate,NEpochs,networknoiserate, momentum, 1,trackdevelopment);
 else
%   [Baby{babycounter}.Phase{1}.wt1 Baby{babycounter}.Phase{1}.wt2] = local_srn(Baby{babycounter}.Phase{1}.NoisyInputs,Baby{babycounter}.Phase{1}.BODYOutputs,nHidNodes,LearningRate,NEpochs,1,networknoiserate, momentum, 1,trackdevelopment);     
   [Baby{babycounter}.Phase{1}.wt1 Baby{babycounter}.Phase{1}.wt2] = backprop(Baby{babycounter}.Phase{1}.NoisyInputs,Baby{babycounter}.Phase{1}.ATOMOutputs,nHidNodes,LearningRate,NEpochs,networknoiserate, momentum, 1,trackdevelopment);
end
% 
% %record the final weights
% wt1 = Baby{babycounter}.Phase{1}.wt1{NEpochs};
% wt2 = Baby{babycounter}.Phase{1}.wt2{NEpochs};
% save('trainedweights1.mat', 'wt1', 'wt2');


for devstage = 1:NEpochs
    % now get set of representative outputs from our our trained network
    % present each of the possible curves and see network prediction 
    % do this multiple times to get the prediction error (i.e. scalar property)   
    [R,C] = size(modality{1}.MemoryCurves);
    for k = 1:OutputLoopSize
        if memorynoise
            modality{1}.NoisyInputs = modality{1}.MemoryCurves + ...
                                  memorynoise_proportional_sd * modality{1}.MemoryCurves .* randn(R,C);
                              
            modality{1}.NoisyInputs = modality{1}.NoisyInputs + ... 
                                  memorynoise_fixed_mean + memorynoise_fixed_sd * rand(R,C);
        else
            modality{1}.NoisyInputs = modality{1}.MemoryCurves;        
        end
%         Baby{babycounter}.Phase{1}.TrainedOutputs{devstage}{k} = local_srn_out(modality{1}.NoisyInputs,Baby{babycounter}.Phase{1}.wt1{devstage},Baby{babycounter}.Phase{1}.wt2{devstage},1,networknoiserate);
        Baby{babycounter}.Phase{1}.TrainedOutputs{devstage}{k} = backprop_out(modality{1}.NoisyInputs,Baby{babycounter}.Phase{1}.wt1{devstage},Baby{babycounter}.Phase{1}.wt2{devstage},networknoiserate);
        if modality{1}.UseBODYMapRepresentation
            Baby{babycounter}.Phase{1}.TrainedOutTimes{devstage}(k,:) = BODYMapRepresentation(Baby{babycounter}.Phase{1}.TrainedOutputs{devstage}{k},outputWidth,minInterval, maxInterval,true,modality{1}.UseBODYbinaryout );
        else
            Baby{babycounter}.Phase{1}.TrainedOutTimes{devstage}(k,:) = ATOMrepresentation(Baby{babycounter}.Phase{1}.TrainedOutputs{devstage}{k},outputWidth,minInterval, maxInterval,true);    
        end
    end
    Baby{babycounter}.Phase{1}.MeanOutput{devstage} = mean(Baby{babycounter}.Phase{1}.TrainedOutTimes{devstage}, 1);
    Baby{babycounter}.Phase{1}.StdDevOutput{devstage} = std(Baby{babycounter}.Phase{1}.TrainedOutTimes{devstage}  - ones(OutputLoopSize,1) * modality{1}.Intervals, 1);

    Baby{babycounter}.Phase{1}.RelScalarErrors{devstage} = Baby{babycounter}.Phase{1}.StdDevOutput{devstage} ./ Baby{babycounter}.Phase{1}.MeanOutput{devstage};
    Baby{babycounter}.Phase{1}.AbsScalarErrors{devstage} = Baby{babycounter}.Phase{1}.StdDevOutput{devstage} ./ modality{1}.Intervals;
end


if includephasetwo
    %%%%%%%%%% PHASE 2 - CALIBRATING ANOTHER MODALITY IN SAME WAY %%%%%%
    % this time train second network to transform second modality
    % using the equivalent outputs of the first network as the training signal
    %  
    % in this version we train just on the end of each event.
    Baby{babycounter}.Phase{2}.rows = randi([modality{2}.numIntervals],NTrainingItems,1);
    Baby{babycounter}.Phase{2}.MemoryInputs = modality{2}.MemoryCurves(Baby{babycounter}.Phase{2}.rows, :);
    Baby{babycounter}.Phase{2}.ATOMOutputs = modality{2}.ATOMOutputs(Baby{babycounter}.Phase{2}.rows,:);
    Baby{babycounter}.Phase{2}.BODYOutputs = modality{2}.BODYOutputs(Baby{babycounter}.Phase{2}.rows,:);

    if memorynoise
        [R,C] = size(Baby{babycounter}.Phase{2}.MemoryInputs);
        Baby{babycounter}.Phase{2}.NoisyInputs = Baby{babycounter}.Phase{2}.MemoryInputs + ...
                              memorynoise_proportional_sd * Baby{babycounter}.Phase{2}.MemoryInputs .* randn(R,C);
        Baby{babycounter}.Phase{2}.NoisyInputs = Baby{babycounter}.Phase{2}.NoisyInputs + ... 
                              memorynoise_fixed_mean + memorynoise_fixed_sd * rand(R,C);
    else
        Baby{babycounter}.Phase{2}.NoisyInputs = Baby{babycounter}.Phase{2}.MemoryInputs;
    end
    
    if modality{2}.UseBODYMapRepresentation
        [Baby{babycounter}.Phase{2}.wt1 Baby{babycounter}.Phase{2}.wt2] = local_srn(Baby{babycounter}.Phase{2}.NoisyInputs,Baby{babycounter}.Phase{2}.BODYOutputs,nHidNodes,LearningRate,NEpochs,1,networknoiserate, momentum, 1,trackdevelopment);
    else
        [Baby{babycounter}.Phase{2}.wt1 Baby{babycounter}.Phase{2}.wt2] = local_srn(Baby{babycounter}.Phase{2}.NoisyInputs,Baby{babycounter}.Phase{2}.ATOMOutputs,nHidNodes,LearningRate,NEpochs,1,networknoiserate, momentum, 1,trackdevelopment);
    end
    
    %record the final weights
    wt1 = Baby{babycounter}.Phase{1}.wt1{NEpochs};
    wt2 = Baby{babycounter}.Phase{1}.wt2{NEpochs};
    save('trainedweights2.mat', 'wt1', 'wt2');


    for devstage=1:NEpochs
        % now get set of representative outputs from our our trained network
        % present each of the possible curves and see network prediction 
        % do this multiple times to get the prediction error (i.e. scalar property)   
        [R,C] = size(modality{2}.MemoryCurves);
        for k = 1:OutputLoopSize
            if memorynoise
                modality{2}.NoisyInputs = modality{2}.MemoryCurves + ...
                                      memorynoise_proportional_sd * modality{2}.MemoryCurves .* randn(R,C);
                modality{2}.NoisyInputs = modality{2}.NoisyInputs + ... 
                                      memorynoise_fixed_mean + memorynoise_fixed_sd * rand(R,C);
            else
                modality{2}.NoisyInputs = modality{2}.MemoryCurves;        
            end
            Baby{babycounter}.Phase{2}.TrainedOutputs{devstage}{k} = local_srn_out(modality{2}.NoisyInputs,Baby{babycounter}.Phase{2}.wt1{devstage},Baby{babycounter}.Phase{2}.wt2{devstage},1,networknoiserate);
            if modality{2}.UseBODYMapRepresentation
                Baby{babycounter}.Phase{2}.TrainedOutTimes{devstage}(k,:) = BODYMapRepresentation(Baby{babycounter}.Phase{2}.TrainedOutputs{devstage}{k},outputWidth,minInterval, maxInterval,true,modality{2}.UseBODYbinaryout);    
            else
                Baby{babycounter}.Phase{2}.TrainedOutTimes{devstage}(k,:) = ATOMrepresentation(Baby{babycounter}.Phase{2}.TrainedOutputs{devstage}{k},outputWidth,minInterval, maxInterval,true);    
            end
        end
        Baby{babycounter}.Phase{2}.MeanOutput{devstage} = mean(Baby{babycounter}.Phase{2}.TrainedOutTimes{devstage}, 1);
        Baby{babycounter}.Phase{2}.StdDevOutput{devstage} = std(Baby{babycounter}.Phase{2}.TrainedOutTimes{devstage}  - ones(OutputLoopSize,1) * modality{2}.Intervals, 1);

        Baby{babycounter}.Phase{2}.RelScalarErrors{devstage} = Baby{babycounter}.Phase{2}.StdDevOutput{devstage} ./ Baby{babycounter}.Phase{2}.MeanOutput{devstage};
        Baby{babycounter}.Phase{2}.AbsScalarErrors{devstage} = Baby{babycounter}.Phase{2}.StdDevOutput{devstage} ./ modality{2}.Intervals;
    end
end

end %baby loop


%%%%%%%%%% DISPLAY THE RESULTS %%%%%%%%%%%%%%%%%%%%%%%%%

% first get the average baby for each time and each stage of development
% there might be a more elegant way of doing this
% but this way i can understand what i am doing!
for babycounter = 1:nBabies
    for ph = 1:phasecount
        for devstage = 1:NEpochs
            AllOutTimes{ph}{devstage}(babycounter,:) = Baby{babycounter}.Phase{ph}.TrainedOutTimes{devstage}(1,:);
            AllMeanTimes{ph}{devstage}(babycounter,:) = Baby{babycounter}.Phase{ph}.MeanOutput{devstage};
            AllMeanErrors{ph}{devstage}(babycounter,:) = Baby{babycounter}.Phase{2}.StdDevOutput{devstage};
            AllRelErrors{ph}{devstage}(babycounter,:) = Baby{babycounter}.Phase{2}.RelScalarErrors{devstage};
            AllAbsErrors{ph}{devstage}(babycounter,:) = Baby{babycounter}.Phase{2}.AbsScalarErrors{devstage};
        end
    end
end
for devstage = 1:NEpochs   
    GlobalOutTimes{devstage} = mean(AllOutTimes{1}{devstage},1);
    GlobalMeanTimes{devstage} = mean(AllMeanTimes{1}{devstage},1);
    GlobalMeanErrors{devstage} = mean(AllMeanErrors{1}{devstage},1);
    GlobalRelErrors{devstage} = mean(AllRelErrors{1}{devstage},1);
    GlobalAbsErrors{devstage} = mean(AllAbsErrors{1}{devstage},1);
end


if showcolumnsgraph 
   %graph showing the inputs and outputs for representative set of time
   %intervals
   fig = figure(0);
   babycounter = nBabies; % just show last run
   for ph = 1:phasecount
        
    %First graph things after learning first modality
    for t = 1:modality{ph}.numIntervals
        
        set(fig, 'Name',  ['Phase' num2str(ph) ' - Input Time  t= ' num2str(t)]);
        
        %The guassian distributions input on this phase
        subplot(2,2,ph);
        axis([0 modality{ph}.inputWidth + 1 0 1.1]);
        bar(1:modality{ph}.inputWidth, modality{ph}.MemoryCurves(t,:));
        xlim([0 modality{ph}.inputWidth + 1]);
        ylim([0 1.1]);
        xlabel('Input Columns');
        ylabel('Activation');
        title(['Input modality {' num2str(ph) '}' ]);
        
        %The guassian distribution that is input.
        subplot(2,2,3-ph);
        axis([0 modality{2}.inputWidth + 1 0 1.1]);
        bar(1:modality{2}.inputWidth, zeros(1, modality{2}.inputWidth) );
        xlim([0 modality{2}.inputWidth + 1]);
        ylim([0 1.1]);
        xlabel('Input Columns');
        ylabel('Activation');
        title(['Input modality {' num2str(3-ph) '}' ]);

        %The output representation from the network
        subplot(2,2,3)
        axis([0 outputWidth + 1 0 1.1]);
        if modality{2}.UseBODYMapRepresentation
            bar(1:outputWidth, modality{1}.BODYOutputs(t,:));
        else
            bar(1:outputWidth, modality{1}.ATOMOutputs(t,:));
        end
        xlim([0 outputWidth + 1]);
        ylim([0  1.1]);
        xlabel('Output Columns');
        ylabel('Activation');
        title('Expected out');
        
        
        %The output representation from the network
        subplot(2,2,4)
        axis([0 outputWidth + 1 0 1.1]);
        bar(1:outputWidth, Baby{babycounter}.Phase{ph}.TrainedOutputs{NEpochs}{1}(t,:));
        xlim([0 outputWidth + 1]);
        ylim([0  1.1]);
        xlabel('Output Columns');
        ylabel('Activation');
        title('Network out');
     
        
         pause(0.2);
    end
   end
end


if showerrorsgraph

    if trackdevelopment %check network performance after each Epoch
        n = 1;
        
        figure(3);
        for ph = 1:2
            subplot(2,2,(ph-1)*2 +1);
            axis([0 maxInterval 0 maxInterval * 1.2]);
            xlabel('Time Interval /seconds');
            ylabel('Prediction /seconds');
            xlim([0  maxInterval]);
            ylim([0  maxInterval]);
            hold on;
            plot(modality{ph}.Intervals, modality{ph}.Intervals); 
            for devstage = 1:NEpochs
                plot(modality{ph}.Intervals, Baby{babycounter}.Phase{ph}.MeanOutput{devstage});             
            end
            hold off;

            subplot(2,2,(ph-1)*2+2);
            axis([0 maxInterval 0  1.2]);
            xlabel('Time Interval /seconds');
            ylabel('Prediction /seconds');
            xlim([0  maxInterval]);
            ylim([0   1.2]);
            title('Average output Errors');
            hold on;
            for devstage = 1:NEpochs
                plot(modality{ph}.Intervals,  Baby{babycounter}.Phase{ph}.AbsScalarErrors{devstage}, ':+g');
            end
           hold off;
        end
    end

    %results showing subplot 1,1 as a single figure for the paper 
    figure(5); 
    axis([0 maxInterval 0 maxInterval * 1.2]);
    xlabel('Time Interval / seconds');
    ylabel('Prediction / seconds');
    xlim([0  maxInterval]);
    ylim([0  maxInterval]);
    hold on;
    plot(modality{ph}.Intervals, modality{ph}.Intervals); 
    for devstage = 1:NEpochs
        plot(modality{ph}.Intervals, GlobalMeanTimes{devstage});             
    end
    hold off;
    
    %plot final performance with error bars.
    figure(2);
    
    for ph= 1:2
        subplot(2,2,(ph-1)*2 +1);
        axis([0 maxInterval 0 maxInterval * 1.2]);
        xlabel('Time Interval /seconds');
        ylabel('Prediction /seconds');
        xlim([0  maxInterval]);
        ylim([0  maxInterval]);
        plot(modality{ph}.Intervals, modality{ph}.Intervals); 
        errorbar(modality{ph}.Intervals, Baby{babycounter}.Phase{ph}.MeanOutput{NEpochs}, 0.5* Baby{babycounter}.Phase{1}.StdDevOutput{NEpochs});

        subplot(2,2,(ph-1)*2 +2);
        axis([0 maxInterval 0  1.2]);
        xlabel('Time Interval /seconds');
        ylabel('Prediction /seconds');
        xlim([0  maxInterval]);
        ylim([0   1.2]);
        hold on;
        plot(modality{ph}.Intervals, Baby{babycounter}.Phase{ph}.RelScalarErrors{NEpochs}, ':+r');
        plot(modality{ph}.Intervals,  Baby{babycounter}.Phase{ph}.AbsScalarErrors{NEpochs}, ':*g');

        title('Scaled output errors');
        hold off;
    end
    
    
    %results for modality as single figure for the paper
    
    figure(6);
    axis([0 maxInterval 0 maxInterval * 1.2]);
    xlabel('Time Interval /seconds');
    ylabel('Prediction /seconds');
    xlim([0  maxInterval]);
    ylim([0  maxInterval]);
    hold on;
    line(modality{ph}.Intervals, modality{ph}.Intervals); 
%     errorbar(modality{ph}.Intervals, GlobalMeanTimes{NEpochs}, GlobalMeanErrors{NEpochs});
    errorbar(modality{ph}.Intervals, Baby{babycounter}.Phase{ph}.MeanOutput{NEpochs}, Baby{babycounter}.Phase{1}.StdDevOutput{NEpochs});
    ax1 = gca;

    xlimits = get(ax1,'XLim');
    ylimits = get(ax1,'YLim');
    xinc = (xlimits(2)-xlimits(1))/5;
    yinc = (ylimits(2)-ylimits(1))/5;
    set(ax1,'XTick',[xlimits(1):xinc:xlimits(2)],...
        'YTick',[ylimits(1):yinc:ylimits(2)])
    
    ax2 = axes('Position',get(ax1,'Position'), ...
            'XAxisLocation','top',...
           'YAxisLocation','right',...
           'Color','none',...
           'XColor','w','YColor','k');
    set(ax2,'XTick',[xlimits(1):xinc:xlimits(2)],...
        'YTick',[0:0.2:1])
     ylabel(ax2, 'Error as proportion of interval');
%     set(get(ax2,'Ylabel'),'String','Fast Decay') 
    xlim(ax2, [0  maxInterval]);
    ylim(ax2, [0 1]);
%     line(modality{ph}.Intervals, GlobalRelErrors{NEpochs}, 'Color', 'r', 'Parent', ax2);
    line(modality{ph}.Intervals, Baby{babycounter}.Phase{ph}.RelScalarErrors{NEpochs}, 'Color', 'r', 'Parent', ax2);
    hold off;
end

if phasecount == 2
    for n=1:NEpochs
        rhomatrix = corrcoef(Baby{babycounter}.Phase{1}.TrainedOutTimes{n}(1,:)',Baby{babycounter}.Phase{2}.TrainedOutTimes{n}(1,:)');
        rho(n) = rhomatrix(1,2);
    end

    figure(4);
    TrainingSteps = NTrainingItems:NTrainingItems:NEpochs*NTrainingItems;
    plot(TrainingSteps, rho);
    xlabel('Training Items');
    ylabel('Correlation');
end