# Global_SOC_Abundance_Persistence
Global soil organic carbon (SOC) profile analysis based on a subset of the International Soil Radiocarbon Database (ISRaD).


Author: Sophie von Fromm

Finishing Date: May 2024


This repository contains all the code to reproduce the analysis and all figures in the publication von Fromm et al. (2024), Global Change Biology.

The folder 'Code' contains all the R code, the folder 'Data' contains all the data needed to run the R Scripts and the folder 'Figure' contains all the figures and tables that are produced with the R code.

Only the data file 'ISRaD_flat_splined_filled_2023_03_09.csv' and the R scripts 'ISRaD_DataSoilProfile', 'ISRaD_GlobalDataDistribution', 'ISRaD_DataMapping_DataDistribution', 'ISRaD_RandomForest', and 'ISRaD_SoilR_ModelProfiles' are needed to reproduce the analysis and figures in the manuscript. All other files either contain raw data and/or are part of the data preparation and can be generated with the corresponding R scripts.

Folder data:
- ISRaD_extra_2023-02-08: Entire ISRaD database. Output file from ISRaD_Database.
- ISRaD_lyr_data_filtered_2023-02-08: Subset of the ISRaD layer data. Output file from ISRaD_Database.
- ISRaD_flat_splined_filled_2023-03-09: Final dataset for the data analysis. Output file from ISRaD_DataPreparation.

Folder code:
- ISRaD_Database: Code to extract, merge, filter and clean the original ISRaD database. Output files: ISRaD_extra_2023-02-08 and ISRaD_lyr_data_filtered_2023-02-08
- ISRaD_DataPreparation: Script to prepare and spline ISRaD dataset. Output file: ISRaD_flat_splined_filled_2023-03-09
- ISRaD_DataMapping_DataDistribution: Script to map data and analysis data distribution. Output file: Figures 1 and 2
- ISRaD_DataSoilProfile: Script to analyis SOC abundance and persistence at the profile level. Output file: Figure 3
- ISRaD_RandomForest: Script to perfrom random forest analysis. Output files: Figures 4, 5, and S3
- ISRaD_SoilR_ModelProfiles: Script to perform the depth-resolved modeling with SoilR. Output files: Figures 6, S4 and S5
- ISRaD_GlobalDataDistribution: Script to compare data distribution from ISRaD with global data distribution. Output file: Figure S1

Additional information about the International Soil Radiocarbon Database can be found here: https://github.com/International-Soil-Radiocarbon-Database/ISRaD
