# run on biowulf2
# R/4.0.3
# /data/OGVFB_BG/scEiaD/2021_03_18
library(glue)
library(reticulate)
conda_dir <- '/data/mcgaugheyd/conda/'
git_dir <- '/home/mcgaugheyd/git/scEiaD/'
label_id_col <- 'cell_type_id'
label_name_col <- 'CellType'
use_python(glue('{conda_dir}/envs/integrate_scRNA/bin/python'), required = TRUE)
source_python( glue('{git_dir}/src/cell_type_predictor.py'))
library(Seurat)
library(tidyverse)


load('n_features-5000__transform-counts__partition-universe__covariate-batch__method-scVIprojectionSO__dims-8__preFilter.scEiaD.seuratV3.Rdata')

load('n_features-5000__transform-counts__partition-universe__covariate-batch__method-scVIprojectionSO__dims-8__preFilter.scEiaD__dist-0.1__neighbors-50.umapFilter.predictions.Rdata')

out <- integrated_obj@reductions$scVI@cell.embeddings %>% as_tibble(rownames = 'Barcode') %>% left_join(umap, by = 'Barcode') %>% 
  filter(study_accession != 'SRP131661')

features <- c(grep('scVI', colnames(integrated_obj@reductions$scVI@cell.embeddings), value = TRUE),
              'UMAP_1', 'UMAP_2', 'nCount_RNA', 'nFeature_RNA', 'percent.mt')

cluster_outlier <- function(out){
  groupings <- out %>% 
    filter(!is.na(CellType)) %>%  
    group_by(cluster, CellType) %>% 
    summarise(Count = n()) %>% 
    mutate(Perc = Count / sum(Count)) %>% 
    filter(Perc > 0.025)
  out %>% 
    left_join(groupings %>% 
                select(cluster, CellTypeKEEP = CellType)) %>% 
    filter(CellType == CellTypeKEEP) %>% 
    select(-CellTypeKEEP)
}

# remove celltype outliers
# we will removve 5% furthest from euclidean center
rm_outlier <- function(out, TM = FALSE){
  bc_retain <- list()
  for (i in out$CellType %>% unique){
    print(i)
    temp <- out %>% filter(CellType == i) %>% select(contains('scVI_')) %>% as.matrix()
    row.names(temp) <- out %>% filter(CellType == i) %>% pull(Barcode)
    scVI_mean <- colMeans(temp)
    euc_dist <- function(x1, x2) sqrt(sum((x1 - x2) ^ 2))
    D <- apply(as.matrix(temp), 1, function(x) euc_dist(scVI_mean, x))
    cutoff = quantile(D, probs = seq(0,1,0.01))[96]
    #print(glue("Retaining {D[D < cutoff] %>% names() %>% length()}" )) 
    #print(glue("Removing {D[D > cutoff] %>% names() %>% length()}" ))
    bc_retain[[i]] <- D[D < cutoff] %>% names()
  }
  out %>% filter(Barcode %in% (bc_retain %>% unlist()))
}

keep_cells <-  c("AC/HC_Precurs", "Amacrine Cells","Astrocytes",	"Bipolar Cells", "Cones",	"Horizontal Cells", "Muller Glia",	"Neurogenic Cells", "RPCs", "Photoreceptor Precursors","Rods", "Retinal Ganglion Cells", "Rod Bipolar Cells", "Microglia")

out <- cluster_outlier(out) %>% rm_outlier(.)
out <- out %>% mutate(CellType = replace(CellType, grepl('Bipolar', CellType), 'Bipolar Cells'),
                      CellType = replace(CellType, CellType %in% c('Early RPCs','Late RPCs'), 'RPCs')) %>% 
  filter(CellType %in% keep_cells)

out_human <- out %>% filter(organism == 'Homo sapiens')
out_mouse <- out %>% filter(organism == 'Mus musculus')
out_monk <- out %>% filter(organism == "Macaca fascicularis")



## train human,  predict others 

