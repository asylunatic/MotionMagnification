function feestbeest (inputFileName, alpha, orientations, lowerBoundFrequency, upperBoundFrequency)
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
vidWriter = VideoWriter(strcat(strrep(inputFileName,'.','_'),'ResultPhase_','alpha_', num2str(alpha), '_orients_', num2str(orientations+1), '_freqlow_', num2str(lowerBoundFrequency), '_freqhigh_', num2str(upperBoundFrequency), '.avi'));

%calculate the max height of the pyramid given the up/downsample factor,
%calculated from the smallest frame width/height and the log of 2. A
%reduction of two is taken because of the pyramid toolbox having this as a
%maximum heigth. 
maxPyramidHeigth = floor(log2(min(size(videoAsFrames,1), size(videoAsFrames,2)))) - 2;
%The number of orientations is 0 based in the pyramidtoolbox, therefore the
%number is lowered by 1.
orientations = orientations-1;
%lastly the TWIDTH is The width of the transition region of the radial
%lowpass function, in octaves, normally set to 1.
twidth = 1;

%Because of memory issues we create a reference frame and its angles etc
%first and then create the other pyramids in a for loop. We store indices
%only once since all the pyramids will be build with the same values.
disp("Converting reference frame to NTSC")
videoYIQ = rgb2ntsc(videoAsFrames(:,:,:,1));
%Splitting up the frame in luminance and Chrominance
videoLumRef = squeeze(videoYIQ(:,:,1));
%We only use the luminance and the first frame stays the same and thus we
%don't get the chrominance channels
%videoChromI = squeeze(videoYIQ(:,:,2));
%videoChromQ = squeeze(videoYIQ(:,:,3));
%disp("Conversion finished")
disp("Calculating the reference pyramid and its angles");
[referencePyramid, indices] = buildSCFpyr(videoLumRef, maxPyramidHeigth, orientations, twidth);
angleReferenceFrame = angle(referencePyramid);
%disp("Reference pyramid and its angles calculated");

%The for loop creates a complex steerable pyramid for each of the frames.
for currentFrame=2:videoLength
    disp(strcat("Current frame: ", num2str(currentFrame), 'out of ', num2str(videoLength)));
    %Create YIQ variant of movie;
    %disp("Converting to NTSC")
    videoYIQ = rgb2ntsc(videoAsFrames(:,:,:,currentFrame));
    %disp("Conversion finished")
    %Splitting up the frame in luminance and Chrominance
    videoLum = squeeze(videoYIQ(:,:,1));
    videoChromI = squeeze(videoYIQ(:,:,2));
    videoChromQ = squeeze(videoYIQ(:,:,3));
    %disp("Creating steerable pyramid and calculating its angles");
    currentFrameSteerablePyramid = buildSCFpyr(videoLum, maxPyramidHeigth, orientations, twidth);
    
    %First we use the steerable pyramids to get the phase angles for each frame.
    currentFrameAngles = angle(currentFrameSteerablePyramid);

    
    %The code below is to visualize parts of the pyramids
    %refPyramid = steerablePyramid(:,1);
    %figure(1); showSpyr(real(refPyramid), indices(:,:,1));
    %figure(2); showSpyr(imag(refPyramid), indices(:,:,1));
    %figure(3); showSpyr(angle(refPyramid), indices(:,:,1));
    %figure(4); showSpyr(abs(refPyramid), indices(:,:,1)); %magnitude

    %Then we calculate the difference between the reference frame and the other
    %frames and store that in delta. Possibly use single for speedup?
    %disp("Calculating delta (difference in phase between reference and current frame)");
    currentdelta = mod(pi+currentFrameAngles - angleReferenceFrame,2*pi)-pi;
    
    %put the angle difference into the fourier domain to apply a filter.
    %disp("Bandpassing delta to only include interesting frequencies")
    fourierAngleDomain = fft2(currentdelta);
    
    %Get only the bandpass which is important for us. Since the Fourier domain
    %consists of the difference of the angles decomposed into their respective
    %Fourier frequencies. Now we have the change in movement as a frequency and
    %thus we can conclude that all movement below our lower threshold and above
    %our upper threshold can be discarded since it is not in our interest. For
    %example when we expect a heart beat movement to be between 0.5Hz (1 beat per 
    %two seconds) and 2Hz (2 beats per second) every response difference in the
    %Fourier Domain below and above those frequencies respectively can be
    %discarded. We create a simple finite impulse response filter for the
    %selected frequency bands. 

    FIRFilter = fir1(1, [lowerBoundFrequency/frameRate , upperBoundFrequency/frameRate]);

    %Note we do not shift the filter since we didn't see any reasons to, while
    %the authors of the original paper did fourier shift it. Furthermore, we
    %hold both the real and imaginary part of the fourier domain while the
    %authors discard the imaginary part. 
    filteredFourierDomain = fourierAngleDomain .* fft(FIRFilter(1));

    %After the application of the filter we do the inverse fourier transform to
    %get the filtered angle movement of the video. After that we magnify it by
    %alpha. 
    filteredAngle = ifft2(filteredFourierDomain);
    %disp("Bandpassing completed")
    
    %disp("Magnifying the difference between the reference and the current frame")
    magnifiedAngle = alpha * filteredAngle;
    magnificationExponent = exp(1i*magnifiedAngle);
    adjustedPyramid = magnificationExponent.* currentFrameSteerablePyramid;
    %disp("Reconstructing the frame")
    reconstructedFrameLum = reconSCFpyr(adjustedPyramid, indices, 'all', 'all', twidth);
    reconstructedFrame(:,:,1) = reconstructedFrameLum;
    reconstructedFrame(:,:,2) = videoChromI;
    reconstructedFrame(:,:,3) = videoChromQ;
    %disp("Conversion back to RGB from ntsc")
    rgbFrame = ntsc2rgb(reconstructedFrame);
    %During writing to the video we use the old video again to overwrite
    %the new frames. This makes the whole process a bit less memory
    %consuming.
    videoAsFrames(:,:,:,currentFrame) = im2uint8(rgbFrame);
end

disp("Completed the magnification and reconstruction")

%We do not attempt denoise of the reconstruction.

%write out the video to same location with Result and parameters behind it
disp("Writing Video")
vidWriter.open;
vidWriter.writeVideo(videoAsFrames)
vidWriter.close;
disp("Finished process")
toc
end
