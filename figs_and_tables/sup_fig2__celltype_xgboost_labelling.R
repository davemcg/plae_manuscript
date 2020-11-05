ct_processing <-  meta_filter %>% 
  #filter(CellType %in% common) %>% 
  filter(is.na(CellType) | CellType != 'Mast') %>% 
  filter(!(!Platform %in% c('10xv2','10xv3','DropSeq') & CellType_predict == 'Unlabelled'  )) %>% 
  filter(!(!Platform %in% c('10xv2','10xv3','DropSeq') & CellType_predict == 'Muller Glia Progenitor'  )) %>% 
  mutate(CellType = case_when(is.na(CellType) ~ 'Unlabelled', 
                              CellType == 'AC/HC_Precurs' ~ 'AC/HC Precursors',
                              TRUE ~ CellType)) %>% 
  mutate(CellType_predict = case_when(CellType_predict == 'RPC' ~ 'RPCs',
                                      CellType_predict == 'AC/HC_Precurs' ~ 'AC/HC Precursors',
                                      grepl('Mesenchymal', CellType_predict) ~ 'Endothelial',
                                      is.na(CellType_predict) ~ 'Unlabelled', 
                                      TRUE ~ CellType_predict)) 

##########
predictedCT <- ct_processing %>% 
  group_by(organism, CellType_predict) %>% 
  summarise(`Published Count` = n()) %>% pivot_wider(values_from = `Published Count`, names_from = c(organism))
colnames(predictedCT) <- c('CellType','HS Transferred','MF Transferred','MM Transferred')
prelabelledCT <- ct_processing %>% 
  group_by(organism, CellType) %>% 
  summarise(`Published Count` = n()) %>% pivot_wider(values_from = `Published Count`, names_from = c(organism))
colnames(prelabelledCT) <- c('CellType','HS Published','MF Published','MM Published')
joinedCT <- left_join(prelabelledCT, predictedCT)
joinedCT[is.na(joinedCT)] <- 0
ctTable <- joinedCT %>% flextable()
##########

ct_alluvial <- ct_processing %>% 
  select(CellType, CellType_predict) %>% 
  group_by(CellType, CellType_predict) %>% 
  summarise(Count = n()) %>% 
  ggplot(aes(y = sqrt(Count), axis1 = CellType, axis2 = CellType_predict)) +
  geom_alluvium(aes(fill = `CellType`), alpha = 0.8) +
  geom_stratum(alpha = 0) +
  ggrepel::geom_label_repel(stat = "stratum", 
                            direction = 'x', 
                            fill = alpha(c("white"),0.5),
                            size = 2, 
                            aes(label = after_stat(stratum))) +
  coord_cartesian(xlim = c(0.5,2.5)) +
  theme_void() +
  scale_fill_manual(values = c(pals::polychrome() %>% unname(),
                               pals::alphabet() %>% unname())) +
  theme(legend.position = "none")