# Data analysis: Profile data ISRaD #
# Relationship between 14C and depth/SOC #
# Sophie von Fromm #
# 08/03/2023 #

library(tidyverse)
library(ggpubr)
library(scales)
library(mlr3)
library(mlr3learners)
library(mlr3viz)
library(iml)
library(mlr3spatial)
library(mlr3spatiotempcv) 
library(RColorBrewer)

# Load filtered and splined data
lyr_data <- read_csv("./Data/ISRaD_flat_splined_filled_2023-03-09.csv") %>% 
  #remove layers that have CORG > 20
  filter(CORG_msp <= 20) %>% 
  mutate(MineralGroupsNew = case_when(
    MineralType == "low-activity clay" ~ "low-activity clay",
    MineralType == "amorphous" ~ "amorphous",
    pro_usda_soil_order == "Mollisols" ~ "high-activity clay",
    pro_usda_soil_order == "Spodosols" ~ "high-activity clay",
    pro_usda_soil_order == "Vertisols" ~ "high-activity clay",
    TRUE ~ "primary mineral"
  ))

# Check data
lyr_data %>% 
  dplyr::summarise(n_studies = n_distinct(entry_name),
                   n_sites = n_distinct(site_name),
                   n_profiles = n_distinct(id))

lyr_data %>% 
  dplyr::select(lyr_14c_msp, CORG_msp, UD, pro_MAT_mod, pro_AI, lyr_clay_mod) %>% 
  cor()

# Convert characters into factors
lyr_data$ClimateZone <- factor(lyr_data$ClimateZone,
                               levels = c("tundra/polar", "cold temperate",
                                          "warm temperate", "tropical", "arid"))

lyr_data$ClimateZoneAnd <- factor(lyr_data$ClimateZoneAnd,
                                  levels = c("volcanic soils", "tundra/polar", 
                                             "cold temperate", "warm temperate", 
                                             "tropical", "arid"))

lyr_data$MineralGroupsNew <- factor(lyr_data$MineralGroupsNew,
                                    levels = c("amorphous", 
                                               "primary mineral",
                                               "high-activity clay",
                                               "low-activity clay"))


## Define color code 
# cold, warm, tropical, arid
color_climate_wo_polar <- c("#bdd7e7", "#7fbf7b", "#1b7837", "#dfc27d")
# polar, cold, warm, tropical, arid
color_climate <- c("#3182bd", "#bdd7e7", "#7fbf7b", "#1b7837", "#dfc27d")
# amorphous, polar, cold, warm, tropical, arid
color_climate_w_amorph <- c("#c083be", "#3182bd", "#bdd7e7", "#7fbf7b", 
                            "#1b7837", "#dfc27d")
# amorphous, primary mineral, high-activity clay, low-activity clay
color_mineral <- c("#c083be", "#bf812d", "#bdbdbd", "#fc9272")

### Random Forest Analysis ###
set.seed(42)
lyr_data_sf <- sf::st_as_sf(lyr_data, coords = c("pro_long", "pro_lat"), crs = 4326)

# Filter data (only keep variables of interest)
rf_data_14c <- lyr_data_sf %>% 
  arrange(id) %>% 
  filter(ClimateZoneAnd != "volcanic soils") %>% 
  filter(ClimateZoneAnd != "tundra/polar") %>%
  dplyr::select(id, entry_name, UD, lyr_14c_msp,
                pro_MAT_mod, lyr_clay_mod, pro_AI)

rf_data_c <- lyr_data_sf %>% 
  arrange(id) %>% 
  filter(ClimateZoneAnd != "volcanic soils") %>% 
  filter(ClimateZoneAnd != "tundra/polar") %>%
  dplyr::select(id, entry_name, UD, CORG_msp,
                pro_MAT_mod, lyr_clay_mod, pro_AI)

## Set-up random forest
task_rf_14c <- as_task_regr_st(x = rf_data_14c %>%
                                 dplyr::select(-entry_name),
                               target = "lyr_14c_msp")

# task_rf_14c <- as_task_regr(x = rf_data_14c %>%
#                               dplyr::select(-entry_name),
#                             target = "lyr_14c_msp")

lrn_rf_14c <- lrn("regr.ranger", importance = "permutation",
                  num.trees = 1000)

# Add id as group for CV (same id kept together)
task_rf_14c$set_col_roles("id", roles = "group")
print(task_rf_14c)

task_rf_c <- as_task_regr_st(x = rf_data_c %>% 
                            dplyr::select(-entry_name), 
                          target = "CORG_msp")

lrn_rf_c <- lrn("regr.ranger", importance = "permutation",
                num.trees = 1000)

# Add id as group for CV (same id kept together)
task_rf_c$set_col_roles("id", roles = "group")
print(task_rf_c)

# cross-validation
resampling_14c <- rsmp("cv", folds = 10)
resampling_14c$instantiate(task_rf_14c)

