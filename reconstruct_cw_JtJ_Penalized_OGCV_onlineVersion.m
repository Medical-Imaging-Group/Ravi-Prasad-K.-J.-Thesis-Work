function...
    [fwd_mesh , pj_error] =...
    reconstruct_cw_JtJ_Penalized_OGCV_onlineVersion...
                                    (fwd_fn,...
                                    data_fn,...
                                    iteration,...
                                    lambda,...
                                    output_fn,...
                                    filter_n,...
                                    penalty)


frequency =0;
tic;
% load fine mesh for fwd solve
%****************************************
% If not a workspace variable, load mesh
if ischar(fwd_fn)== 1
    fwd_mesh = load_mesh(fwd_fn);
end
if ~strcmp(fwd_mesh.type,'stnd')
    errordlg('Mesh type is incorrect','NIRFAST Error');
    error('Mesh type is incorrect');
end

%*******************************************************
% read data
%*******************************************************
%This is the calibrated experimental data or simulated data
anom = load_data(data_fn);
if ~isfield(anom,'paa')
    errordlg('Data not found or not properly formatted','NIRFAST Error');
    error('Data not found or not properly formatted');
end

% remove zeroed data
anom.paa(anom.link(:,3)==0,:) = [];
data_link = anom.link;

anom = anom.paa;
anom = log(anom(:,1)); %take log of amplitude
fwd_mesh.link = data_link;

%*******************************************************

% Initiate projection error
pj_error = [];
%*******************************************************
% Initiate log file
fid_log = fopen([output_fn '.log'],'w');
fprintf(fid_log,'Absoprtion reconstruction from amplitude only\n');
%     fprintf(fid_log,'Forward Mesh   = %s\n',fwd_fn);

fprintf(fid_log,'Frequency      = %f MHz\n',frequency);
fprintf(fid_log,'Data File      = %s\n',data_fn);
fprintf(fid_log,'Initial Reg    = %d\n',lambda);
fprintf(fid_log,'Filter         = %d\n',filter_n);
fprintf(fid_log,'Output Files   = %s_mua.sol\n',output_fn);
fprintf(fid_log,'               = %s_mus.sol\n',output_fn);
fprintf(fid_log,'Initial Guess mua = %d\n',fwd_mesh.mua(1));