train_test_predictions <- scEiaD_classifier_train(
  inputMatrix=out_human, labelIdCol=label_id_col,
  labelNameCol=label_name_col,
  trainedModelFile='testing/human.out',featureCols=features, predProbThresh=.5,
  generateProb=TRUE,
  bad_cell_types = list("RPE/Margin/Periocular Mesenchyme/Lens Epithelial Cells", "Droplet", "Droplets", 'Doublet', 'Doublets', 'Smooth Muscle Cell', 'Choriocapillaris','Artery')
)
HSpredictions_mouse <- scEiaD_classifier_predict(inputMatrix=out_mouse,labelIdCol=label_id_col,
                                                 labelNameCol=label_name_col,
                                                 trainedModelFile='testing/human.out',
                                                 featureCols=features,  predProbThresh=.5) %>% 
  select(Barcode, predict_CellType = CellType) %>% 
  inner_join(out_mouse %>% select(Barcode, true_CellType = CellType))

HSpredictions_monk <- scEiaD_classifier_predict(inputMatrix=out_monk,labelIdCol=label_id_col,
                                                labelNameCol=label_name_col,
                                                trainedModelFile='testing/human.out',
                                                featureCols=features,  predProbThresh=.5) %>% 
  select(Barcode, predict_CellType = CellType) %>% 
  inner_join(out_monk %>% select(Barcode, true_CellType = CellType))


human_model__scoring <- bind_rows(
  (mltest::ml_test(factor(HSpredictions_monk$predict_CellType, levels = factor(HSpredictions_monk$true_CellType) %>% levels()), HSpredictions_monk$true_CellType))$F1 %>% enframe() %>% mutate(organism = 'Macaque'),
  (mltest::ml_test(factor(HSpredictions_mouse$predict_CellType, levels = factor(HSpredictions_mouse$true_CellType) %>% levels()), HSpredictions_mouse$true_CellType))$F1 %>% enframe() %>% mutate(organism = 'Mouse'))

#Train mouse, predict on human maca

train_test_predictions <- scEiaD_classifier_train(
  inputMatrix=out_mouse, labelIdCol=label_id_col,
  labelNameCol=label_name_col,
  trainedModelFile='testing/mouse.out',featureCols=features, predProbThresh=.5,
  generateProb=TRUE,
  bad_cell_types = list("RPE/Margin/Periocular Mesenchyme/Lens Epithelial Cells", "Droplet", "Droplets", 'Doublet', 'Doublets', 'Smooth Muscle Cell', 'Choriocapillaris','Artery')
)
MMpredictions_human <- scEiaD_classifier_predict(inputMatrix=out_human,labelIdCol=label_id_col,
                                                 labelNameCol=label_name_col,
                                                 trainedModelFile='testing/mouse.out',
                                                 featureCols=features,  predProbThresh=.5) %>% 
  select(Barcode, predict_CellType = CellType) %>% 
  inner_join(out_human %>% select(Barcode, true_CellType = CellType))

MMpredictions_monk <- scEiaD_classifier_predict(inputMatrix=out_monk,labelIdCol=label_id_col,
                                                labelNameCol=label_name_col,
                                                trainedModelFile='testing/mouse.out',
                                                featureCols=features,  predProbThresh=.5) %>% 
  select(Barcode, predict_CellType = CellType) %>% 
  inner_join(out_monk %>% select(Barcode, true_CellType = CellType))



mouse_model__scoring <- bind_rows(
  (mltest::ml_test(factor(MMpredictions_monk$predict_CellType, levels = factor(MMpredictions_monk$true_CellType) %>% levels()), MMpredictions_monk$true_CellType))$F1 %>% enframe() %>% mutate(organism = 'Macaque'),
  (mltest::ml_test(factor(MMpredictions_human$predict_CellType, levels = factor(MMpredictions_human$true_CellType) %>% levels()), MMpredictions_human$true_CellType))$F1 %>% enframe() %>% mutate(organism = 'Human'))


save(human_model__scoring, mouse_model__scoring, file = 'species_transfer_celltype_model.Rdata')