# autoplot(resampling_14c, task_rf_14c, fold_id = c(1,2,5,10)) +
#   theme_bw(base_size = 14) +
#   theme(axis.text = element_blank())
# 
# ggsave(file = paste0("./Figure/ISRaD_msp_SOC_14C_RF_cv_", Sys.Date(),
#                      ".jpeg"), width = 12, height = 8)

resampling_c <- rsmp("cv", folds = 10)
resampling_c$instantiate(task_rf_c)

# autoplot(resampling_c, task_rf_c, fold_id = c(1,2,5,10))

## Train model & check performance
rr_14c <- mlr3::resample(task = task_rf_14c, learner = lrn_rf_14c, 
                         resampling = resampling_14c, store_models = TRUE)

rr_14c$aggregate(measures = msrs(c("regr.rmse", "regr.mse", "regr.rsq")))
rr_score_14c_ind <- rr_14c$score(measures = msrs(c("regr.rmse", "regr.mse", 
                                                   "regr.rsq")))

rr_14c_measure <- data.frame(regr_rmse = rr_score_14c_ind$regr.rmse,
                             regr_mse = rr_score_14c_ind$regr.mse,
                             regr_rsq = rr_score_14c_ind$regr.rsq)

skimr::skim_without_charts(rr_14c_measure)


rr_pred_14c <- rr_14c$prediction(predict_sets = "test")
rr_14c_prediction <- data.frame(truth = rr_pred_14c$truth,
                                response = rr_pred_14c$response)

vi_14c_all <- lapply(rr_14c$learners, function(x) x$model$variable.importance) 

vi_14c_sum <- vi_14c_all %>%   
  plyr::ldply() %>% 
  mutate(row_sum = rowSums(pick(where(is.numeric)))) %>% 
  mutate(UD = UD/row_sum*100,
         lyr_clay_mod = lyr_clay_mod/row_sum*100,
         pro_AI = pro_AI/row_sum*100,
         pro_MAT_mod = pro_MAT_mod/row_sum*100) %>% 
  dplyr::select(-row_sum) %>% 
  dplyr::summarise(across(everything(), list(median = median, mad = mad), 
                          .names = "{.col}.{.fn}")) %>% 
  pivot_longer(everything(), names_to = "names", values_to = "values") %>% 
  separate_wider_delim(names, ".", names = c("predictor", "measure")) %>% 
  pivot_wider(names_from = measure, values_from = values)

rr_14c_prediction %>% 
  ggplot(aes(x = response, y = truth)) +
  geom_point(shape = 21) +
  geom_rug() +
  geom_abline(intercept = 0, slope = 1, color = "red") +
  geom_smooth(method = "lm") +
  theme_bw(base_size = 16) +
  theme(axis.text = element_text(color = "black")) +
  scale_y_continuous(expression(paste("Observed ", Delta^14,"C [‰]")), 
                     limits = c(-1000,500), breaks = seq(-1000,500,250)) +
  scale_x_continuous(expression(paste("Predicted ", Delta^14,"C [‰]")), 
                     limits = c(-1000,300), breaks = seq(-1000,250,250)) +
  geom_text(aes(x = -720, y = 430), 
            label = paste("R² = ", round(median(rr_14c_measure$regr_rsq), 2), 
                          " ± ", round(mad(rr_14c_measure$regr_rsq), 2))) +
  geom_text(aes(x = -720, y = 370), 
            label = paste("MSE = ", round(median(rr_14c_measure$regr_mse), 0), 
                          " ± ", round(mad(rr_14c_measure$regr_mse), 0))) +
  geom_text(aes(x = -720, y = 310), 
            label = paste("RMSE = ", round(median(rr_14c_measure$regr_rmse), 0), 
                          " ± ", round(mad(rr_14c_measure$regr_rmse), 0), "‰"))

# Remove objects that are not needed anymore: free space
rm(rr_14c, rr_pred_14c, rr_14c_measure, rr_14c_prediction, rr_score_14c_ind,
   resampling_14c, task_rf_14c, lrn_rf_14c)

rr_c <- mlr3::resample(task = task_rf_c, learner = lrn_rf_c, 
                       resampling = resampling_c, store_models = TRUE)

rr_c$aggregate(measures = msrs(c("regr.rmse", "regr.mse", "regr.rsq")))

rr_score_c_ind <- rr_c$score(measures = msrs(c("regr.rmse", "regr.mse", "regr.rsq")))
rr_c_measure <- data.frame(regr_rmse = rr_score_c_ind$regr.rmse,
                           regr_mse = rr_score_c_ind$regr.mse,
                           regr_rsq = rr_score_c_ind$regr.rsq)

skimr::skim_without_charts(rr_c_measure)