for it = 1 : iteration
    
    % Calculate jacobian
    [J,data]=jacobian_stnd(fwd_mesh,frequency,recon_mesh);
    data.amplitude(data_link(:,3)==0,:) = [];
    
    % Set jacobian as Phase and Amplitude part instead of complex
    J = J.complete;
    
    % Read reference data
    clear ref;
    ref = log(data.amplitude);
    
    data_diff = (anom-ref);
    
    pj_error = [pj_error sum(abs(data_diff.^2))];
    
    disp('---------------------------------');
    disp(['Iteration Number          = ' num2str(it)]);
    disp(['Projection error          = ' num2str(pj_error(end))]);
    
    fprintf(fid_log,'---------------------------------\n');
    fprintf(fid_log,'Iteration Number          = %d\n',it);
    fprintf(fid_log,'Projection error          = %f\n',pj_error(end));
    
    if it ~= 1
        p = (pj_error(end-1)-pj_error(end))*100/pj_error(end-1);
        disp(['Projection error change   = ' num2str(p) '%']);
        fprintf(fid_log,'Projection error change   = %f %%\n',p);
        if p <= 2
            disp('---------------------------------');
            disp('STOPPING CRITERIA REACHED');
            fprintf(fid_log,'---------------------------------\n');
            fprintf(fid_log,'STOPPING CRITERIA REACHED\n');
            break
        end
    end
    % Normalize Jacobian wrt optical values
    % Normalize Jacobian wrt optical values
    N = fwd_mesh.mua;
    nn = length(fwd_mesh.nodes);
    % Normalise by looping through each node, rather than creating a
    % diagonal matrix and then multiplying - more efficient for large meshes
    for i = 1 : nn
        J(:,i) = J(:,i).*N(i,1);
    end
    clear nn N
    
    % % % % % %%%% Penalty terms
    
    if it ==1
        C_mua= ones(ncol,1);
        W = lambda.*diag( 1 ./ C_mua);
        %        foo =fwd_mesh.mua- 0.01;
        %  end
    else
        mua_P =foo;
        var_dmua = var(foo)
        if penalty ==1
            C_mua = abs(mua_P);
            % %          W = diag( 1e-4 ./ C_mua);
        elseif penalty ==2
            C_mua = sqrt(var_dmua+(mua_P.*mua_P));
            %         W = diag( 1e-4 ./ C_mua);
        elseif penalty ==3
            C_mua = var_dmua + (mua_P.*mua_P);
            %         W = diag( 1e-4 ./ C_mua);
        elseif penalty ==4
            C_mua = (var_dmua + (mua_P.*mua_P)).^2 ;
            %         W = diag( 1e-4 ./ C_mua);
        elseif penalty ==5
            a = 3;
            C_mua = (var_dmua + (mua_P.*mua_P)).^a ;
            %         W = diag( 1e-4 ./ C_mua);
        elseif penalty ==6
            a = 0.001;
            C_mua = (var_dmua + (mua_P.*mua_P)).^a ;
            %         W = diag( 1e-4 ./ C_mua);
            %           C_mua  = mua_P./tanh( mua_P) ;
            
        elseif penalty ==0
            C_mua= 1+ 0.*mua_P;
            %         W = diag( 1e-4 ./ C_mua);
        else
            disp('PENALTY IS NOT SPECICFIED');
            
        end
        
        clear muaP

        
        if penalty ~=0
            lambda = fminbnd(@(lambda)...
                GCV_penalized(J,data_diff,(1./C_mua),lambda),1e-6,100,...
                optimset('Display','iter', 'MaxIter', 1000,...
                'MaxFunEvals', 1000, 'TolX', 1e-16))
        end
        reg = ( lambda ./ C_mua);
        
    end
    
    disp(['Mua Regularization        = ' num2str(lambda)]);
    fprintf(fid_log,'Mua Regularization        = %f\n',lambda);
    
    % build hessian
    [~,ncol]=size(J);
    Hess = zeros(ncol);
    Hess = (J'*J);
    
    % Add regularisation to diagonal - looped rather than creating a matrix
    % as it is computational more efficient for large meshes
    for i = 1 : ncol
        Hess(i,i) = Hess(i,i) + reg(i);
    end
    
    foo = Hess\(J'*data_diff);
    
    
    
    % % % % % % % % % % % % % % % %
    
    foo1 = foo.*[fwd_mesh.mua];
    
    % Update values
    fwd_mesh.mua = fwd_mesh.mua + foo1;
    fwd_mesh.kappa = (1./(3.*(fwd_mesh.mus+fwd_mesh.mua)));
    
    
    clear foo1 Hess Hess_norm tmp data_diff G
    
    
    
    % We dont like -ve mua or mus! so if this happens, terminate
    if (any(fwd_mesh.mua<0) | any(fwd_mesh.mus<0))
        disp('---------------------------------');
        disp('-ve mua or mus calculated...not saving solution');
        fprintf(fid_log,'---------------------------------\n');
        fprintf(fid_log,'STOPPING CRITERIA REACHED\n');
        %              break
    end
    
    % % %         Filtering if needed!
    if filter_n > 1
        fwd_mesh = mean_filter(fwd_mesh,abs(filter_n));
    elseif filter_n < 1
        fwd_mesh = median_filter(fwd_mesh,abs(filter_n));
    end
    
    if it == 1
        fid = fopen([output_fn '_mua.sol'],'w');
    else
        fid = fopen([output_fn '_mua.sol'],'a');
    end
    fprintf(fid,'solution %g ',it);
    fprintf(fid,'-size=%g ',length(fwd_mesh.nodes));
    fprintf(fid,'-components=1 ');
    fprintf(fid,'-type=nodal\n');
    fprintf(fid,'%f ',fwd_mesh.mua);
    fprintf(fid,'\n');
    fclose(fid);
    
    if it == 1
        fid = fopen([output_fn '_mus.sol'],'w');
    else
        fid = fopen([output_fn '_mus.sol'],'a');
    end
    fprintf(fid,'solution %g ',it);
    fprintf(fid,'-size=%g ',length(fwd_mesh.nodes));
    fprintf(fid,'-components=1 ');
    fprintf(fid,'-type=nodal\n');
    fprintf(fid,'%f ',fwd_mesh.mus);
    fprintf(fid,'\n');
    fclose(fid);
end

% close log file!
time = toc;
fprintf(fid_log,'Computation TimeRegularization = %f\n',time);
fclose(fid_log);
end

function V_alpha = GCV_penalized(J,data_diff,Cp,alpha)

[n p] = size(J);

J_alpha = J*(( J'*J  + n*diag(alpha.*Cp))\J');

I = eye(n,n);
% alpha
% Golub's paper:-
% G. Golub and U. von Matt,
% "A Generalized cross-validation for large-scale problems," 
% J. Comput. Graph. Statist., {\bf 6}, 1--34 (1997).

V_alpha = (1/n) * norm( (I- J_alpha)*data_diff)^2 /...
    ((1/n) *trace( (I- J_alpha))^2);

end
