classdef DataProcess 
    % IMPORTANT NOTE: our in-vivo data was obtained using a Philips scanner, in which the 
    % acquired 2D k-space data produces images that are 1D-fftshifted along one dimension only 
    % (e.g. two separate halfs of the brain). The "extra_fftshift_flag" in our code compensates for  
    % this. However, if you work with data of a different scanner/vendor, you may need to perform
    % some extra fftshifts here an there. 
  
    % This toolbox currently supports only periodic sub-sampling for our in-vivo data. 
    % However, it supports all types of under-sampling for the brain phantom data.   
    
    
    properties          
        FileName        
       
        sigma         % width of the Gaussian Convolution kernel
        g             % Convolution kernel values
       
        SenseMaps     % sensitivity maps 

        extra_fftshift_flag  % this flag equals 1 for our in-vivo data, which produces images that inherently require 1D-fftshift. See explanation above
        rotangle  % rotation angle, used only for visualization (not during reconstruction) 
        
        R             % Under-sampling Reduction factor 
        
        GoldStandard
        GoldStandard4display
                                
        N        % Image size along one dimension. Each single-coil image (or k-space matrix) is NxN pixels. 
        NC        % number of coils
        N_center  % N_center = N/2+1. Index of middle pixel in k-space.
        
        % IMPORTANT NOTE: in the three following fields (and the code), we 
        % assume that the DC is NOT in the matrix center; rather, it is 
        % assumed that k-space is fftshifted.
        KspaceFullySampled  
        sampling_mask            
        KspaceSampled
        
        KspaceSampPattern_DC_in_center  % this is used only for visualization; here the DC is in the center.
        
        W          % weights for CORE reconstruction
        w_Roemer   % weights for combining multi-coil images into a sinlge image using the optimal method of Roemer et al., (1990) "The NMR phased array" MRM.
        
        mask           % the mask contains 0s outside the brain area. It is used for computing the rec error only inside the brain area
        mask4display   % this is the same mask, after rotation by rotangle

        CORE_conv_im   % This is the convolution image produced by a CORE unit (for a pre-defined kernel)
        CORE_conv_im4display  % same image, prepared for display
                
        cmin   % color range - max value  (for magnitude image display)
        cmax   % color range - min value  (for magnitude image display)
        
    end
    
    % ==================================================== %
    
    methods
        
        %% =========== Initialization ==============        
        function D = DataProcess(demo,sampling_scheme) % Initialization
                     
            switch demo
                
                case 'brain_phantom_example'
                    
                    D.rotangle = 0; % rotation angle for the final display
                    D.N = 256;      % Each image is NxN pixels
                    D.N_center = round(D.N/2)+1;
                    D.NC = 8;       % Number of coils
                    D.extra_fftshift_flag = 0;
                    D.cmin = 0;     % colormap lower limit (for figures)
                    D.cmax = 0.8;   % colormap upper limit (for figures)
                    D.FileName = 'Analytical_Brain_data_256';

                case {'In_vivo_example_1','In_vivo_example_2'}
                    
                    D.rotangle = -90; % rotation angle for the final display
                    D.N = 240;       % Each image is NxN pixels
                    D.N_center = round(D.N/2)+1;
                    D.NC = 32;       % Number of coils
                    D.extra_fftshift_flag = 1; % an extra fftshift along the 2nd dimension is required for data obtained in the 7T Phillips scanner at Leiden Univeristy
                    D.cmin = 0;      % colormap lower limit (for figures)
                    D.cmax = 0.12;   % colormap upper limit (for figures)
                    
                    switch demo
                        case 'In_vivo_example_1'
                            D.FileName = 'in_vivo_data_scan1'; %'In_vivo_data_1';
                        case 'In_vivo_example_2'
                            D.FileName = 'in_vivo_data_scan7';
                    end
            end
            
            
            %% =========== Load k-space data & Sensitivity Maps ==============
            switch demo
                % =========== In-vivo 7T brain scans data (courtesy of Prof. Andrew G. Webb) ==============
                
                case {'In_vivo_example_1','In_vivo_example_2'}
                    
                    % -------  Load High-Res K-space data -------------
                    load(['kspace_data\',D.FileName]);  % load data from the sub-folder named kspace_data
                    
                    % --------- fft-shift the K-space data  --------
                    for n = 1:D.NC  % make kspace uncentered
                        D.KspaceFullySampled(n,:,:) = squeeze(fftshift(kspace_data_original(n,:,:)));
                    end
                    D.SenseMaps = SenseMaps;
                    D.mask = mask;   % this masks is zero for all pixels outside the brain. It will be used later for NRMSE calculation.
                    D.mask4display = prep4display(D.mask,D.extra_fftshift_flag,D.rotangle,ones(D.N,D.N));
                    
                    D = sos_from_kspace(D);
                    
                    % ----- Load sampling mask ---------
                    load('sampling/Periodic_Samp_Pattern_240x240_R5');
               
                    
                    
                % =========== Analytic Brain Phantom 256x256 ==============
                case 'brain_phantom_example'
                    
                    % ------ load data (k-space + sensitivity maps + mask) ---------
                    load(['kspace_data\',D.FileName]);
                    D.SenseMaps = SenseMaps;
                    D.mask = mask;
                    D.mask4display = mask; % this is the same as mask because there's no need to rotate or fft-shift the data here
                    
                    % --------- Create K-space for the analytical brain phantom --------
                    for n = 1:D.NC
                        coil_image = squeeze(D.SenseMaps(n,:,:)).*brain_phantom;
                        D.KspaceFullySampled(n,:,:) = fft2(coil_image);
                    end
                    D = sos_from_kspace(D);
                    
                    % --------- K-space Sampling --------
                    % load sampling mask - all of these are with R=10 and
                    % are designed for 240x240 matrices
                    switch sampling_scheme
                        case 'periodic'
                            load('sampling/Ordered_Samp_Pattern_240x240_R10')
                        case 'variying-period'
                            load('sampling/Var-Ordered_Samp_Pattern_240x240_R10')
                        case 'variable-density'
                            load('sampling/Var-Dens_Samp_Pattern_240x240_R10')
                        case 'random'
                            load('sampling/random uniform_Samp_Pattern_240x240_R10')
                    end
                    
            end % switch demo
            
            % Prepare sampling matrix (KspaceSampPattern was loaded from a file)
            D.KspaceSampPattern_DC_in_center = KspaceSampPattern;
            D.sampling_mask = fftshift(KspaceSampPattern);
            
            % --------- Sample K-space --------
            D = calc_kspace_samples(D);
            
            % ------ Compute Gold Standard -------
            D = calc_gold_standard_Roemer(D);
                                    
            
        end
        
        %% ----------------- calc gold standard - Roemer's method ------------------
        function D = calc_gold_standard_Roemer(D)            
            % This function computes an image from a (reconstructed)
            % fully-sampled k-space data of NC coils using the method of:
            % Roemer et al., (1990) "The NMR phased array" MRM
            % See also equation (14) in the CORE-PI paper. 
            
            % ------ step 1: compute weights for optimal combination  ------
            w_Roemer =zeros(D.NC,D.N,D.N);
            
            for n=1:D.NC
                w_Roemer(n,:,:)=D.SenseMaps(n,:,:).*conj(D.SenseMaps(n,:,:))./sum(D.SenseMaps.*conj(D.SenseMaps),1);
            end
            
            % ---- step2: calc gold standard, i.e., fully sampled reference ---
            gold_Roemer = zeros(D.N,D.N);
            for n=1:D.NC  % n = coil index
                kspace_ncoil = squeeze(D.KspaceFullySampled(n,:,:));
                im_ncoil = ifft2(kspace_ncoil);
                gold_Roemer = gold_Roemer+im_ncoil./squeeze(D.SenseMaps(n,:,:)).*squeeze(w_Roemer(n,:,:));
            end
            
            % replace NaN values with 0 values
            gold_Roemer_vec = gold_Roemer(:);
            NaN_inds = find(isnan(abs(gold_Roemer_vec))==1);
            gold_Roemer_vec(NaN_inds) = 0;
            gold_Roemer2 = reshape(gold_Roemer_vec,D.N,D.N);
             
            D.GoldStandard = gold_Roemer2;
            D.GoldStandard4display = prep4display(D.GoldStandard,D.extra_fftshift_flag,D.rotangle,D.mask4display);
            D.w_Roemer = w_Roemer;
            
        end
        
        %% --------------- calc K-space samples -----------
        function D = calc_kspace_samples(D)
            
            for n = 1:D.NC
                D.KspaceSampled(n,:,:) = squeeze(D.KspaceFullySampled(n,:,:)).*D.sampling_mask;
            end
        end
        
        %% ------------ create Gaussian kernel ----------------
        function D = create_gaussian_kernel(D,sigma)
              
              D.sigma = sigma;        
              g = zeros(1,D.N);
              
              for i=1:D.N
                 g(i)=exp(-(((i-D.N_center)/(sigma))^2)/2);
              end
              
              D.g = g/sum(g(:));
              
          
        end
        
        %% ------------------- Calc CORE reconstruction ----------------------------
        % For explanations see Appendix A and Algorithm I in the CORE-PI paper.
        
        function D = CORE(D)
            
            % =========== preparation ============
            g = D.g;
            
            [NC,N,N]=size(D.SenseMaps);
   
            Kx_set_for_uncentered_DC = find(D.sampling_mask(1,:)==1); % these are indices of sampled columns
             
            Kx_vals_for_fft = fftshift(  [-(D.N_center-1):1:(D.N_center-2)]  );
            Kx_vals_for_fft = Kx_vals_for_fft(Kx_set_for_uncentered_DC); % These are VALUES (not indices) of the k-number. They are necessary for manual calculation of the FFT, which is performed below.
            inds_to_fix = find(Kx_vals_for_fft < (-D.N_center+1) );
            Kx_vals_for_fft(inds_to_fix) = Kx_vals_for_fft(inds_to_fix) + D.N;
            
            % ================= 
            NK = length(Kx_vals_for_fft); % number of acquired k-space columns (for a single coil)
            N_CK = NC*NK; % (Ncoils)X(number of sampled columns)
         
            % ================= Calc. R_mat (ifft of sampled K-lines) =================
            % This part impelements the equation R_i_k_x(y) = IFFT{SenseMaps_coil_n(kx,ky)}
            R_mat = zeros(N_CK ,N);
            % This matrix is named "R_mat" (because "R" is used for the under-sampling reduction factor).
            % R_mat is used to create the convolution image.
            % Each ROW of R_mat holds the 1-D ifft of data that was sampled from a
            % single k-space column of a single coil. Hence, the number of
            % rows in P is N_CK=(Ncoils)X(number of sampled columns).
            
            for n=1:D.NC
                kspace_ncoil_sampled = squeeze(D.KspaceSampled(n,:,:));
                for kk=1:NK
                    sampled_vec = kspace_ncoil_sampled(:,Kx_set_for_uncentered_DC(kk));
                    address     = n+(kk-1)*D.NC;
                    R_mat(address,:)=ifft(sampled_vec.');
                end
            end % for n
            
            %=========================== calc M_y0 matrix & Weights =====================
            
            disp('calculating weights')
            D.W   = zeros(N_CK,N,N);
            x_vec = ((1:N)-1)/N;
            
            % for every line:
            for y0 = 1:N
                SenseMaps_y0_all_coils = squeeze(D.SenseMaps(:,y0,:));
                
                % ----- Construct "M_y0" - matrix of modulated Sensitivity Maps  ------------
                % According to the paper (see Appendix A, page 212, bottom
                % left paragraph):
                % M_y0(n_ck,x) = SenseMaps(n_ck,x,y0)*exp(-i*Kx(nk)*x)
                
                M = [];
                for kline_ind = 1:NK
                    kx_val = Kx_vals_for_fft(kline_ind); % We work with uncenetered DC in kspace everywhere
                    Ex           = exp(-2*pi*j*(kx_val)*x_vec); % Manual computation of Fourier transform. e^(-j*kx*x) = exponent per x
                    Ex_all_coils = repmat( Ex,[NC 1]);
                    M_block_nk = SenseMaps_y0_all_coils.*Ex_all_coils;
                    M=[M ;  M_block_nk  ];
                end
                
                % ------ calc W for y0 ----------
                % This code section computes the weights for all pixels in row y0
                % simultaneously. It was originally developed for this paper:
                % Azhari H, Sodickson DK, Edelman RR. "Rapid MR imaging by sensitivity
                % profile indexing and deconvolution reconstruction (SPID)", MRI (2003)
                % (c) D.K. Sodickson (2003)
                pointermtx  = convmtx(g,N).';
                G_convmtx = pointermtx(ceil(N/2)+1:ceil(3*N/2),:);
                G_convmtx(1:ceil(N/2)-1,:)  = G_convmtx(1:ceil(N/2)-1,:) + pointermtx(ceil(3*N/2)+1:2*N-1,:);
                G_convmtx(ceil(N/2)+1:N,:) = G_convmtx(ceil(N/2)+1:N,:) + pointermtx(1:ceil(N/2),:);
                M_inv = pinv(M);
                D.W(:,y0,:) = (G_convmtx*M_inv).';  % This is the Least-Squares solution of the underdetermined system  G = M_inv x W  for row y0
                G = G_convmtx.' ;
                
            end	%for y0
            
            % =================  Convolved Image =============
            % This part calculates the convolution image h(x,y) = conv(f(x,y),g(x))
            % The convolution image is created row-after-row (for y0=1:N),
            % where for each row the calculation is performed for all x
            % values at once.
            % This part implements the equation h(x,y0)= SumOverKx(SumOverCoils(W(i,kx,x)*R(i,kx,y0)))
            
            conv_im=zeros(N,N);
            
            for y0=1:N;
                W_y = squeeze(D.W(:,y0,:));
                R_y = R_mat(:,y0);
                conv_im(y0,:)= (R_y.')*W_y;
            end
            D.CORE_conv_im = conv_im;
            D.CORE_conv_im4display = prep4display(D.CORE_conv_im,D.extra_fftshift_flag,D.rotangle,D.mask4display);
            
        end
        
%         %% ================ CORE-PI =========
         function D=CORE_PI(D)
%             
%             % -------- create filters 
%             % get the four wavelet filters associaited with the pre-defined
%             % wavelet type:
%             switch D.wavelet_type
%                 case 'db2' % default for CORE-PI
%                     HP_D =[-0.4830    0.8365   -0.2241   -0.1294];
%                     HP_R = [-0.1294   -0.2241    0.8365   -0.4830];
%                     LP_D = [-0.1294    0.2241    0.8365    0.4830];
%                     LP_R = [0.4830    0.8365    0.2241   -0.1294];
%                 case 'haar'
%                     HP_D = [-0.7071 0.7071];
%                     HP_R = [0.7071 -0.7071];
%                     LP_D = [0.7071 0.7071];
%                     LP_R = [0.7071 0.7071];
%                 case 'coif1'
%                     HP_D = [0.0727    0.3379   -0.8526    0.3849    0.0727   -0.0157];
%                     HP_R = [-0.0157    0.0727    0.3849   -0.8526    0.3379    0.0727];
%                     LP_D = [-0.0157   -0.0727    0.3849    0.8526    0.3379   -0.0727];
%                     LP_R = [-0.0727    0.3379    0.8526    0.3849   -0.0727   -0.0157];
%                 case 'sym4'
%                     HP_D = [-0.0322   -0.0126    0.0992    0.2979   -0.8037    0.4976    0.0296   -0.0758];
%                     HP_R = [-0.0758    0.0296    0.4976   -0.8037    0.2979    0.0992   -0.0126   -0.0322];
%                     LP_D = [-0.0758   -0.0296    0.4976    0.8037    0.2979   -0.0992   -0.0126    0.0322];
%                     LP_R = [0.0322   -0.0126   -0.0992    0.2979    0.8037    0.4976   -0.0296   -0.0758];
%                 otherwise
%                     % NOTICE: this requires Matlab's wavelet toolbox
%                     [LP_D,HP_D,LP_R,HP_R] = wfilters(D.wavelet_type);
%             end
%             
%             % LP_D = Low-Pass Decomposition Filter
%             % HP_D = High-Pass Decomposition Filter
%             % LP_R = Low-Pass Reconstruction Filter
%             % HP_D = High-Pass Reconstruction Filter
%             
%             % zero-pad the above filters to the k-space length:
%             LF = length(LP_D); % length of one filter
%             LP_Dec_kernel = [zeros(1,D.N_center - LF/2-1) LP_D  zeros(1,D.N_center-LF/2-1)]; % Low-Pass Decomposition Filter of length N
%             HP_Dec_kernel = [zeros(1,D.N_center - LF/2-1) HP_D  zeros(1,D.N_center-LF/2-1)]; % High-Pass Decomposition Filter of length N
%             
%             % ------ calc approximation coefficients ----
%             disp('CORE-PI - Low Pass (approximation) channel')
%             D.g = LP_Dec_kernel;
            
            D = CORE(D);
            
            % save results in D array
            if D.extra_fftshift_flag==1
                D.conv_image_LP_channel = fftshift(D.CORE_conv_im,2);
            else
                D.conv_image_LP_channel = D.CORE_conv_im;
            end
            D.conv_image_LP_channel_4display = prep4display(D.conv_image_LP_channel,0,D.rotangle,D.mask4display);
            
            
            % ------ calc detail coefficients ----
            disp('CORE-PI - High Pass (details) channel')
            D.g = HP_Dec_kernel;
            
            D = CORE(D);
            
            % save results in D array
            if D.extra_fftshift_flag==1
                D.conv_image_HP_channel = fftshift(D.CORE_conv_im,2);
            else
                D.conv_image_HP_channel = D.CORE_conv_im;
            end
            D.conv_image_HP_channel_4display = prep4display(D.conv_image_HP_channel,0,D.rotangle,D.mask4display);
            
            
            % -------------- Image Reconstruction ---------------
            % Here we reconstruct each row of the image separately
            % according to equation [13] in the CORE-PI paper.
            % This is done using the SWT synthesis (reconstruction)
            % filters LP_R & HP_D that were constructed above.
            % Specifically, for any row y0, we perform these steps:
            % 1. Convolve row y0 of the LP image with the LP_R filter
            % 2. Convolve row y0 of the HP image with the HP_R filter
            % 3. Sum the results. This gives us row y0 in the reconstructed
            %    image.
            
            % Convolve LP and HP rows with appropriate SWT synthesis filters
            for y0 = 1:D.N  
                LP_row_rec(y0,:) = (wconv1(D.conv_image_LP_channel(y0,:).',LP_R)).'; % perform convolution
                HP_row_rec(y0,:) = (wconv1(D.conv_image_HP_channel(y0,:).',HP_R)).'; % perform convolution
            end
            % Restore original size (this is required since the convolution
            % produces a vector that has more than N pixels)
            LF = length(LP_R); % Length of Filter
            inds_to_keep = (LF/2):1:(size(LP_row_rec,2)-LF/2);
            
            LP_row_rec = LP_row_rec(:,inds_to_keep)/2;
            HP_row_rec = HP_row_rec(:,inds_to_keep)/2;
            
            % Sum the results
            D.CORE_PI_Rec = LP_row_rec + HP_row_rec; % sum the LP and HP channels to obtain final recon
            
            % prepare final image for a nice display (rotate + fftshift + apply mask)            
            D.CORE_PI_Rec4display = prep4display(D.CORE_PI_Rec,0,D.rotangle,D.mask4display);
                       
        end
      
        
        function   D = sos_from_kspace(D)
            % calc Sum Of Squares from fully-sampled k-space data
            Images = zeros(D.N,D.N,D.NC); % the fully-sampled data in space domain.
            
            for coil_i=1:D.NC
                kspace_coil_i     = squeeze(D.KspaceFullySampled(coil_i,:,:)); % extract fully-sampled data of coil #i
                Images(:,:,coil_i) = fftshift(ifft2(fftshift(kspace_coil_i))); % compute image
            end
            
            %D.sos = sos(Images);  % use an external function to compute SOS
            
        end  % sos_from_k_space
        
        
    end % methods
    
end % classdef