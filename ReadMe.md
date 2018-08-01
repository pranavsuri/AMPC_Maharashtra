# Help the Ag Industry
This repository contains the files related to the recruitment challenge given by SocialCops.

- **RPub Document:** http://rpubs.com/pranav_suri/help_the_ag_industry

- **Data:**  https://drive.google.com/drive/u/0/folders/0B-zoMsiXW40gZlNtNnlINEszRTg

#### Aim
To understand trends in APMC (Agricultural produce market committee)/Mandi price & quantity arrival data for different commodities in Maharashtra.

#### Files & Directories Index
- `AMPC_Maharashtra.Rmd` – Main experimentation (R Markdown)

- `AMPC_Maharashtra.R` – Extracted R Code from RMD file

- [Figs](/Figs) – Contains all plots from the analysis
  - `time_series_plots-1.png` –

  - `acf_plots-1.png` – Auto-Correlation Function plots to determine whether data is stationary or not

  - `time_series_decomposition-1.png` –

- [Data](/Data) – Contains data-exports from the analysis

  - `Outliers.csv` – Outlier values

  - `Seasonality_Type.csv` – Detected Seasonality Type

  - `Deseasonalized_Data.csv` – Deseasonalized Data

  - `MSP_Comparison_(Raw_&_Deseasonalized.csv)` – Contains a binary attribute that indicates whether deseasonalized/raw are lesser than Minimum Support Price

  - `Fluctuation_Data.csv` – Contains flagged values of quantities with high price fluctuation