rr_pred_c <- rr_c$prediction(predict_sets = "test")
rr_c_prediction <- data.frame(truth = rr_pred_c$truth,
                              response = rr_pred_c$response)

vi_c_all <- lapply(rr_c$learners, function(x) x$model$variable.importance)

vi_c_sum <- vi_c_all %>%   
  plyr::ldply() %>% 
  mutate(row_sum = rowSums(pick(where(is.numeric)))) %>% 
  mutate(UD = UD/row_sum*100,
         lyr_clay_mod = lyr_clay_mod/row_sum*100,
         pro_AI = pro_AI/row_sum*100,
         pro_MAT_mod = pro_MAT_mod/row_sum*100) %>% 
  dplyr::select(-row_sum) %>% 
  dplyr::summarise(across(everything(), list(median = median, mad = mad), 
                          .names = "{.col}.{.fn}")) %>% 
  pivot_longer(everything(), names_to = "names", values_to = "values") %>% 
  separate_wider_delim(names, ".", names = c("predictor", "measure")) %>% 
  pivot_wider(names_from = measure, values_from = values)

rr_c_prediction %>% 
  ggplot(aes(x = response, y = truth)) +
  geom_point(shape = 21) +
  geom_rug() +
  geom_abline(intercept = 0, slope = 1, color = "red") +
  geom_smooth(method = "lm") +
  theme_bw(base_size = 16) +
  theme(axis.text = element_text(color = "black")) +
  scale_y_continuous("Observed SOC [wt-%]", limits = c(0,25)) +
  scale_x_continuous("Predicted SOC [wt-%]", limits = c(0,20)) +
  geom_text(aes(x = 7, y = 24), 
            label = paste("R² = ", round(median(rr_c_measure$regr_rsq), 2), 
                          " ± ", round(mad(rr_c_measure$regr_rsq), 2))) +
  geom_text(aes(x = 7, y = 23), 
            label = paste("MSE = ", round(median(rr_c_measure$regr_mse), 2), 
                          " ± ", round(mad(rr_c_measure$regr_mse), 2))) +
  geom_text(aes(x = 7, y = 22), 
            label = paste("RMSE = ", round(median(rr_c_measure$regr_rmse), 2), 
                          " ± ", round(mad(rr_c_measure$regr_rmse), 2), "wt-%"))

# Remove objects that are not needed anymore: free space
rm(rr_c, rr_pred_c, rr_c_measure, rr_c_prediction, rr_score_c_ind,
   resampling_c, task_rf_c, lrn_rf_c)
  
## Variable importance
# Figure 4
vi_14c <- vi_14c_sum %>% 
  ggplot() +
  geom_bar(aes(x = reorder(predictor, -median), y = median, fill = predictor),
           stat = "identity") +
  geom_errorbar(aes(ymin = median-mad, ymax = median+mad, 
                    x = reorder(predictor, -median)), width = 0.2) +
  theme_bw(base_size = 16) +
  theme(axis.text = element_text(color = "black"),
        axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "none") +
  scale_y_continuous("Relative importance [%]", expand = c(0,0),
                     limits = c(0,45)) +
  scale_x_discrete("", labels = c("Depth", "MAT", "PET/MAP", "Clay content")) +
  scale_fill_manual(values = c("#a6611a", "#80cdc1", "#018571", "#dfc27d"))
  
vi_c <- vi_c_sum  %>% 
  ggplot() +
  geom_bar(aes(x = reorder(predictor, -median), y = median, fill = predictor),
           stat = "identity") +
  geom_errorbar(aes(ymin = median-mad, ymax = median+mad, 
                    x = reorder(predictor, -median)), width = 0.2) +
  theme_bw(base_size = 16) +
  theme(axis.text = element_text(color = "black"),
        axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "none") +
  scale_y_continuous("", expand = c(0,0),
                     limits = c(0,45)) +
  scale_x_discrete("", labels = c("PET/MAP", "MAT", "Depth", "Clay content")) +
  scale_fill_manual(values = c("#a6611a", "#80cdc1", "#018571", "#dfc27d"))
  
ggarrange(vi_14c, vi_c, labels = c("a) SOC persistence model",  "b) SOC abundance model"), 
          vjust = 2.5, hjust = c(-0.35,-0.35))
ggsave(file = paste0("./Figure/Figure_4_", Sys.Date(),
                     ".jpeg"), width = 10, height = 5)

### Partial Dependence plots

## 14C
rf_data_14c_pdp <- lyr_data %>% 
  arrange(id) %>% 
  filter(ClimateZoneAnd != "volcanic soils") %>% 
  filter(ClimateZoneAnd != "tundra/polar") %>%
  dplyr::select(id, entry_name, UD, lyr_14c_msp,
                pro_MAT_mod, lyr_clay_mod, pro_AI)


task_rf_14c_pdp <- as_task_regr(x = rf_data_14c_pdp %>%
                                  dplyr::select(-entry_name, -id),
                                target = "lyr_14c_msp")

