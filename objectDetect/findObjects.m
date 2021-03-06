function data = findObjects(data, opt)
  % retrieve objects and compute ICP
  addpath([fileparts( mfilename('fullpath') ) '/../mesaRender']);
  opt.furniture_class = { 'bed', 'sofa', 'chair', 'table', 'desk', 'bookshelf', 'shelves'};
  opt.tolPara = 0.07799;
  opt.shortlist = 3;
  if isfield(data, 'gt')
    cnt = 0;
    for rr = 1 : numel(data.label_names)
      if ismember(data.label_names{rr}, {'wall', 'floor', 'ceiling'}), continue; end 
      cnt = cnt + 1;
      regionMasks{cnt} = data.gt == rr;
    end
  else
    regionMasks = data.regionProp;
  end
  regionMasks = cat(3, regionMasks{:});
  data.planeData.siftRgb = data.siftRgb; data.planeData.siftD=data.siftD;
  feat = extract_region_to_structure_classes_features(im2uint8(data.images), data.depths, data.planeData, regionMasks);
  
  % actual retrieval
  load([fileparts( mfilename('fullpath') ) '/../config/retrivalSet.mat']);
  feat = normalize_zero_mean(feat, trainMeans);
  feat = normalize_unit_var(feat, trainStds);
  org_feat = feat;
  feat = (feat * Wx);
  fullDist = pdist2(feat, trainfeat);
  [distance, index] = sort(fullDist, 2); 

  total_fvc = struct('vertices', [], 'faces', []);
  result = struct('feature', [], 'mask', [], 'retrieval', ...
    struct('filename', {}, 'gtid', [], 'label', {}, 'rotate', [], ...
    'scaling', [], 'score', [], 'faces', [], 'vertices', [], 'depthErr', []) );
  
  for i=1:size(feat,1)
    fprintf('%d\n', i);
    result(i).feature = org_feat(i,:); result(i).mask = regionMasks(:,:,i);
    if sum(sum(regionMasks(:,:,i)))<opt.too_small, continue; end
    
    idx = 1; nRetrieval = 0; S = {};
    while nRetrieval<opt.maxRetrieval
      data2 = load( [fileparts( mfilename('fullpath') ) '/../processed_data/' trainInfo(index(i,idx)).filename] );
      data2 = data2.data;
      m2 = load( [fileparts( mfilename('fullpath') ) '/../mat/' trainInfo(index(i,idx)).filename] );
      m2 = m2.model;

      hasGT = 0;
      for j=1:numel(m2.objects) % find object model
        if (m2.objects{j}.uid==trainInfo(index(i,idx)).gtid)
          cmp = m2.objects{j}.mesh.comp;
          fvc = struct('vertices', [], 'faces', []); foffset = 0;
          for jj=1:numel(cmp)
            fvc.vertices = cat(1, fvc.vertices, cmp{jj}.vertices*m2.camera.R' );
            fvc.faces = cat(1, fvc.faces, cmp{jj}.faces+foffset);
            foffset = size(fvc.vertices, 1);
          end
          hasGT = 1; break;
        end
      end
      
      if ~hasGT || isempty(fvc.faces) % the matched object does not have object model
        idx = idx + 1;
        continue;
      end
      
      % region2region rotation
      fvc.vertices = fvc.vertices*m2.camera.R;
      reg1mask = regionMasks(:,:,i);
      reg2mask = data2.gt==trainInfo(index(i,idx)).gtid;
      coord1 = cat(2, data.X(reg1mask), data.Y(reg1mask), data.Z(reg1mask));
      coord2 = cat(2, data2.X(reg2mask), data2.Y(reg2mask), data2.Z(reg2mask));
      %simple fit
      bbox1 = get_bounding_box_3d(coord1); bbox2 = get_bounding_box_3d(coord2);      
      
      transferLabel = data2.label_names{ trainInfo(index(i,idx)).gtid };
      
      canRotate = ismember(transferLabel, opt.furniture_class);
      notManhattan = 1-max(abs(data.normal), [], 3);
      notManhattan = notManhattan(reg1mask);
      canRotate =  canRotate | mean(notManhattan)>(2*opt.tolPara);
     
      retr = findICP(data, opt, bbox1, bbox2, coord1, reg1mask, fvc, false, canRotate);
      
      if ~isempty(retr)
        nRetrieval = nRetrieval+1;
        retr.filename = trainInfo(index(i,idx)).filename;
        retr.gtid = trainInfo(index(i,idx)).gtid;
        retr.label = transferLabel;
        retr.score = distance(i,idx);
        S{nRetrieval}.bbox1 = bbox1; S{nRetrieval}.bbox2 = bbox2;
        S{nRetrieval}.coord1 = coord1;
        S{nRetrieval}.reg1mask = reg1mask;
        S{nRetrieval}.fvc = fvc;
        S{nRetrieval}.canRotate = canRotate;
        result(i).retrieval(nRetrieval) = retr;
      %else
      %  keyboard;
      end
      idx = idx + 1;
      if idx>(10*opt.maxRetrieval), 
        break; 
      end
    end
    
    if nRetrieval<opt.maxRetrieval
      continue;
    end
    [~, mini] = sort([result(i).retrieval.depthErr]);
    mini = mini(1:opt.shortlist);
    S = {S{mini}};
    result(i).retrieval = result(i).retrieval(mini);
    for j=1:opt.shortlist
      retr = findICP(data, opt, S{j}.bbox1, S{j}.bbox2, S{j}.coord1, S{j}.reg1mask, S{j}.fvc, true, S{j}.canRotate, result(i).retrieval(j));
      result(i).retrieval(j).vertices = retr.vertices; result(i).retrieval(j).faces = retr.faces;
      result(i).retrieval(j).rotate = retr.rotate; result(i).retrieval(j).scaling = retr.scaling;
      result(i).retrieval(j).depthErr = retr.depthErr;
    end
    
    [~, idx] = sort([result(i).retrieval.depthErr]); fvc = result(i).retrieval(idx(1));
    total_fvc.faces = cat(1, total_fvc.faces, fvc.faces+size(total_fvc.vertices,1));
    total_fvc.vertices = cat(1, total_fvc.vertices, fvc.vertices);
  end
  data.objectProp.info = result;
  data.objectProp.fvc = total_fvc;
end
