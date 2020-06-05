function eulerianmagnify (inputFileName, alpha, lowerBoundFrequency, upperBoundFrequency)
tic
addpath('./matlabPyrTools');
addpath('./matlabPyrTools/MEX');

%Read the given video
disp("Reading the video");
vidReader = VideoReader(inputFileName);
videoAsFrames = vidReader.read;
videoLength = size(videoAsFrames,4);
videoWidth = size(videoAsFrames,2);
videoHeigth = size(videoAsFrames,1);
frameRate = vidReader.FrameRate;
disp("Reading finished")
%Making sure the path to write out is correct
vidWriter = VideoWriter(strcat(strrep(inputFileName,'.','_'),'ResultEulerian_','alpha_', num2str(alpha), '_freqlow_', num2str(lowerBoundFrequency), '_freqhigh_', num2str(upperBoundFrequency), '.avi'));

%Because of memory issues we create a reference frame first and then create
%the other pyramids in a for loop. We store indices only once since all the
%pyramids will be build with the same values.
disp("Converting reference frame to NTSC")
videoYIQ = rgb2ntsc(videoAsFrames(:,:,:,1));
%Splitting up the frame in luminance and Chrominance
videoLumRef = squeeze(videoYIQ(:,:,1));
videoChromIRef = squeeze(videoYIQ(:,:,2));
videoChromQRef = squeeze(videoYIQ(:,:,3));
disp("Conversion finished")
disp("Calculating the reference pyramid and its angles");
[referencePyramidLum,indices] = buildLpyr(videoLumRef,'auto');
referencePyramidChromI = buildLpyr(videoChromIRef,'auto');
referencePyramidChromQ = buildLpyr(videoChromQRef,'auto');
disp("Reference pyramid calculated");

%Create the first pyramid for an first order IIR filter. 
lowpassedPyramid(:,:,1) = referencePyramidLum;
lowpassedPyramid(:,:,2) = referencePyramidChromI;
lowpassedPyramid(:,:,3) = referencePyramidChromQ;

upperPassedPyramid(:,:,1) = referencePyramidLum;
upperPassedPyramid(:,:,2) = referencePyramidChromI;
upperPassedPyramid(:,:,3) = referencePyramidChromQ;

%The for loop creates a laplacian pyramid for each of the frames, magnifies
%motion and recreates the frame
for currentFrame=2:videoLength
    if mod(currentFrame,10) == 0
        disp(strcat("Processing of frame: ", num2str(currentFrame), " out of: ",num2str(videoLength)));
    end
    %Create YIQ variant of movie;
    videoYIQ = rgb2ntsc(videoAsFrames(:,:,:,currentFrame));
    %Splitting up the frame in luminance and Chrominance
    videoLum = squeeze(videoYIQ(:,:,1));
    videoChromI = squeeze(videoYIQ(:,:,2));
    videoChromQ = squeeze(videoYIQ(:,:,3));

    %Creating the laplacian pyramid fo the frame
    currentPyramidLum = buildLpyr(videoLum,'auto');
    currentPyramidChromI = buildLpyr(videoChromI,'auto');
    currentPyramidChromQ = buildLpyr(videoChromQ,'auto');
    
    currentPyramid(:,:,1) = currentPyramidLum;
    currentPyramid(:,:,2) = currentPyramidChromI;
    currentPyramid(:,:,3) = currentPyramidChromQ;
    
    %We use a standard IIR filter to filter to get the bandpass
    lowpassedPyramid = (1-lowerBoundFrequency)*lowpassedPyramid + lowerBoundFrequency*currentPyramid;
    upperPassedPyramid = (1-upperBoundFrequency)*upperPassedPyramid + upperBoundFrequency*currentPyramid;

    %Simply said all frequencies below the upper frequency minus all the
    %frequencies below the lower frequency gives us the bandpass. 
    filteredPyramid = (upperPassedPyramid - lowpassedPyramid);
    
    %In its simplest form according to equation 4 of the paper, we can
    %simply amplify the bandpassed signal and add it to the original.
    amplifiedPyramid = alpha .* filteredPyramid;
    %We do not amplify the lowest layer of the pyramid to make sure that
    %less noise is amplified.
    amplifiedPyramid(1:(indices(1,1) * indices(1,2))) = 0;
    currentPyramid = currentPyramid + amplifiedPyramid;
    
    %Use the inverse laplacian pyramid 
    reconstructedFrameLum = reconLpyr(currentPyramid(:,:,1), indices);
    reconstructedFrameChromI = reconLpyr(currentPyramid(:,:,2), indices);
    reconstructedFrameChromQ = reconLpyr(currentPyramid(:,:,3), indices);
    
    reconstructedFrame(:,:,1) = reconstructedFrameLum;
    reconstructedFrame(:,:,2) = reconstructedFrameChromI;
    reconstructedFrame(:,:,3) = reconstructedFrameChromQ;
    
    rgbFrame = ntsc2rgb(reconstructedFrame);
    %During writing to the video we use the old video again to overwrite
    %the new frames. This makes the whole process a bit less memory
    %consuming.
    videoAsFrames(:,:,:,currentFrame) = im2uint8(rgbFrame);
end
%We do not attempt denoise of the reconstruction.

%write out the video to same location with Result and parameters behind it
disp("Writing Video")
vidWriter.open;
vidWriter.writeVideo(videoAsFrames)
vidWriter.close;
disp("Finished process")
toc
end