lrn_rf_14c_pdp <- lrn("regr.ranger", importance = "permutation",
                      num.trees = 1000) 

lrn_rf_14c_pdp$train(task_rf_14c_pdp)

model_14c <- Predictor$new(lrn_rf_14c_pdp, data = rf_data_14c_pdp %>%  
                             dplyr::select(-id, -entry_name))

#MAT
effect_14c_ice_MAT <- FeatureEffects$new(model_14c, method = "ice",
                                         features = "pro_MAT_mod")
#AI
effect_14c_ice_AI <- FeatureEffects$new(model_14c, method = "ice",
                                        features = "pro_AI")

#UD
effect_14c_ice_UD <- FeatureEffects$new(model_14c, method = "ice", 
                                        features = "UD")

#clay
effect_14c_ice_clay <- FeatureEffects$new(model_14c, method = "ice", 
                                          features = "lyr_clay_mod")

## SOC
rf_data_c_pdp <- lyr_data %>% 
  arrange(id) %>% 
  filter(ClimateZoneAnd != "volcanic soils") %>% 
  filter(ClimateZoneAnd != "tundra/polar") %>%
  dplyr::select(id, entry_name, UD, CORG_msp,
                pro_MAT_mod, lyr_clay_mod, pro_AI)

task_rf_c_pdp <- as_task_regr(x = rf_data_c_pdp %>%
                                dplyr::select(-entry_name, -id),
                              target = "CORG_msp")

lrn_rf_c_pdp <- lrn("regr.ranger", importance = "permutation",
                      num.trees = 1000) 

lrn_rf_c_pdp$train(task_rf_c_pdp)

model_c <- Predictor$new(lrn_rf_c_pdp, data = rf_data_c_pdp %>%  
                             dplyr::select(-id, -entry_name))
#MAT
effect_c_ice_MAT <- FeatureEffects$new(model_c, method = "ice",
                                       features = "pro_MAT_mod")

#AI
effect_c_ice_AI <- FeatureEffects$new(model_c, method = "ice",
                                      features = "pro_AI")

#UD
effect_c_ice_UD <- FeatureEffects$new(model_c, method = "ice", 
                                      features = "UD")

#clay
effect_c_ice_clay <- FeatureEffects$new(model_c, method = "ice", 
                                        features = "lyr_clay_mod")

## Merge both PDP's
mat_ice_climate <- lyr_data %>% 
  arrange(id) %>%
  dplyr::filter(ClimateZoneAnd != "volcanic soils") %>% 
  dplyr::filter(ClimateZoneAnd != "tundra/polar") %>%
  dplyr::select(id, ClimateZoneAnd) %>% 
  rownames_to_column(var = ".id") %>% 
  dplyr::mutate(.id = as.integer(.id)) %>% 
  left_join(effect_14c_ice_MAT$effects$pro_MAT_mod$results %>% 
              dplyr::rename(pred_14c = .value), multiple = "all") %>% 
  left_join(effect_c_ice_MAT$effects$pro_MAT_mod$results %>% 
              dplyr::rename(pred_c = .value), multiple = "all") %>% 
  dplyr::group_by(ClimateZoneAnd, pro_MAT_mod) %>% 
  dplyr::mutate(pred_median_c = median(pred_c),
                pred_median_14c = median(pred_14c)) %>% 
  ungroup() %>% 
  arrange(pro_MAT_mod) %>% 
  dplyr::select(ClimateZoneAnd, pro_MAT_mod, pred_median_c, pred_median_14c) %>% 
  distinct(.keep_all = TRUE)
  
ai_ice_climate <- lyr_data %>% 
  arrange(id) %>%
  filter(ClimateZoneAnd != "volcanic soils") %>% 
  filter(ClimateZoneAnd != "tundra/polar") %>%
  dplyr::select(id, ClimateZoneAnd) %>% 
  rownames_to_column(var = ".id") %>% 
  mutate(.id = as.integer(.id)) %>% 
  left_join(effect_14c_ice_AI$effects$pro_AI$results %>% 
              dplyr::rename(pred_14c = .value), multiple = "all") %>% 
  left_join(effect_c_ice_AI$effects$pro_AI$results %>% 
              dplyr::rename(pred_c = .value), multiple = "all") %>% 
  dplyr::group_by(ClimateZoneAnd, pro_AI) %>% 
  dplyr::mutate(pred_median_c = median(pred_c),
                pred_median_14c = median(pred_14c)) %>% 
  ungroup() %>% 
  arrange(pro_AI) %>% 
  dplyr::select(ClimateZoneAnd, pro_AI, pred_median_c, pred_median_14c) %>% 
  distinct(.keep_all = TRUE)

