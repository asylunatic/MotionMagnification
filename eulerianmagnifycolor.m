function eulerianmagnifycolor (inputFileName, alpha, lowerBoundFrequency, upperBoundFrequency)
tic
addpath('./matlabPyrTools');
addpath('./matlabPyrTools/MEX');

%Read the given video
vidReader = VideoReader(inputFileName);
videoAsFrames = vidReader.read;
videoLength = size(videoAsFrames,4);
videoWidth = size(videoAsFrames,2);
videoHeight = size(videoAsFrames,1);
frameRate = vidReader.FrameRate;
%Making sure the path to write out is correct
vidWriter = VideoWriter(strcat(strrep(inputFileName,'.','_'),'ResultEulerian_','alpha_', num2str(alpha), '_freqlow_', num2str(lowerBoundFrequency), '_freqhigh_', num2str(upperBoundFrequency), '.avi'));

%Because we need the height indices for the gaussian pyramid, we use the
%first frame as reference frame to get the information from it.
videoYIQ = rgb2ntsc(videoAsFrames(:,:,:,1));
%Splitting up the frame in luminance and Chrominance
videoLumRef = squeeze(videoYIQ(:,:,1));
videoChromIRef = squeeze(videoYIQ(:,:,2));
videoChromQRef = squeeze(videoYIQ(:,:,3));

%Because the gaussian pyramid has a specific height we are calculating this
%maximum height over here. 
maxPyramidHeight = floor(log2(min(size(videoAsFrames,1), size(videoAsFrames,2))))-3;

%Calculating the indices
[referencePyramidLum,indices] = buildGpyr(videoLumRef,maxPyramidHeight, 'binom5');

%This for loop creates the bounds and sizes of the pyramid so we can use
%that in the Gaussian pyramid at a later stage. 
lowIndexHighestPyramid = 1;
highestLevel = size(indices,1);
for i =1:size(indices,1)
    highIndexHighestPyramid = lowIndexHighestPyramid -1 + (indices(i, 1) * indices(i,2));
    if i ~= size(indices,1)
        lowIndexHighestPyramid = highIndexHighestPyramid +1;
    end
end



%The for loop creates a Gaussian pyramid for each of the frames.
for currentFrame=1:videoLength
    if mod(currentFrame,10) == 0
        disp(strcat("Creating Gaussian pyramid of frame: ", num2str(currentFrame), " out of: ",num2str(videoLength)));
    end
    %Create YIQ variant of movie;
    videoYIQ = rgb2ntsc(videoAsFrames(:,:,:,currentFrame));
    %Splitting up the frame in luminance and Chrominance
    videoLum = squeeze(videoYIQ(:,:,1));
    videoChromI = squeeze(videoYIQ(:,:,2));
    videoChromQ = squeeze(videoYIQ(:,:,3));
    currentPyramidLum = buildGpyr(videoLum,maxPyramidHeight, 'binom5');
    currentPyramidChromI = buildGpyr(videoChromI,maxPyramidHeight, 'binom5');
    currentPyramidChromQ = buildGpyr(videoChromQ,maxPyramidHeight, 'binom5');
    
    currentgaussPyramid(:,:,1) = currentPyramidLum;
    currentgaussPyramid(:,:,2) = currentPyramidChromI;
    currentgaussPyramid(:,:,3) = currentPyramidChromQ;
        
    %Use the highest level of the gaussian pyramid. 
    gaussianSmallestFrameLum = currentgaussPyramid(lowIndexHighestPyramid:highIndexHighestPyramid,:,1);
    gaussianSmallestFrameLum = reshape(gaussianSmallestFrameLum, indices(highestLevel, 1), indices(highestLevel,2));
    gaussianSmallestFrameChromI = currentgaussPyramid(lowIndexHighestPyramid:highIndexHighestPyramid,:,2);
    gaussianSmallestFrameChromI = reshape(gaussianSmallestFrameChromI, indices(highestLevel, 1), indices(highestLevel,2));
    gaussianSmallestFrameChromQ = currentgaussPyramid(lowIndexHighestPyramid:highIndexHighestPyramid,:,3);
    gaussianSmallestFrameChromQ = reshape(gaussianSmallestFrameChromQ, indices(highestLevel, 1), indices(highestLevel,2));

    %write to an variable to filter as next step
    gaussianVideo(currentFrame,:,:,1) = gaussianSmallestFrameLum';
    gaussianVideo(currentFrame,:,:,2) = gaussianSmallestFrameChromI';
    gaussianVideo(currentFrame,:,:,3) = gaussianSmallestFrameChromQ';
end

%Creating the Frequency domain and the bandpassmask for this frequency
%domain.
disp("Filtering the Gaussian video")
frequency = 1:videoLength;
frequency = (frequency-1)/videoLength*frameRate;
bandpassMask = frequency > lowerBoundFrequency & frequency < upperBoundFrequency;
gaussVideoHeight = size(gaussianVideo,3);
gaussVideoWidth =size(gaussianVideo,2);
bandpassMask = repmat(transpose(bandpassMask), [1, gaussVideoWidth, gaussVideoHeight, 3]);

frequencyDomain = fft(gaussianVideo, [], 1);
%Applying the bandpassMask to the frequency domain to filter out
%frequencies.
frequencyDomain(~bandpassMask) = 0;
filteredGaussVideo = ifft(frequencyDomain, [], 1);

%Magnify the channel changes
disp("Magnify the different channel changes");
magnifiedGaussVideo = alpha .* real(filteredGaussVideo);

for currentFrame = 1 : videoLength
    if mod(currentFrame,10) == 0
        disp(strcat("Creating reconstruction of frame: ", num2str(currentFrame), " out of: ",num2str(videoLength)));
    end
    filteredNewFrame(:,:,1) = transpose(imresize(squeeze(magnifiedGaussVideo(currentFrame,:,:,1)),[videoWidth, videoHeight]));
    filteredNewFrame(:,:,2) = transpose(imresize(squeeze(magnifiedGaussVideo(currentFrame,:,:,2)),[videoWidth, videoHeight]));
    filteredNewFrame(:,:,3) = transpose(imresize(squeeze(magnifiedGaussVideo(currentFrame,:,:,3)),[videoWidth, videoHeight]));
    frameYIQ = rgb2ntsc(videoAsFrames(:,:,:,currentFrame));
    reconstructedFrame = frameYIQ + filteredNewFrame;
    rgbFrame = ntsc2rgb(reconstructedFrame);
    %During writing to the video we use the old video again to overwrite
    %the new frames. This makes the whole process a bit less memory
    %consuming.
    videoAsFrames(:,:,:,currentFrame) = im2uint8(rgbFrame);
end
%We do not attempt denoise of the reconstruction.
disp("Finished magnification and reconstruction");

%write out the video to same location with Result and parameters behind it
disp("Writing Video")
vidWriter.open;
vidWriter.writeVideo(videoAsFrames)
vidWriter.close;
disp("Finished process")
toc
end