ud_ice_climate <- lyr_data %>% 
  arrange(id) %>%
  filter(ClimateZoneAnd != "volcanic soils") %>% 
  filter(ClimateZoneAnd != "tundra/polar") %>%
  dplyr::select(id, ClimateZoneAnd) %>% 
  rownames_to_column(var = ".id") %>% 
  mutate(.id = as.integer(.id)) %>% 
  left_join(effect_14c_ice_UD$effects$UD$results %>% 
              dplyr::rename(pred_14c = .value), multiple = "all") %>% 
  left_join(effect_c_ice_UD$effects$UD$results %>% 
              dplyr::rename(pred_c = .value), multiple = "all") %>% 
  dplyr::group_by(ClimateZoneAnd, UD) %>% 
  dplyr::mutate(pred_median_c = median(pred_c),
                pred_median_14c = median(pred_14c)) %>% 
  ungroup() %>% 
  arrange(UD) %>% 
  dplyr::select(ClimateZoneAnd, UD, pred_median_c, pred_median_14c) %>% 
  distinct(.keep_all = TRUE)

clay_ice_climate <- lyr_data %>% 
  arrange(id) %>%
  filter(ClimateZoneAnd != "volcanic soils") %>% 
  filter(ClimateZoneAnd != "tundra/polar") %>%
  dplyr::select(id, ClimateZoneAnd) %>% 
  rownames_to_column(var = ".id") %>% 
  mutate(.id = as.integer(.id)) %>% 
  left_join(effect_14c_ice_clay$effects$lyr_clay_mod$results %>% 
              dplyr::rename(pred_14c = .value), multiple = "all") %>% 
  left_join(effect_c_ice_clay$effects$lyr_clay_mod$results %>% 
              dplyr::rename(pred_c = .value), multiple = "all") %>% 
  dplyr::group_by(ClimateZoneAnd, lyr_clay_mod) %>% 
  dplyr::mutate(pred_median_c = median(pred_c),
                pred_median_14c = median(pred_14c)) %>% 
  ungroup() %>% 
  arrange(lyr_clay_mod) %>% 
  dplyr::select(ClimateZoneAnd, lyr_clay_mod, pred_median_c, pred_median_14c) %>% 
  distinct(.keep_all = TRUE)

##PDP plots
mat_ice_pdp <- mat_ice_climate %>% 
  dplyr::rename(pred_value = pro_MAT_mod) %>% 
  mutate(predictor = "MAT [°C]")
ai_ice_pdp <- ai_ice_climate %>% 
  dplyr::rename(pred_value = pro_AI) %>% 
  mutate(predictor = "PET/MAP")
ud_ice_pdp <- ud_ice_climate %>% 
  dplyr::rename(pred_value = UD) %>% 
  mutate(predictor = "Depth [cm]")

pred_pdp <- rbind(mat_ice_pdp, ai_ice_pdp, ud_ice_pdp) %>% 
  tibble() 

pred_pdp$ClimateZoneAnd <- factor(pred_pdp$ClimateZoneAnd,
                                  levels = c("cold temperate",
                                             "warm temperate",
                                             "tropical",
                                             "arid"))

lyr_data_rug <- lyr_data %>% 
  filter(ClimateZoneAnd != "volcanic soils") %>%
  filter(ClimateZoneAnd != "tundra/polar") %>%
  group_by(ClimateZoneAnd) %>% 
  dplyr::distinct(ClimateZoneAnd, pro_MAT_mod, pro_AI) %>% 
  dplyr::rename('PET/MAP' = pro_AI,
                'MAT [°C]' = pro_MAT_mod) %>% 
  pivot_longer(!ClimateZoneAnd, values_to = "pred_value", names_to = "predictor")

# Group by ClimateZoneAnd and then Summarise 95% of data
quantiles_climate <- lyr_data %>% 
  filter(ClimateZoneAnd != "volcanic soils") %>%
  filter(ClimateZoneAnd != "tundra/polar") %>% 
  group_by(ClimateZoneAnd) %>% 
  dplyr::distinct(ClimateZoneAnd, pro_MAT_mod, pro_AI) %>% 
  dplyr::summarise(P5_MAT = quantile(pro_MAT_mod, 0.025),
                   P95_MAT = quantile(pro_MAT_mod, 0.975),
                   P5_PET_MAP = quantile(pro_AI, 0.025),
                   P95_PET_MAP = quantile(pro_AI, 0.975))

quantiles_depth <- lyr_data %>% 
  filter(ClimateZoneAnd != "volcanic soils") %>%
  filter(ClimateZoneAnd != "tundra/polar") %>% 
  group_by(ClimateZoneAnd) %>% 
  dplyr::summarise(P5_depth = quantile(UD, 0.025),
                   P95_depth = quantile(UD, 0.975))

quantiles <- quantiles_climate %>% 
  left_join(quantiles_depth)

## Code below comes from Benjamin Butler
#Split the data based on the predictor so that we can create new vectors
#that can be interpolated onto
pdp_split <- split(pred_pdp, f = pred_pdp$predictor)

#create the higher resolution vectors to interpolate onto

#one for MAT
pred_value_high_res_mat <- seq(min(pdp_split$`MAT [°C]`$pred_value),
                               max(pdp_split$`MAT [°C]`$pred_value),
                               length.out = 200)

#one for PET_MAP
pred_value_high_res_pet <- seq(min(pdp_split$`PET/MAP`$pred_value),
                               max(pdp_split$`PET/MAP`$pred_value),
                               length.out = 200) #the higher this is the great the resolution

pred_value_high_res_depth <- seq(min(pdp_split$`Depth [cm]`$pred_value),
                                 max(pdp_split$`Depth [cm]`$pred_value),
                                 length.out = 200)

#Split the data again by ClimateZoneAnd
pdp_split_mat <- split(pdp_split$`MAT [°C]`, f = pdp_split$`MAT [°C]`$ClimateZoneAnd)
pdp_split_pet <- split(pdp_split$`PET/MAP`, f = pdp_split$`PET/MAP`$ClimateZoneAnd)
pdp_split_depth <- split(pdp_split$`Depth [cm]`, f = pdp_split$`Depth [cm]`$ClimateZoneAnd)

#Create a function that will compute a natural spline of the data based on the
#higher resolution vectors
spline_data_14c <- function(data, new_x) {
  
  splined_data <- approx(x = data$pred_value,
                         y = data$pred_median_14c,
                         method = "linear",
                         xout = new_x) |> data.frame()
  
  names(splined_data) <- c("pred_value", "pred_median_14c")
  
  splined_data$ClimateZoneAnd <- unique(data$ClimateZoneAnd)
  
  splined_data$predictor <- unique(data$predictor)
  
  return(splined_data)
  
}

spline_data_c <- function(data, new_x) {
  
  splined_data <- approx(x = data$pred_value,
                         y = data$pred_median_c,
                         method = "linear",
                         xout = new_x) |> data.frame()
  
  names(splined_data) <- c("pred_value", "pred_median_c")
  
  splined_data$ClimateZoneAnd <- unique(data$ClimateZoneAnd)
  
  splined_data$predictor <- unique(data$predictor)
  
  return(splined_data)
  
}

#Apply the spline function to the MAT data
pdp_split_mat_splined_14c <- lapply(pdp_split_mat, spline_data_14c,
                                    new_x = pred_value_high_res_mat)

pdp_split_mat_splined_c <- lapply(pdp_split_mat, spline_data_c,
                                  new_x = pred_value_high_res_mat)

#Apply the spline function to the PET_MAP data
pdp_split_pet_splined_14c <- lapply(pdp_split_pet, spline_data_14c,
                                    new_x = pred_value_high_res_pet)

pdp_split_pet_splined_c <- lapply(pdp_split_pet, spline_data_c,
                                  new_x = pred_value_high_res_pet)

pdp_split_depth_splined_14c <- lapply(pdp_split_depth, spline_data_14c,
                                      new_x = pred_value_high_res_depth)

pdp_split_depth_splined_c <- lapply(pdp_split_depth, spline_data_c,
                                    new_x = pred_value_high_res_depth)

#Bind them all together
pdp_splined_14c <- do.call(rbind, c(pdp_split_mat_splined_14c,
                                    pdp_split_pet_splined_14c,
                                    pdp_split_depth_splined_14c))

pdp_splined_c <- do.call(rbind, c(pdp_split_mat_splined_c,
                                  pdp_split_pet_splined_c,
                                  pdp_split_depth_splined_c))

pdp_splined <- pdp_splined_14c %>% 
  left_join(pdp_splined_c) %>% 
  tibble()

#Split them again by ClimateZoneAnd so that we can run the outlier loop
pdp_splined_split <- split(pdp_splined, f = pdp_splined$ClimateZoneAnd)

#Just a quick check that I'm dealing with data in the right order because
#I'm about to right a clunky for loop that uses data in the pdp list and in the
#quantiles data table.
identical(as.character(quantiles$ClimateZoneAnd), names(pdp_splined_split))

#Run the loop that assigns outliers
for (i in 1:length(pdp_splined_split )) {
  
  pdp_splined_split[[i]] <- pdp_splined_split[[i]] %>% 
    mutate(outlier = case_when(
    predictor == "MAT [°C]" & 
      (pred_value < quantiles$P5_MAT[i] | pred_value > quantiles$P95_MAT[i]) ~ TRUE,
    predictor == "PET/MAP" & 
      (pred_value < quantiles$P5_PET_MAP[i] | pred_value > quantiles$P95_PET_MAP[i]) ~ TRUE,
    predictor == "Depth [cm]" & 
      (pred_value < quantiles$P5_depth[i] | pred_value > quantiles$P95_depth[i]) ~ TRUE,
    .default = FALSE
  ))
  
}

pdp_splined <- do.call(rbind, pdp_splined_split) %>% 
  tibble()

pdp_splined$ClimateZoneAnd <- factor(pdp_splined$ClimateZoneAnd,
                                     levels = c("cold temperate",
                                                "warm temperate",
                                                "tropical", "arid"))

pred_pdp_14c <- pdp_splined %>% 
  ggplot(aes(x = pred_value, color = ClimateZoneAnd)) +
  geom_line(aes(y = pred_median_14c), linewidth = 1.5, alpha = 0.3,
            linetype = "dashed") +
  geom_line(data = pdp_splined[-which(pdp_splined$outlier == TRUE), ], 
            aes(y = pred_median_14c),
            linewidth = 1.5) +
  geom_rug(data = lyr_data_rug, sides = "b") +
  theme_bw(base_size = 15) +
  theme(axis.text = element_text(color = "black"),
        legend.position = "top",
        plot.margin = margin(r = 5, l = 5, t = 5, b = 5),
        axis.title.x = element_blank()) +
  facet_wrap(~predictor, scales = "free_x") +
  scale_x_continuous("") +
  scale_y_continuous(expression(paste("Predicted  ", Delta^14, "C [‰]")),
                     expand = c(0,0), limits = c(-500,100)) +
  scale_color_manual("Climate grouping", values = color_climate_wo_polar)

pred_pdp_c <- pdp_splined %>% 
  ggplot(aes(x = pred_value, color = ClimateZoneAnd)) +
  geom_line(aes(y = pred_median_c), linewidth = 1.5, alpha = 0.3, 
            linetype = "dashed") +
  geom_line(data = pdp_splined[-which(pdp_splined$outlier == TRUE), ], 
            aes(y = pred_median_c),
            linewidth = 1.5) +
  geom_rug(data = lyr_data_rug, sides = "b") +
  theme_bw(base_size = 15) +
  theme(axis.text = element_text(color = "black"),
        legend.position = "top",
        panel.grid.minor.y = element_blank(),
        plot.margin = margin(r = 5, l = 20, t = 5, b = 10),
        axis.title.x = element_blank()) +
  facet_wrap(~predictor, scales = "free_x") +
  scale_x_continuous("") +
  scale_y_continuous("Predicted SOC [wt-%]",
                     expand = c(0,0), limits = c(0.2,10),
                     breaks = c(0.5,1,5,10), labels = c(0.5,1,5,10)) +
  coord_trans(y = "log10") +
  annotation_logticks(sides = "l", scaled = FALSE, short = unit(1.5,"mm"),
                      mid = unit(3,"mm"), long = unit(4,"mm")) +
  scale_color_manual("Climate grouping", values = color_climate_wo_polar)

## Figure A3
ggarrange(pred_pdp_14c, pred_pdp_c, common.legend = TRUE, nrow = 2,
          labels = c("a)", "b)"), label.x = c(0.01,0.01))
ggsave(file = paste0("./Figure/Figure_A3_", 
                     Sys.Date(), ".jpeg"), width = 9, height = 7)

### Point PDP plots (95th data range)
## Clay content
# select 95% of the data for each climate group
clay_p_sum <- lyr_data %>% 
  dplyr::filter(ClimateZoneAnd != "volcanic soils") %>% 
  dplyr::filter(ClimateZoneAnd != "tundra/polar") %>%
  group_by(ClimateZoneAnd) %>% 
  dplyr::select(ClimateZoneAnd, lyr_clay_mod) %>% 
  dplyr::summarise(P5 = quantile(lyr_clay_mod, 0.025),
                   P95 = quantile(lyr_clay_mod, 0.975))

clay_p <- clay_ice_climate %>%
  left_join(clay_p_sum) %>% 
  dplyr::mutate(
    lyr_clay_mod_p = case_when(
      lyr_clay_mod < P5 ~ NA,
      lyr_clay_mod > P95 ~ NA,
      TRUE ~ lyr_clay_mod),
    pred_median_14c_p = case_when(
      lyr_clay_mod < P5 ~ NA,
      lyr_clay_mod > P95 ~ NA,
      TRUE ~ pred_median_14c),
    pred_median_c_p = case_when(
      lyr_clay_mod < P5 ~ NA,
      lyr_clay_mod > P95 ~ NA,
      TRUE ~ pred_median_c))

clay_p$ClimateZoneAnd <- factor(clay_p$ClimateZoneAnd,
                                levels = c("cold temperate", "warm temperate",
                                           "tropical", "arid"))

clay_14c_p <- clay_p %>%
  ggplot(aes(color = ClimateZoneAnd)) +
  geom_smooth(aes(x = lyr_clay_mod_p, y = pred_median_14c_p), alpha = 0.2) +
  geom_path(aes(x = lyr_clay_mod, y = pred_median_14c), 
            linewidth = 1, alpha = 0.3, linetype = "dashed") +
  # geom_path(aes(x = lyr_clay_mod_p, y = pred_median_14c_p), 
  #           linewidth = 1) +
  geom_point(aes(x = lyr_clay_mod_p, y = pred_median_14c_p, size = lyr_clay_mod_p)) +
  theme_bw(base_size = 16) +
  theme(axis.text = element_text(color = "black"),
        plot.margin = margin(r = 5, l = 15, t = 10)) +
  scale_y_continuous(expression(paste("Median predicted ", Delta^14,"C [‰]")), 
                     limits = c(-300,0), expand = c(0,0)) +
  scale_x_continuous("", expand = c(0,0)) +
  scale_color_manual("Climate grouping", values = color_climate_wo_polar) +
  guides(color = guide_legend(override.aes = list(size = 2))) 

clay_c_p <- clay_p %>% 
  ggplot(aes(color = ClimateZoneAnd)) +
  geom_smooth(aes(x = lyr_clay_mod_p, y = pred_median_c_p), alpha = 0.2) +
  geom_path(aes(x = lyr_clay_mod, y = pred_median_c), 
            linewidth = 1, alpha = 0.3, linetype = "dashed") +
  # geom_path(aes(x = lyr_clay_mod_p, y = pred_median_c_p), 
  #           linewidth = 1) +
  geom_point(aes(x = lyr_clay_mod_p, y = pred_median_c_p, size = lyr_clay_mod_p)) +
  theme_bw(base_size = 16) +
  theme(axis.text = element_text(color = "black"),
        plot.margin = margin(r = 5, l = 25, b = 10)) +
  scale_y_continuous("Median predicted SOC [wt-%]", 
                     limits = c(0,2), expand = c(0,0)) +
  scale_x_continuous("Clay content [%]", expand = c(0,0)) +
  scale_color_manual("Climate grouping", values = color_climate_wo_polar) +
  guides(color = guide_legend(override.aes = list(size = 2)))

clay_p %>% 
  group_by(ClimateZoneAnd) %>% 
  dplyr::slice(which.min(lyr_clay_mod_p),
               which.max(lyr_clay_mod_p))

clay_14c_c_p <- clay_p %>% 
  ggplot() +
  geom_point(aes(y = pred_median_14c_p, x = pred_median_c_p, 
                 size = lyr_clay_mod_p, color = ClimateZoneAnd)) +
  theme_bw(base_size = 16) +
  theme(axis.text = element_text(color = "black"),
        panel.grid.minor.x = element_blank(),
        plot.margin = margin(r = 15, t = 10, b = 10, l = 5),
        legend.box = "vertical", 
        legend.spacing.y = unit(0.1, "cm")) +
  scale_y_continuous(expression(paste("Median predicted ", Delta^14,"C [‰]")), 
                     limits = c(-300,0), expand = c(0,0)) +
  scale_x_continuous("Median predicted SOC [wt-%]", expand = c(0,0), 
                     limits = c(0.3,2), breaks = c(0.5,1,2), labels = c(0.5,1,2)) +
  coord_trans(x = "log10") +
  annotation_logticks(sides = "b", scaled = FALSE, short = unit(1.5,"mm"),
                      mid = unit(3,"mm"), long = unit(4,"mm")) +
  geom_segment(x = 0.35, y = -95, xend = 0.67, yend = -195,
               color = color_climate_wo_polar[4],
               arrow = arrow(length = unit(0.5, "cm"))) +
  geom_segment(x = 0.73, y = -75, xend = 0.78, yend = -120,
               color = color_climate_wo_polar[3],
               arrow = arrow(length = unit(0.5, "cm"))) +
  geom_segment(x = 0.86, y = -120, xend = 1.3, yend = -200,
               color = color_climate_wo_polar[2],
               arrow = arrow(length = unit(0.5, "cm"))) +
  geom_segment(x = 1.1, y = -128, xend = 1.5, yend = -235,
               color = color_climate_wo_polar[1],
               arrow = arrow(length = unit(0.5, "cm"))) +
  scale_color_manual("Climate grouping", values = color_climate_wo_polar) + 
  scale_size_continuous("Clay content [%]") +
  guides(color = guide_legend(override.aes = list(size = 4)))

clay_p %>% 
  group_by(ClimateZoneAnd) %>% 
  slice(which.min(lyr_clay_mod_p), which.max(lyr_clay_mod_p))

## Figure 5   
ggarrange(ggarrange(clay_14c_p, clay_c_p, nrow = 2, legend = "none"),
          clay_14c_c_p, common.legend = TRUE, widths = c(0.8,1))
ggsave(file = paste0("./Figure/Figure_5_", 
                     Sys.Date(), ".jpeg"), width = 9, height = 7.5)

